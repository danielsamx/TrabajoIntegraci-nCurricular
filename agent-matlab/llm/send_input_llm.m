function [response, port_used] = send_input_llm(cfg_llm, prompt, payload, img_path)
    % SEND_INPUT_LLM Envía una petición (TEXTO + IMAGEN) al LLM con abstracción de puertos.
    %
    % SEND_INPUT_LLM Sends a (TEXT + IMAGE) request to the LLM with port abstraction.
    %
    % Modos (cfg_llm.mode) / Modes:
    %   'sequential'  : empieza siempre por ports(1); si falla rápido, prueba el siguiente
    %                   always starts at ports(1); on a fast failure, tries the next one
    %   'round-robin' : el puerto inicial rota en cada llamada (reparte carga) + failover
    %                   the starting port rotates on each call (load sharing) + failover
    %   'parallel'    : (experimental) lanza la petición a todos los puertos con
    %                   backgroundPool y usa la primera respuesta; si no está disponible,
    %                   vuelve a 'sequential' automáticamente
    %                   (experimental) sends to all ports with backgroundPool and uses the
    %                   first answer; falls back to 'sequential' automatically
    %
    % Con N = 1 los tres modos son idénticos. Pasar de N=1 a N=4 solo requiere cambiar
    % server_llm.ports (y opcionalmente models/mode) en config/server-llm.mat.
    % With N = 1 all modes are identical. Moving from N=1 to N=4 only requires changing
    % server_llm.ports (and optionally models/mode) in config/server-llm.mat.
    %
    % DECISIÓN: array de puertos con round-robin | RAZÓN: permite N=1 y N=4 sin cambiar
    %   código | ALTERNATIVA DESCARTADA: hardcodear un puerto único
    % DECISION: port array with round-robin | REASON: supports N=1 and N=4 without code
    %   changes | DISCARDED ALTERNATIVE: hardcoding a single port
    %
    % DECISIÓN: presupuesto de tiempo por ciclo compartido entre reintentos | RAZÓN: el
    %   failover solo tiene sentido si el primer puerto falla rápido (conexión rechazada);
    %   un timeout ya consume el presupuesto y se pasa al fallback LDA | ALTERNATIVA
    %   DESCARTADA: timeout completo por puerto (N=4 podría bloquear 2 s)
    % DECISION: per-cycle time budget shared across retries | REASON: failover only makes
    %   sense when the first port fails fast (connection refused); a timeout already
    %   spends the budget and the LDA fallback takes over | DISCARDED ALTERNATIVE: full
    %   timeout per port (N=4 could block for 2 s)
    %
    % DECISIÓN: transporte 'mock' seleccionable por configuración | RAZÓN: permite probar
    %   el pipeline y el reparto de puertos sin red por el MISMO camino de código |
    %   ALTERNATIVA DESCARTADA: funciones de prueba separadas (no prueban el código real)
    % DECISION: 'mock' transport selectable by configuration | REASON: lets the pipeline
    %   and port distribution be tested without network through the SAME code path |
    %   DISCARDED ALTERNATIVE: separate test functions (they do not test the real code)
    %
    % Entradas / Inputs:
    %   cfg_llm  : struct de server-llm.mat (o 'reset' para reiniciar el round-robin)
    %              struct from server-llm.mat (or 'reset' to reset the round-robin)
    %   prompt   : struct de prompt-llm.mat o char / struct from prompt-llm.mat or char
    %   payload  : texto ASCII de build_payload / ASCII text from build_payload
    %   img_path : PNG de generate_heatmap (obligatorio) / PNG from generate_heatmap
    %
    % Salidas / Outputs:
    %   response  : struct con ok, content, raw, error, port, model, latency_ms,
    %               http_latency_ms, attempts, mode, transport
    %   port_used : puerto que respondió (NaN si ninguno) / answering port (NaN if none)
    %
    % Ejemplo / Example:
    %   [resp, port] = send_input_llm(server_llm, prompt_llm, payload, img_path);
    %   if resp.ok, [cmd, ok] = parse_llm_response(resp.content); end

    persistent rr_counter parallel_disabled

    MIN_TIMEOUT = 0.05;

    if isempty(rr_counter)
        rr_counter = 0;
    end
    if isempty(parallel_disabled)
        parallel_disabled = false;
    end

    if ischar(cfg_llm) || isstring(cfg_llm)
        if strcmpi(cfg_llm, 'reset')
            rr_counter = 0;
            parallel_disabled = false;
            response = [];
            port_used = [];
            return;
        end
        error('send_input_llm:badInput', 'Entrada no válida / Invalid input');
    end

    t_start = tic;
    response = new_response();
    port_used = NaN;

    ports = double(cfg_llm.ports(:)');
    n_ports = numel(ports);
    if n_ports == 0
        error('send_input_llm:noPorts', 'server_llm.ports está vacío / is empty');
    end
    llm_mode = lower(char(get_field(cfg_llm, 'mode', 'sequential')));
    transport = lower(char(get_field(cfg_llm, 'transport', 'http')));
    budget = get_field(cfg_llm, 'cycle_budget', cfg_llm.timeout);
    response.mode = llm_mode;
    response.transport = transport;

    % 1) Imagen obligatoria / mandatory image
    try
        img_b64 = encode_image(img_path);
    catch err
        response.error = ['image: ', err.message];
        response.latency_ms = 1000 * toc(t_start);
        logger('ERROR', 'send_input_llm', 'Imagen no disponible / Image unavailable: %s', ...
            err.message);
        return;
    end

    % 2) Orden de puertos / port order
    if strcmp(llm_mode, 'round-robin')
        start_idx = mod(rr_counter, n_ports) + 1;
        rr_counter = rr_counter + 1;
    else
        start_idx = 1;
    end
    order = [start_idx:n_ports, 1:start_idx - 1];

    % 3) Modo paralelo (experimental) / parallel mode (experimental)
    if strcmp(llm_mode, 'parallel') && n_ports > 1 && strcmp(transport, 'http') && ...
            ~parallel_disabled
        [par_response, par_port, handled, disable] = call_parallel(cfg_llm, prompt, ...
            payload, img_b64, ports, order, budget, t_start);
        if disable
            parallel_disabled = true;
            logger('WARN', 'send_input_llm', ['backgroundPool/webwrite no disponible; ', ...
                'se usa modo secuencial / unavailable; using sequential mode']);
        end
        if handled
            response = par_response;
            port_used = par_port;
            return;
        end
    end

    % 4) Secuencial con failover / sequential with failover
    last_model = '';
    body = '';
    for idx = order
        remaining = budget - toc(t_start);
        if response.attempts > 0 && remaining < MIN_TIMEOUT
            break;
        end
        timeout_k = max(remaining, MIN_TIMEOUT);
        model = model_for_port(cfg_llm, idx);
        if ~strcmp(model, last_model)
            body = build_request_body(cfg_llm, prompt, payload, img_b64, model);
            last_model = model;
        end

        response.attempts = response.attempts + 1;
        t_call = tic;
        try
            switch transport
                case 'http'
                    raw = http_post(cfg_llm, idx, ports(idx), body, timeout_k);
                case 'mock'
                    raw = mock_post(cfg_llm, ports(idx), payload);
                otherwise
                    error('send_input_llm:transport', 'Transporte desconocido: %s', ...
                        transport);
            end
            content = extract_content(raw);
            response.ok = true;
            response.raw = raw;
            response.content = content;
            response.port = ports(idx);
            response.model = model;
            response.http_latency_ms = 1000 * toc(t_call);
            response.error = '';
            port_used = ports(idx);
            break;
        catch err
            response.error = sprintf('port %d: %s', ports(idx), err.message);
            logger('WARN', 'send_input_llm', ...
                'Fallo en puerto / Port failure %d (%.0f ms): %s', ports(idx), ...
                1000 * toc(t_call), err.message);
        end
    end

    response.latency_ms = 1000 * toc(t_start);
    response.body_bytes = numel(body);
