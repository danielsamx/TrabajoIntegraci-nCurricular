function passed = test_parallel_ports()
    % TEST_PARALLEL_PORTS Prueba la abstracción de puertos: N=1 y N=4 con el MISMO código.
    %
    % TEST_PARALLEL_PORTS Tests the port abstraction: N=1 and N=4 with the SAME code.
    %
    % Comprueba / Checks (transporte 'mock', sin red / 'mock' transport, no network):
    %   1. N=1 round-robin      -> siempre 1234 / always 1234
    %   2. N=4 round-robin      -> 1234, 1235, 1236, 1237, 1234, ...
    %   3. N=4 sequential       -> siempre 1234 / always 1234
    %   4. N=4 con 1235 caído   -> failover a 1236, nunca 1235, sin fallos
    %      N=4 with 1235 down   -> failover to 1236, never 1235, no failures
    %   5. Todos los puertos caídos -> ok=false (main.m activará el LDA)
    %      All ports down           -> ok=false (main.m will trigger the LDA)
    %   6. main.m con N=1 y N=4 produce la MISMA secuencia de comandos; solo cambia el
    %      reparto de puertos / main.m with N=1 and N=4 produces the SAME command
    %      sequence; only the port distribution changes
    %
    % DECISIÓN: la única diferencia entre los casos es el struct de configuración |
    %   RAZÓN: demuestra la restricción 5 (N=1 -> N=4 cambiando solo server-llm.mat) |
    %   ALTERNATIVA DESCARTADA: funciones distintas por número de puertos
    % DECISION: the only difference between cases is the configuration struct |
    %   REASON: demonstrates constraint 5 (N=1 -> N=4 changing only server-llm.mat) |
    %   DISCARDED ALTERNATIVE: different functions per number of ports
    %
    % Salidas / Outputs:
    %   passed : true si todas las comprobaciones pasan / true if all checks pass
    %
    % Ejemplo / Example:
    %   ok = test_parallel_ports();

    root = add_project_paths();
    fprintf('\n--- test_parallel_ports ---\n');
    results = true(0);

    rms_values = [0.06, 0.08, 0.21, 0.82, 0.19, 0.05, 0.44, 0.07];
    payload = ['RMS:[0.06,0.08,0.21,0.82,0.19,0.05,0.44,0.07]|', ...
        'MAV:[0.05,0.07,0.18,0.79,0.17,0.04,0.41,0.06]|STATE:ACTIVE|', ...
        'CALIB:[D1=5+6,D2=4+7,D3=3+7,D4=2+8,D5=1+8]|PREV:#R:000|T:10240'];
    img_path = generate_heatmap(rms_values, 'ACTIVE', 10240, struct( ...
        'render_mode', 'raster', 'out_path', fullfile(tempdir, 'test_parallel_ports.png')));
    prompt = 'system prompt de prueba / test system prompt';

    cfg1 = mock_config(1234, 'round-robin');
    cfg4 = mock_config([1234, 1235, 1236, 1237], 'round-robin');
    cfg4_seq = mock_config([1234, 1235, 1236, 1237], 'sequential');

    % 1-3) Reparto / distribution
    [ports1, ok1] = run_calls(cfg1, prompt, payload, img_path, 8);
    results(end + 1) = check('N=1 round-robin -> 1234', all(ports1 == 1234) && all(ok1));
    [ports4, ok4] = run_calls(cfg4, prompt, payload, img_path, 8);
    results(end + 1) = check('N=4 round-robin -> 1234..1237 x2', ...
        isequal(ports4, [1234, 1235, 1236, 1237, 1234, 1235, 1236, 1237]) && all(ok4));
    [ports4s, ok4s] = run_calls(cfg4_seq, prompt, payload, img_path, 4);
    results(end + 1) = check('N=4 sequential -> 1234', all(ports4s == 1234) && all(ok4s));

    % 4) Failover
    cfg_fail = cfg4;
    cfg_fail.mock_fail_ports = 1235;
    [ports_f, ok_f, attempts_f] = run_calls(cfg_fail, prompt, payload, img_path, 8);
    results(end + 1) = check('failover: nunca 1235 / never 1235', ...
        ~any(ports_f == 1235) && all(ok_f));
    results(end + 1) = check('failover: 1235 -> 1236 (2 intentos / attempts)', ...
        ports_f(2) == 1236 && attempts_f(2) == 2);

    % 5) Todos caídos / all down
    cfg_down = cfg4;
    cfg_down.mock_fail_ports = cfg4.ports;
    [~, ok_d] = run_calls(cfg_down, prompt, payload, img_path, 2);
    results(end + 1) = check('todos caídos -> ok=false / all down', ~any(ok_d));

    % Validez de la respuesta / answer validity
    send_input_llm('reset');
    response = send_input_llm(cfg4, prompt, payload, img_path);
    [cmd, parsed] = parse_llm_response(response.content);
    results(end + 1) = check('respuesta mock válida y = B / valid mock answer = B', ...
        parsed && is_valid_response(cmd) && strcmp(cmd.command, 'B'));

    % 6) main.m con N=1 y N=4 / main.m with N=1 and N=4
    [calib, prompt_llm] = load_configs(root);
    prosthesis_cfg = struct('ip', '127.0.0.1', 'port', 0, 'endpoint', '/api/command', ...
        'timeout', 0.5, 'protocol', 'SIM', 'max_consecutive_failures', 5, ...
        'safe_command', '#R');
    common = {'Source', 'simulated', 'SimRealtime', false, 'MaxCycles', 24, ...
        'Period', 0, 'Verbose', false, 'LogDir', fullfile(tempdir, 'protesis_test_logs'), ...
        'ProsthesisConfig', prosthesis_cfg, 'PromptConfig', prompt_llm, ...
        'Calibration', calib};

    seq1 = containers.Map('KeyType', 'double', 'ValueType', 'any');
    rng(21);
    summary1 = main(common{:}, 'LlmConfig', cfg1, 'OnCycle', @(i) record(seq1, i));
    seq4 = containers.Map('KeyType', 'double', 'ValueType', 'any');
    rng(21);
    summary4 = main(common{:}, 'LlmConfig', cfg4, 'OnCycle', @(i) record(seq4, i));

    commands1 = strjoin(string(values(seq1)), ' ');
    commands4 = strjoin(string(values(seq4)), ' ');
    fprintf('      N=1: %s\n      N=4: %s\n', commands1, commands4);
    results(end + 1) = check('main N=1 == main N=4 (comandos / commands)', ...
        commands1 == commands4);
    results(end + 1) = check('main N=1: 24 llamadas al puerto 1234 / calls to 1234', ...
        isequal(summary1.ports, 1234) && isequal(summary1.port_counts, 24));
    results(end + 1) = check('main N=4: 6 llamadas por puerto / calls per port', ...
        isequal(sort(summary4.ports), [1234, 1235, 1236, 1237]) && ...
        all(summary4.port_counts == 6));

    passed = all(results);
    fprintf('--- test_parallel_ports: %s (%d/%d) ---\n', pass_text(passed), sum(results), ...
        numel(results));
