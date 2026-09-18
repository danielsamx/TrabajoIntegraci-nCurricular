function out = llm_logger(action, varargin)
    % LLM_LOGGER Registro de cada invocación al LLM (JSON Lines) y estadísticas.
    %
    % LLM_LOGGER Logs every LLM call (JSON Lines) and keeps statistics.
    %
    % Uso / Usage:
    %   path  = llm_logger('init', 'logs');        % abre logs/llm_YYYYMMDD_HHMMSS.jsonl
    %   llm_logger('log', entry);                  % entry = struct (ver main.m / see main.m)
    %   stats = llm_logger('summary');             % imprime y devuelve estadísticas
    %   llm_logger('close');
    %
    % Campos de entry usados en estadísticas / entry fields used by statistics:
    %   port, llm_ok, llm_valid, llm_latency_ms, source ('llm'|'lda'), smoothing
    %
    % DECISIÓN: formato JSON Lines (una línea por ciclo) | RAZÓN: se añade sin reescribir el
    %   archivo, sobrevive a cortes y se analiza con jsondecode línea a línea |
    %   ALTERNATIVA DESCARTADA: .mat por sesión (se pierde todo si MATLAB se cierra)
    % DECISION: JSON Lines format (one line per cycle) | REASON: append-only, survives
    %   crashes and can be parsed line by line with jsondecode |
    %   DISCARDED ALTERNATIVE: per-session .mat (everything is lost if MATLAB closes)
    %
    % DECISIÓN: el contenido crudo del LLM se trunca a 2000 caracteres | RAZÓN: limita el
    %   tamaño del log en sesiones largas | ALTERNATIVA DESCARTADA: guardar la respuesta
    %   HTTP completa
    % DECISION: raw LLM content is truncated to 2000 characters | REASON: bounds log size
    %   in long sessions | DISCARDED ALTERNATIVE: storing the full HTTP response
    %
    % Entradas / Inputs:
    %   action   : 'init' | 'log' | 'summary' | 'close'
    %   varargin : carpeta (init) o struct de entrada (log) / folder (init) or entry (log)
    %
    % Salidas / Outputs:
    %   out : ruta del archivo (init/close), true (log) o estadísticas (summary)
    %         file path (init/close), true (log) or statistics (summary)

    persistent file_id file_path stats

    out = [];
    if isempty(file_id)
        file_id = -1;
    end
    if isempty(stats)
        stats = new_stats();
    end

    switch lower(action)
        case 'init'
            folder = 'logs';
            if ~isempty(varargin)
                folder = char(varargin{1});
            end
            if ~isfolder(folder)
                mkdir(folder);
            end
            if file_id > 2
                fclose(file_id);
            end
            stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            file_path = fullfile(folder, ['llm_', stamp, '.jsonl']);
            file_id = fopen(file_path, 'a', 'n', 'UTF-8');
            if file_id < 0
                logger('WARN', 'llm_logger', 'No se pudo abrir / Cannot open: %s', file_path);
            end
            stats = new_stats();
            out = file_path;

        case 'log'
            entry = varargin{1};
            stats = update_stats(stats, entry);
            if isfield(entry, 'llm_content') && ischar(entry.llm_content) && ...
                    numel(entry.llm_content) > 2000
                entry.llm_content = entry.llm_content(1:2000);
            end
            if file_id > 2
                try
                    fprintf(file_id, '%s\n', jsonencode(entry));
                catch err
                    logger('WARN', 'llm_logger', ['Entrada no serializable / ', ...
                        'Non-serializable entry: %s'], err.message);
                end
            end
            out = true;

        case 'summary'
            out = stats;
            print_summary(stats);

        case 'close'
            if file_id > 2
                fclose(file_id);
            end
            file_id = -1;
            out = file_path;

        otherwise
            error('llm_logger:action', 'Acción desconocida / Unknown action: %s', action);
    end
end

% -------------------------------------------------------------------------------------------
function stats = new_stats()
    % NEW_STATS Estadísticas vacías. / Empty statistics.
    stats = struct('calls', 0, 'http_ok', 0, 'valid', 0, 'fallback_lda', 0, ...
        'hold', 0, 'latency_sum_ms', 0, 'latency_max_ms', 0, ...
        'ports', [], 'port_calls', [], 'port_ok', []);
end

% -------------------------------------------------------------------------------------------
function stats = update_stats(stats, entry)
    % UPDATE_STATS Acumula una invocación. / Accumulates one call.
    stats.calls = stats.calls + 1;
    llm_ok = get_field(entry, 'llm_ok', false);
    stats.http_ok = stats.http_ok + double(llm_ok);
    stats.valid = stats.valid + double(get_field(entry, 'llm_valid', false));
    source = get_field(entry, 'source', '');
    stats.fallback_lda = stats.fallback_lda + double(strcmp(source, 'lda'));
    stats.hold = stats.hold + double(strcmp(get_field(entry, 'smoothing', ''), 'held'));
    latency = get_field(entry, 'llm_latency_ms', 0);
    if isfinite(latency)
        stats.latency_sum_ms = stats.latency_sum_ms + latency;
        stats.latency_max_ms = max(stats.latency_max_ms, latency);
    end
    port = get_field(entry, 'port', NaN);
    if ~isempty(port) && isfinite(port)
        idx = find(stats.ports == port, 1);
        if isempty(idx)
            stats.ports(end + 1) = port;
            stats.port_calls(end + 1) = 0;
            stats.port_ok(end + 1) = 0;
            idx = numel(stats.ports);
        end
        stats.port_calls(idx) = stats.port_calls(idx) + 1;
        stats.port_ok(idx) = stats.port_ok(idx) + double(llm_ok);
    end
end

% -------------------------------------------------------------------------------------------
function print_summary(stats)
    % PRINT_SUMMARY Imprime el resumen en consola. / Prints the summary to the console.
    n = max(stats.calls, 1);
    fprintf('\n===== LLM summary / Resumen LLM =====\n');
    fprintf('Invocaciones / Calls        : %d\n', stats.calls);
    fprintf('HTTP OK                     : %d (%.1f%%)\n', stats.http_ok, ...
        100 * stats.http_ok / n);
    fprintf('JSON válido / valid         : %d (%.1f%%)\n', stats.valid, ...
        100 * stats.valid / n);
    fprintf('Fallback LDA                : %d (%.1f%%)\n', stats.fallback_lda, ...
        100 * stats.fallback_lda / n);
    fprintf('Mantenidos / held (smooth)  : %d\n', stats.hold);
    fprintf('Latencia media / mean (ms)  : %.1f\n', stats.latency_sum_ms / n);
    fprintf('Latencia máx / max (ms)     : %.1f\n', stats.latency_max_ms);
    for k = 1:numel(stats.ports)
        fprintf('  Puerto / Port %5d : %d llamadas / calls, %d OK\n', ...
            stats.ports(k), stats.port_calls(k), stats.port_ok(k));
    end
    fprintf('=====================================\n');
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
