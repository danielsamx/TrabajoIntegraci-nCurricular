function passed = test_full_pipeline()
    % TEST_FULL_PIPELINE Prueba de extremo a extremo de main.m sin hardware ni red.
    %
    % TEST_FULL_PIPELINE End-to-end test of main.m without hardware or network.
    %
    % Escenario A / Scenario A: LLM simulado ('mock'), prótesis 'SIM', Myo simulado
    %   - el LLM se invoca en TODOS los ciclos / the LLM is called on EVERY cycle
    %   - 0 fallbacks, 100 % comandos aceptados / 0 fallbacks, 100 % commands accepted
    %   - en la fase D2 domina 'B' y en la fase D3 domina 'C'
    %     'B' dominates the D2 phase and 'C' dominates the D3 phase
    %
    % Escenario B / Scenario B: LLM inalcanzable (127.0.0.1:9)
    %   - el LLM se sigue invocando en TODOS los ciclos / still called on EVERY cycle
    %   - el fallback LDA decide en todos los ciclos / the LDA fallback decides every cycle
    %   - el LDA reconoce la fase D2 como 'B' / the LDA recognizes the D2 phase as 'B'
    %
    % DECISIÓN: simulación no en tiempo real (40 muestras nuevas por ciclo) | RAZÓN: el
    %   guion 'auto' cambia de gesto cada 10 ciclos exactos, así las fases son deterministas
    %   | ALTERNATIVA DESCARTADA: tiempo real (fases dependientes de la carga del PC)
    % DECISION: non-real-time simulation (40 new samples per cycle) | REASON: the 'auto'
    %   script changes gesture every exactly 10 cycles, so phases are deterministic |
    %   DISCARDED ALTERNATIVE: real time (phases depend on PC load)
    %
    % Salidas / Outputs:
    %   passed : true si ambos escenarios pasan / true if both scenarios pass
    %
    % Ejemplo / Example:
    %   ok = test_full_pipeline();

    root = add_project_paths();
    fprintf('\n--- test_full_pipeline ---\n');
    results = true(0);

    [calib, prompt_llm] = load_or_build_configs(root);
    log_dir = fullfile(tempdir, 'protesis_test_logs');
    prosthesis_cfg = struct('ip', '127.0.0.1', 'port', 0, 'endpoint', '/api/command', ...
        'timeout', 0.5, 'protocol', 'SIM', 'max_consecutive_failures', 5, ...
        'safe_command', '#R');

    % Escenario A: LLM simulado / Scenario A: mock LLM -------------------------------------
    llm_cfg = base_llm_config();
    llm_cfg.transport = 'mock';
    recorder = containers.Map('KeyType', 'double', 'ValueType', 'any');
    rng(11);
    prosthesis_simulator('reset');
    summary = main('Source', 'simulated', 'SimRealtime', false, 'MaxCycles', 40, ...
        'Period', 0, 'Verbose', false, 'LogDir', log_dir, 'LlmConfig', llm_cfg, ...
        'ProsthesisConfig', prosthesis_cfg, 'PromptConfig', prompt_llm, ...
        'Calibration', calib, 'OnCycle', @(info) record(recorder, info));

    results(end + 1) = check('A: 40 ciclos / cycles', summary.cycles == 40);
    results(end + 1) = check('A: LLM invocado en cada ciclo / called every cycle', ...
        summary.llm_calls == summary.cycles);
    results(end + 1) = check('A: 0 fallbacks', summary.fallback_count == 0);
    results(end + 1) = check('A: todas las respuestas válidas / all answers valid', ...
        summary.llm_valid == summary.cycles);
    results(end + 1) = check('A: prótesis aceptó todo / prosthesis accepted all', ...
        summary.prosthesis_ok == summary.cycles);
    results(end + 1) = check('A: fase REST -> #R / REST phase', ...
        phase_majority(recorder, 3:10, 'raw') == "#R");
    results(end + 1) = check('A: fase D2 -> B / D2 phase', ...
        phase_majority(recorder, 13:20, 'raw') == "B");
    results(end + 1) = check('A: fase D3 -> C / D3 phase', ...
        phase_majority(recorder, 33:40, 'raw') == "C");
    state = prosthesis_simulator('state');
    results(end + 1) = check('A: simulador recibió comandos / simulator got commands', ...
        state.commands >= 40);

    % Escenario B: LLM inalcanzable / Scenario B: unreachable LLM ---------------------------
    llm_cfg = base_llm_config();
    llm_cfg.ip = '127.0.0.1';
    llm_cfg.ports = 9;
    llm_cfg.timeout = 0.3;
    recorder = containers.Map('KeyType', 'double', 'ValueType', 'any');
    rng(12);
    summary = main('Source', 'simulated', 'SimRealtime', false, 'MaxCycles', 20, ...
        'Period', 0, 'Verbose', false, 'LogDir', log_dir, 'LlmConfig', llm_cfg, ...
        'ProsthesisConfig', prosthesis_cfg, 'PromptConfig', prompt_llm, ...
        'Calibration', calib, 'OnCycle', @(info) record(recorder, info));

    results(end + 1) = check('B: LLM invocado en cada ciclo / called every cycle', ...
        summary.llm_calls == summary.cycles && summary.cycles == 20);
    results(end + 1) = check('B: fallback LDA en cada ciclo / LDA fallback every cycle', ...
        summary.fallback_count == summary.cycles);
    results(end + 1) = check('B: prótesis aceptó todo / prosthesis accepted all', ...
        summary.prosthesis_ok == summary.cycles);
    results(end + 1) = check('B: LDA fase D2 -> B / LDA D2 phase', ...
        phase_majority(recorder, 13:20, 'raw') == "B");

    passed = all(results);
    fprintf('--- test_full_pipeline: %s (%d/%d) ---\n', pass_text(passed), sum(results), ...
        numel(results));