end

% -------------------------------------------------------------------------------------------
function [ports, oks, attempts] = run_calls(cfg, prompt, payload, img_path, n)
    % RUN_CALLS Ejecuta n llamadas y registra el puerto usado.
    % RUN_CALLS Runs n calls and records the port used.
    send_input_llm('reset');
    ports = nan(1, n);
    oks = false(1, n);
    attempts = zeros(1, n);
    for k = 1:n
        [response, port] = send_input_llm(cfg, prompt, payload, img_path);
        ports(k) = port;
        oks(k) = response.ok;
        attempts(k) = response.attempts;
    end
    fprintf('      %-12s N=%d -> [%s]\n', cfg.mode, numel(cfg.ports), num2str(ports));
end

% -------------------------------------------------------------------------------------------
function keep_running = record(store, info)
    % RECORD Guarda el comando enviado de cada ciclo. / Stores each cycle's sent command.
    store(info.cycle) = sprintf('%s:%d', info.smoothed_command, round(info.smoothed_value));
    keep_running = true;
end

% -------------------------------------------------------------------------------------------
function cfg = mock_config(ports, mode)
    % MOCK_CONFIG Configuración en memoria con transporte simulado.
    % MOCK_CONFIG In-memory configuration with the mock transport.
    cfg = struct('ip', '127.0.0.1', 'ips', {{}}, 'endpoint', '/v1/chat/completions', ...
        'api_key', 'lm-studio', 'timeout', 0.5, 'cycle_budget', [], 'max_tokens', 200, ...
        'temperature', 0, 'top_p', 1, 'stop', {{['}', newline]}}, ...
        'use_json_schema', false, 'ports', ports, ...
        'models', {{'qwen2.5-vl-7b-instruct'}}, 'mode', mode, 'transport', 'mock', ...
        'mock_fail_ports', []);
end

% -------------------------------------------------------------------------------------------
function [calib, prompt_llm] = load_configs(root)
    % LOAD_CONFIGS Carga o genera calibración y prompt (sin tocar config/ si faltan).
    % LOAD_CONFIGS Loads or builds calibration and prompt (without touching config/).
    calib_file = fullfile(root, 'config', 'calibration.mat');
    if isfile(calib_file)
        loaded = load(calib_file, 'calib');
        calib = loaded.calib;
    else
        calib = calibrate('Source', 'simulated', 'UserId', 'test', 'IsDefault', true, ...
            'Interactive', false, 'Reps', 8, 'Seed', 42, 'SavePath', [tempname, '.mat']);
    end
    prompt_file = fullfile(root, 'config', 'prompt-llm.mat');
    if isfile(prompt_file)
        loaded = load(prompt_file, 'prompt_llm');
        prompt_llm = loaded.prompt_llm;
    else
        prompt_llm = create_prompt_llm_config('save_path', [tempname, '.mat']);
    end
    prompt_llm.image.render_mode = 'raster';
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