end

% ===========================================================================================
% Transporte / Transport
% ===========================================================================================
function raw = http_post(cfg, idx, port, body, timeout_s)
    % HTTP_POST POST JSON a LM Studio con webwrite. / JSON POST to LM Studio with webwrite.
    url = build_url(cfg, idx, port);
    opts = make_options(cfg, timeout_s);
    raw = webwrite(url, body, opts);
end

% -------------------------------------------------------------------------------------------
function url = build_url(cfg, idx, port)
    % BUILD_URL http://<ip>:<puerto><endpoint>. / http://<ip>:<port><endpoint>.
    url = sprintf('http://%s:%d%s', ip_for_port(cfg, idx), port, cfg.endpoint);
end

% -------------------------------------------------------------------------------------------
function opts = make_options(cfg, timeout_s)
    % MAKE_OPTIONS weboptions para JSON con Bearer token. / JSON weboptions with Bearer.
    opts = weboptions('MediaType', 'application/json', 'ContentType', 'json', ...
        'Timeout', timeout_s, 'RequestMethod', 'post', ...
        'HeaderFields', {'Authorization', ['Bearer ', char(cfg.api_key)]});
end

% -------------------------------------------------------------------------------------------
function [response, port_used, handled, disable] = call_parallel(cfg, prompt, payload, ...
        img_b64, ports, order, budget, t_start)
    % CALL_PARALLEL Lanza la petición a todos los puertos y toma la primera respuesta.
    % CALL_PARALLEL Sends the request to all ports and takes the first answer.
    %
    % DECISIÓN: backgroundPool (MATLAB base) | RAZÓN: no requiere Parallel Computing
    %   Toolbox (no permitido) | ALTERNATIVA DESCARTADA: parpool/parfor (requiere toolbox)
    % DECISION: backgroundPool (base MATLAB) | REASON: does not need Parallel Computing
    %   Toolbox (not allowed) | DISCARDED ALTERNATIVE: parpool/parfor (needs the toolbox)
    response = new_response();
    response.mode = 'parallel';
    response.transport = 'http';
    port_used = NaN;
    handled = false;
    disable = false;

    if exist('backgroundPool', 'file') == 0
        disable = true;
        return;
    end

    n = numel(order);
    try
        pool = backgroundPool;
        for j = 1:n
            idx = order(j);
            body = build_request_body(cfg, prompt, payload, img_b64, model_for_port(cfg, idx));
            futures(j) = parfeval(pool, @webwrite, 1, build_url(cfg, idx, ports(idx)), ...
                body, make_options(cfg, budget)); %#ok<AGROW>
        end
    catch err
        logger('WARN', 'send_input_llm', 'parfeval: %s', err.message);
        if exist('futures', 'var')
            cancel(futures);
        end
        disable = true;
        return;
    end

    handled = true;
    response.attempts = n;
    n_done = 0;
    while n_done < n
        remaining = budget - toc(t_start);
        if remaining <= 0
            response.error = 'parallel timeout';
            break;
        end
        try
            [j, raw] = fetchNext(futures, remaining);
        catch err
            n_done = n_done + 1;
            response.error = err.message;
            if contains(lower(err.message), {'not supported', 'thread-based'})
                disable = true;
                handled = false;
                break;
            end
            continue;
        end
        if isempty(j)
            response.error = 'parallel timeout';
            break;
        end
        n_done = n_done + 1;
        try
            response.content = extract_content(raw);
            response.raw = raw;
            response.ok = true;
            response.port = ports(order(j));
            response.model = model_for_port(cfg, order(j));
            response.error = '';
            port_used = response.port;
            break;
        catch err
            response.error = err.message;
        end
    end
    try
        cancel(futures);
    catch
        % Los futuros ya terminados no se cancelan / finished futures cannot be cancelled
    end
    response.latency_ms = 1000 * toc(t_start);
    response.http_latency_ms = response.latency_ms;