end

% -------------------------------------------------------------------------------------------
function keep_running = record(recorder, info)
    % RECORD Guarda el comando de cada ciclo (callback OnCycle).
    % RECORD Stores each cycle's command (OnCycle callback).
    recorder(info.cycle) = struct('raw', info.command, 'sent', info.smoothed_command, ...
        'source', info.source);
    keep_running = true;
end

% -------------------------------------------------------------------------------------------
function winner = phase_majority(recorder, cycles, field)
    % PHASE_MAJORITY Comando más frecuente en un rango de ciclos (como string).
    % PHASE_MAJORITY Most frequent command in a cycle range (as string).
    values = strings(0);
    for c = cycles
        if isKey(recorder, c)
            item = recorder(c);
            values(end + 1) = string(item.(field)); %#ok<AGROW>
        end
    end
    if isempty(values)
        winner = "";
        return;
    end
    [labels, ~, idx] = unique(values);
    counts = accumarray(idx(:), 1);
    [~, best] = max(counts);
    winner = labels(best);
    fprintf('      ciclos %d-%d: %s\n', cycles(1), cycles(end), strjoin(values, ' '));
end

% -------------------------------------------------------------------------------------------
function cfg = base_llm_config()
    % BASE_LLM_CONFIG Configuración del LLM en memoria (no toca config/).
    % BASE_LLM_CONFIG In-memory LLM configuration (does not touch config/).
    cfg = struct('ip', '127.0.0.1', 'ips', {{}}, 'endpoint', '/v1/chat/completions', ...
        'api_key', 'lm-studio', 'timeout', 0.5, 'cycle_budget', [], 'max_tokens', 200, ...
        'temperature', 0, 'top_p', 1, 'stop', {{['}', newline]}}, ...
        'use_json_schema', false, 'ports', 1234, ...
        'models', {{'qwen2.5-vl-7b-instruct'}}, 'mode', 'sequential', 'transport', 'http');
end

% -------------------------------------------------------------------------------------------
function [calib, prompt_llm] = load_or_build_configs(root)
    % LOAD_OR_BUILD_CONFIGS Usa config/ si existe; si no, genera copias temporales.
    % LOAD_OR_BUILD_CONFIGS Uses config/ if present; otherwise builds temporary copies.
    calib_file = fullfile(root, 'config', 'calibration.mat');
    if isfile(calib_file)
        loaded = load(calib_file, 'calib');
        calib = loaded.calib;
    else
        calib = calibrate('Source', 'simulated', 'UserId', 'test', 'IsDefault', true, ...
            'Interactive', false, 'Reps', 8, 'Seed', 42, ...
            'SavePath', [tempname, '.mat']);
    end
    prompt_file = fullfile(root, 'config', 'prompt-llm.mat');
    if isfile(prompt_file)
        loaded = load(prompt_file, 'prompt_llm');
        prompt_llm = loaded.prompt_llm;
    else
        prompt_llm = create_prompt_llm_config('save_path', [tempname, '.mat']);
    end
    prompt_llm.image.render_mode = 'raster';   % más rápido en tests / faster in tests
end

% -------------------------------------------------------------------------------------------
function ok = check(name, condition)
    % CHECK Imprime el resultado de una comprobación. / Prints a check result.
    ok = logical(condition);
    fprintf('  [%s] %s\n', pass_text(ok), name);
end

% -------------------------------------------------------------------------------------------
function text = pass_text(ok)
    % PASS_TEXT 'PASS' o 'FAIL'.
    if ok
        text = 'PASS';
    else
        text = 'FAIL';
    end
end

% -------------------------------------------------------------------------------------------
function root = add_project_paths()
    % ADD_PROJECT_PATHS Permite ejecutar el test de forma independiente.
    % ADD_PROJECT_PATHS Allows running the test standalone.
    root = fileparts(fileparts(mfilename('fullpath')));
    folders = {'config', 'acquisition', 'processing', 'llm', 'prosthesis', 'utils', 'tests'};
    addpath(root);
    for k = 1:numel(folders)
        addpath(fullfile(root, folders{k}));
    end
end
