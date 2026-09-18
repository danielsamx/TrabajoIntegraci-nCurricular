function passed = test_llm_connection(varargin)
    % TEST_LLM_CONNECTION Prueba la conexión con LM Studio en TODOS los puertos configurados.
    %
    % TEST_LLM_CONNECTION Tests the LM Studio connection on ALL configured ports.
    %
    % Para cada puerto / For each port:
    %   1. GET /v1/models -> el servidor responde y el modelo está cargado
    %      the server answers and the model is loaded
    %   2. POST /v1/chat/completions con TEXTO + IMAGEN (ejemplo del índice) dos veces
    %      (arranque en frío y en caliente) -> JSON válido y latencia medida
    %      POST with TEXT + IMAGE (index example) twice (cold and warm start)
    %      -> valid JSON and measured latency
    %   3. Aviso si la latencia en caliente supera server_llm.timeout
    %      Warning if the warm latency exceeds server_llm.timeout
    %
    % DECISIÓN: timeout amplio (30 s) solo en el test | RAZÓN: la primera petición carga el
    %   modelo y el codificador de visión; queremos medir, no fallar por el arranque en frío
    %   | ALTERNATIVA DESCARTADA: usar el timeout de producción (0.5 s) y fallar siempre
    % DECISION: large timeout (30 s) only in the test | REASON: the first request loads the
    %   model and vision encoder; we want to measure, not fail on cold start |
    %   DISCARDED ALTERNATIVE: using the production timeout (0.5 s) and always failing
    %
    % Entradas (nombre-valor) / Inputs (name-value):
    %   'Config'  : struct server_llm (por defecto config/server-llm.mat)
    %   'Timeout' : timeout del test en s / test timeout in s (30)
    %
    % Salidas / Outputs:
    %   passed : true si todos los puertos devuelven un JSON válido
    %            true if every port returns a valid JSON
    %
    % Ejemplo / Example:
    %   ok = test_llm_connection();
    %   ok = test_llm_connection('Timeout', 60);

    root = add_project_paths();
    fprintf('\n--- test_llm_connection ---\n');

    p = inputParser;
    addParameter(p, 'Config', []);
    addParameter(p, 'Timeout', 30);
    parse(p, varargin{:});

    passed = false;
    try
        cfg = p.Results.Config;
        if isempty(cfg)
            loaded = load(fullfile(root, 'config', 'server-llm.mat'), 'server_llm');
            cfg = loaded.server_llm;
        end
        loaded = load(fullfile(root, 'config', 'prompt-llm.mat'), 'prompt_llm');
        prompt_llm = loaded.prompt_llm;
    catch err
        fprintf('  [FAIL] configuración / configuration: %s (ejecute setup / run setup)\n', ...
            err.message);
        return;
    end

    production_timeout = cfg.timeout;
    payload = ['RMS:[0.06,0.08,0.21,0.82,0.19,0.05,0.44,0.07]|', ...
        'MAV:[0.05,0.07,0.18,0.79,0.17,0.04,0.41,0.06]|STATE:ACTIVE|', ...
        'CALIB:[D1=5+6,D2=4+7,D3=3+7,D4=2+8,D5=1+8]|PREV:#R:000|T:10240'];
    rms_values = [0.06, 0.08, 0.21, 0.82, 0.19, 0.05, 0.44, 0.07];
    img_path = generate_heatmap(rms_values, 'ACTIVE', 10240, struct( ...
        'width', prompt_llm.image.width, 'height', prompt_llm.image.height, ...
        'render_mode', prompt_llm.image.render_mode, ...
        'out_path', fullfile(tempdir, 'test_llm_connection.png')));

    port_ok = false(1, numel(cfg.ports));
    for k = 1:numel(cfg.ports)
        port = cfg.ports(k);
        ip = cfg.ip;
        if isfield(cfg, 'ips') && numel(cfg.ips) >= k && ~isempty(cfg.ips{k})
            ip = cfg.ips{k};
        end
        models = cellstr(cfg.models);
        model = models{min(k, numel(models))};
        fprintf('  Puerto / port %d (%s, modelo / model %s)\n', port, ip, model);

        % 1) /v1/models
        try
            opts = weboptions('Timeout', 5, 'ContentType', 'json', ...
                'HeaderFields', {'Authorization', ['Bearer ', cfg.api_key]});
            listing = webread(sprintf('http://%s:%d/v1/models', ip, port), opts);
            ids = model_ids(listing);
            fprintf('    [PASS] /v1/models -> %s\n', strjoin(ids, ', '));
            if ~any(strcmpi(ids, model))
                fprintf(['    [WARN] "%s" no aparece en la lista; LM Studio puede cargarlo ', ...
                    'bajo demanda / not listed; LM Studio may load it on demand\n'], model);
            end
        catch err
            fprintf('    [FAIL] /v1/models: %s\n', err.message);
            continue;
        end

        % 2) Clasificación TEXTO + IMAGEN / TEXT + IMAGE classification
        port_cfg = cfg;
        port_cfg.ports = port;
        port_cfg.models = {model};
        port_cfg.ips = {ip};
        port_cfg.mode = 'sequential';
        port_cfg.transport = 'http';
        port_cfg.timeout = p.Results.Timeout;
        port_cfg.cycle_budget = p.Results.Timeout;
        latencies = nan(1, 2);
        valid = false(1, 2);
        for attempt = 1:2
            send_input_llm('reset');
            response = send_input_llm(port_cfg, prompt_llm, payload, img_path);
            latencies(attempt) = response.latency_ms;
            if ~response.ok
                fprintf('    [FAIL] chat/completions (%d): %s\n', attempt, response.error);
                continue;
            end
            [cmd, ok, parse_error] = parse_llm_response(response.content);
            [valid(attempt), reason] = is_valid_response(cmd);
            if ~ok
                reason = parse_error;
            end
            fprintf('    [%s] intento / attempt %d: %.0f ms -> %s %s\n', ...
                pass_text(valid(attempt)), attempt, response.latency_ms, ...
                strtrim(response.content), reason);
            if valid(attempt) && ~strcmp(cmd.command, 'B')
                fprintf('    [WARN] se esperaba / expected "B" (índice / index)\n');
            end
        end
        port_ok(k) = any(valid);

        if isfinite(latencies(2)) && latencies(2) > 1000 * production_timeout
            fprintf(['    [WARN] latencia en caliente %.0f ms > timeout %.0f ms: aumente ', ...
                'server_llm.timeout o use imagen raster 320x240 / warm latency above ', ...
                'timeout: raise it or use a 320x240 raster image\n'], latencies(2), ...
                1000 * production_timeout);
        end
    end

    passed = all(port_ok);
    fprintf('--- test_llm_connection: %s (%d/%d puertos / ports) ---\n', ...
        pass_text(passed), sum(port_ok), numel(port_ok));
end

% -------------------------------------------------------------------------------------------
function ids = model_ids(listing)
    % MODEL_IDS Extrae los id de modelo de /v1/models. / Extracts model ids.
    ids = {};
    if ~isstruct(listing) || ~isfield(listing, 'data')
        return;
    end
    data = listing.data;
    if isstruct(data)
        data = num2cell(data);
    end
    for k = 1:numel(data)
        if isfield(data{k}, 'id')
            ids{end + 1} = char(data{k}.id); %#ok<AGROW>
        end
    end
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