end

% -------------------------------------------------------------------------------------------
function raw = mock_post(cfg, port, payload)
    % MOCK_POST Simula LM Studio con un clasificador determinista basado en las reglas.
    % MOCK_POST Simulates LM Studio with a deterministic rule-based classifier.
    fail_ports = get_field(cfg, 'mock_fail_ports', []);
    if any(fail_ports == port)
        error('send_input_llm:mockRefused', 'Connection refused (mock, port %d)', port);
    end
    latency_s = get_field(cfg, 'mock_latency_s', 0);
    if latency_s > 0
        pause(latency_s);
    end
    message = struct('role', 'assistant', 'content', mock_classifier(payload));
    choice = struct('index', 0, 'message', message, 'finish_reason', 'stop');
    raw = struct('id', 'mock', 'object', 'chat.completion', 'model', 'mock', ...
        'choices', choice);
end

% -------------------------------------------------------------------------------------------
function content = mock_classifier(payload)
    % MOCK_CLASSIFIER Implementación determinista de las reglas del system prompt.
    % MOCK_CLASSIFIER Deterministic implementation of the system prompt rules.
    tok = regexp(payload, 'RMS:\[([^\]]*)\]', 'tokens', 'once');
    r = str2double(strsplit(tok{1}, ','));
    tok = regexp(payload, 'STATE:([A-Z_]+)', 'tokens', 'once');
    state = tok{1};
    tok = regexp(payload, 'PREV:([^|]+)', 'tokens', 'once');
    [prev_cmd, prev_value] = parse_prev(tok{1});

    flexor_to_command = {'E', 'D', 'C', 'B', 'A'};     % CH1..CH5
    [flex_peak, flex_ch] = max(r(1:5));
    [ext_peak, ext_ch] = max(r(6:8));
    ext_ch = ext_ch + 5;

    if strcmp(state, 'NOISE')
        out = hold_command(prev_cmd, prev_value, 0.50);
    elseif max(r) < 0.15
        out = make_command('#R', 'rest', 0.95, [], 0);
    else
        [is_comp, gesture, trig, conf] = is_composite_gesture(r);
        if is_comp && ~isempty(gesture)
            out = make_command(gesture, 'gesture', conf, trig, ...
                rms_to_value(r, gesture, 'gesture', [], trig));
        elseif is_comp
            out = hold_command(prev_cmd, prev_value, 0.45);
        elseif flex_peak >= 0.40
            command = flexor_to_command{flex_ch};
            info = label_to_finger(command);
            trig = unique([flex_ch, info.primary_channels], 'stable');
            trig = trig(1:2);
            out = make_command(command, 'flex', 0.90, trig, ...
                rms_to_value(r, command, 'flex', [], trig));
        elseif ext_peak >= 0.40 && flex_peak < 0.25
            candidates = {{'A'}, {'B', 'C'}, {'D', 'E'}};
            options = candidates{ext_ch - 5};
            command = options{1};
            if any(strcmp(prev_cmd, options))
                command = prev_cmd;
            end
            out = make_command(command, 'extend', 0.75, ext_ch, ...
                rms_to_value(r, command, 'extend', [], ext_ch));
        else
            out = hold_command(prev_cmd, prev_value, 0.60);
        end
    end
    content = jsonencode(out);
