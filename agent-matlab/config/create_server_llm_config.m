function server_llm = create_server_llm_config(varargin)
    % CREATE_SERVER_LLM_CONFIG Genera config/server-llm.mat (servidor LM Studio).
    %
    % CREATE_SERVER_LLM_CONFIG Generates config/server-llm.mat (LM Studio server).
    %
    % Cualquier campo puede sobrescribirse con pares nombre-valor.
    % Any field can be overridden with name-value pairs.
    %
    % DECISIÓN: usar struct con array de puertos | RAZÓN: permite N=1 y N=4 sin cambiar
    %   código | ALTERNATIVA DESCARTADA: variables separadas por puerto (no escala)
    % DECISION: use a struct with a port array | REASON: supports N=1 and N=4 without code
    %   changes | DISCARDED ALTERNATIVE: separate variables per port (does not scale)
    %
    % DECISIÓN: generador con pares nombre-valor en lugar de editar el .mat a mano |
    %   RAZÓN: un .mat es binario; regenerarlo es reproducible y queda documentado |
    %   ALTERNATIVA DESCARTADA: editar el .mat con load/save manual (propenso a errores)
    % DECISION: generator with name-value pairs instead of hand-editing the .mat |
    %   REASON: a .mat is binary; regenerating it is reproducible and documented |
    %   DISCARDED ALTERNATIVE: editing the .mat with manual load/save (error-prone)
    %
    % DECISIÓN: stop tokens construidos con newline/char(13) | RAZÓN: en MATLAB '}\n' entre
    %   comillas simples es literalmente "barra invertida + n", no un salto de línea |
    %   ALTERNATIVA DESCARTADA: {'}\n', ...} literal (nunca coincidiría)
    % DECISION: stop tokens built with newline/char(13) | REASON: in MATLAB '}\n' inside
    %   single quotes is literally "backslash + n", not a line break |
    %   DISCARDED ALTERNATIVE: literal {'}\n', ...} (would never match)
    %
    % Ejemplos / Examples:
    %   create_server_llm_config();                                       % N = 1
    %   create_server_llm_config('ip', '192.168.1.50');
    %   create_server_llm_config('ports', [1234 1235 1236 1237], ...
    %                            'mode', 'round-robin');                  % N = 4
    %   create_server_llm_config('timeout', 2.0);                         % GPU lenta / slow
    %
    % Salidas / Outputs:
    %   server_llm : struct guardado / saved struct

    root = fileparts(fileparts(mfilename('fullpath')));
    save_path = fullfile(root, 'config', 'server-llm.mat');

    server_llm = struct();
    server_llm.ip = '192.168.1.100';              % IP del servidor LM Studio / server IP
    server_llm.ips = {};                          % (opcional) IP por puerto / IP per port
    server_llm.endpoint = '/v1/chat/completions'; % Endpoint OpenAI-compatible
    server_llm.api_key = 'lm-studio';             % LM Studio no la valida / not validated
    server_llm.timeout = 0.5;                     % s (500 ms) por ciclo / per cycle
    server_llm.cycle_budget = [];                 % [] = igual a timeout / same as timeout
    server_llm.max_tokens = 200;                  % tokens de salida / output tokens
    server_llm.temperature = 0.0;                 % determinista / deterministic
    server_llm.top_p = 1.0;                       % greedy
    server_llm.stop = {['}', newline], ['}', char(13), newline], [newline, newline]};
    server_llm.use_json_schema = false;           % response_format json_schema (opcional)

    % Array de puertos (N=1 actualmente; [1234 1235 1236 1237] para N=4)
    % Port array (N=1 now; [1234 1235 1236 1237] for N=4)
    server_llm.ports = 1234;

    % Modelo por puerto (uno solo = compartido) / model per port (one = shared)
    server_llm.models = {'qwen2.5-vl-7b-instruct'};

    % Modo / mode: 'sequential' | 'round-robin' | 'parallel' (experimental)
    server_llm.mode = 'sequential';

    % Transporte / transport: 'http' (real) | 'mock' (pruebas sin red / offline tests)
    server_llm.transport = 'http';

    for k = 1:2:numel(varargin) - 1
        name = char(varargin{k});
        value = varargin{k + 1};
        if strcmpi(name, 'save_path')
            save_path = value;
        elseif isfield(server_llm, name)
            server_llm.(name) = value;
        else
            error('create_server_llm_config:field', ...
                'Campo desconocido / Unknown field: %s', name);
        end
    end

    validate_config(server_llm);

    folder = fileparts(save_path);
    if ~isfolder(folder)
        mkdir(folder);
    end
    save(save_path, 'server_llm');
    fprintf('[%s] server-llm.mat -> %s | ip=%s | ports=[%s] | mode=%s\n', ...
        char(datetime('now', 'Format', 'HH:mm:ss')), save_path, server_llm.ip, ...
        num2str(server_llm.ports), server_llm.mode);
end

% -------------------------------------------------------------------------------------------
function validate_config(cfg)
    % VALIDATE_CONFIG Comprueba coherencia antes de guardar. / Consistency checks.
    if ~isnumeric(cfg.ports) || isempty(cfg.ports) || any(cfg.ports <= 0) || ...
            any(cfg.ports ~= round(cfg.ports))
        error('create_server_llm_config:ports', 'ports debe ser un vector de enteros > 0');
    end
    models = cellstr(cfg.models);
    if numel(models) ~= 1 && numel(models) ~= numel(cfg.ports)
        error('create_server_llm_config:models', ...
            'models debe tener 1 elemento o uno por puerto / 1 element or one per port');
    end
    if ~any(strcmpi(cfg.mode, {'sequential', 'round-robin', 'parallel'}))
        error('create_server_llm_config:mode', 'Modo no válido / Invalid mode: %s', cfg.mode);
    end
    if ~any(strcmpi(cfg.transport, {'http', 'mock'}))
        error('create_server_llm_config:transport', 'Transporte no válido: %s', cfg.transport);
    end
    if ~isempty(cfg.ips) && numel(cfg.ips) ~= numel(cfg.ports)
        error('create_server_llm_config:ips', 'ips debe tener un elemento por puerto');
    end
    if cfg.timeout <= 0
        error('create_server_llm_config:timeout', 'timeout debe ser > 0');
    end
end