end

% -------------------------------------------------------------------------------------------
function out = hold_command(prev_cmd, prev_value, confidence)
    % HOLD_COMMAND Mantiene el comando previo (o reposo si no hay).
    % HOLD_COMMAND Holds the previous command (or rest if there is none).
    if isempty(prev_cmd)
        out = make_command('#R', 'rest', confidence, [], 0);
        return;
    end
    info = label_to_finger(prev_cmd);
    value = min(max(prev_value, info.range(1)), info.range(2));
    out = make_command(prev_cmd, 'hold', confidence, [], value);
end

% -------------------------------------------------------------------------------------------
function out = make_command(command, action, confidence, channels, value)
    % MAKE_COMMAND Crea el struct de salida del LLM simulado.
    % MAKE_COMMAND Creates the simulated LLM output struct.
    info = label_to_finger(command);
    out = struct('command', command, 'finger', info.finger, 'action', action, ...
        'confidence', confidence, 'trigger_channels', {num2cell(channels)}, ...
        'value', round(value));
end

% -------------------------------------------------------------------------------------------
function [command, value] = parse_prev(text)
    % PARSE_PREV 'B:095' -> ('B', 95); 'NONE' -> ('', 0).
    command = '';
    value = 0;
    parts = strsplit(strtrim(text), ':');
    if isempty(parts) || strcmpi(parts{1}, 'NONE') || isempty(label_to_finger(parts{1}))
        return;
    end
    command = upper(parts{1});
    if numel(parts) >= 2
        value = str2double(parts{2});
        if ~isfinite(value)
            value = 0;
        end
    end
end

% ===========================================================================================
% Utilidades / Helpers
% ===========================================================================================
function content = extract_content(raw)
    % EXTRACT_CONTENT Texto del asistente de la respuesta OpenAI.
    % EXTRACT_CONTENT Assistant text from the OpenAI response.
    if ischar(raw) || isstring(raw)
        content = char(raw);
        return;
    end
    if ~isstruct(raw) || ~isfield(raw, 'choices') || isempty(raw.choices)
        error('send_input_llm:format', 'Respuesta sin choices / Response without choices');
    end
    choices = raw.choices;
    if iscell(choices)
        choice = choices{1};
    else
        choice = choices(1);
    end
    value = choice.message.content;
    if ischar(value) || isstring(value)
        content = char(value);
    elseif iscell(value) || isstruct(value)
        if isstruct(value)
            value = num2cell(value);
        end
        parts = cellfun(@part_text, value, 'UniformOutput', false);
        content = strjoin(parts, '');
    else
        content = '';
    end
end

% -------------------------------------------------------------------------------------------
function text = part_text(part)
    % PART_TEXT Texto de una parte de contenido multiparte. / Text of a content part.
    if ischar(part)
        text = part;
    elseif isstruct(part) && isfield(part, 'text')
        text = char(part.text);
    else
        text = '';
    end
end

% -------------------------------------------------------------------------------------------
function b64 = encode_image(img_path)
    % ENCODE_IMAGE Lee el PNG y lo codifica en Base64. / Reads the PNG and encodes it.
    if isempty(img_path) || ~isfile(img_path)
        error('send_input_llm:noImage', 'No existe la imagen / Image not found: %s', ...
            char(img_path));
    end
    fid = fopen(img_path, 'r');
    if fid < 0
        error('send_input_llm:imageOpen', 'No se pudo abrir / Cannot open: %s', img_path);
    end
    bytes = fread(fid, Inf, '*uint8');
    fclose(fid);
    if isempty(bytes)
        error('send_input_llm:imageEmpty', 'Imagen vacía / Empty image');
    end
    b64 = base64encode(bytes);
end

% -------------------------------------------------------------------------------------------
function model = model_for_port(cfg, idx)
    % MODEL_FOR_PORT Modelo del puerto idx (uno compartido o uno por puerto).
    % MODEL_FOR_PORT Model of port idx (one shared or one per port).
    models = cellstr(cfg.models);
    if numel(models) >= idx
        model = models{idx};
    else
        model = models{1};
    end
end

% -------------------------------------------------------------------------------------------
function ip = ip_for_port(cfg, idx)
    % IP_FOR_PORT IP del puerto idx (cfg.ips opcional, si no cfg.ip).
    % IP_FOR_PORT IP of port idx (optional cfg.ips, otherwise cfg.ip).
    ip = char(cfg.ip);
    if isfield(cfg, 'ips') && numel(cfg.ips) >= idx && ~isempty(cfg.ips{idx})
        ip = char(cfg.ips{idx});
    end
end

% -------------------------------------------------------------------------------------------
function response = new_response()
    % NEW_RESPONSE Struct de respuesta vacío. / Empty response struct.
    response = struct('ok', false, 'content', '', 'raw', [], 'error', '', ...
        'port', NaN, 'model', '', 'latency_ms', NaN, 'http_latency_ms', NaN, ...
        'attempts', 0, 'mode', '', 'transport', '', 'body_bytes', 0);
end

% -------------------------------------------------------------------------------------------
function value = get_field(s, name, default_value)
    % GET_FIELD Campo opcional con valor por defecto. / Optional field with default.
    if isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = default_value;
    end
end
