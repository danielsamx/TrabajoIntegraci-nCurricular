function logger(level, module, fmt, varargin)
    % LOGGER Logger general con marca de tiempo, niveles y archivo opcional.
    %
    % LOGGER General-purpose logger with timestamp, levels and optional file.
    %
    % Uso / Usage:
    %   logger('INFO', 'main', 'Ciclo %d / Cycle %d', k, k);
    %   logger('config', 'level', 'DEBUG', 'file', 'logs/run.log');
    %   logger('close');
    %
    % Niveles / Levels: DEBUG < INFO < WARN < ERROR
    %
    % DECISIÓN: función con estado persistente en vez de clase | RAZÓN: se llama desde
    %   cualquier módulo sin pasar un objeto, y es compatible con scripts | ALTERNATIVA
    %   DESCARTADA: variable global (colisiones de nombres, difícil de depurar)
    % DECISION: function with persistent state instead of a class | REASON: callable from
    %   any module without passing an object, and script-friendly | DISCARDED
    %   ALTERNATIVE: global variable (name clashes, hard to debug)
    %
    % DECISIÓN: ERROR va a stderr (fid 2) | RAZÓN: se distingue en la consola de MATLAB
    %   (texto rojo) | ALTERNATIVA DESCARTADA: todo a stdout
    % DECISION: ERROR goes to stderr (fid 2) | REASON: stands out in the MATLAB console
    %   (red text) | DISCARDED ALTERNATIVE: everything to stdout
    %
    % Entradas / Inputs:
    %   level    : 'DEBUG'|'INFO'|'WARN'|'ERROR'|'config'|'close'
    %   module   : nombre del módulo emisor / emitting module name
    %   fmt      : formato estilo sprintf / sprintf-style format
    %   varargin : argumentos del formato / format arguments

    persistent min_level file_id

    level_names = {'DEBUG', 'INFO', 'WARN', 'ERROR'};
    if isempty(min_level)
        min_level = 2;   % INFO
    end
    if isempty(file_id)
        file_id = -1;
    end

    if strcmpi(level, 'close')
        if file_id > 2
            fclose(file_id);
        end
        file_id = -1;
        return;
    end

    if strcmpi(level, 'config')
        args = [{module, fmt}, varargin];
        for k = 1:2:numel(args) - 1
            name = lower(char(args{k}));
            value = args{k + 1};
            switch name
                case 'level'
                    idx = find(strcmpi(level_names, value), 1);
                    if ~isempty(idx)
                        min_level = idx;
                    end
                case 'file'
                    if file_id > 2
                        fclose(file_id);
                    end
                    file_id = -1;
                    if ~isempty(value)
                        folder = fileparts(char(value));
                        if ~isempty(folder) && ~isfolder(folder)
                            mkdir(folder);
                        end
                        file_id = fopen(char(value), 'a', 'n', 'UTF-8');
                    end
            end
        end
        return;
    end

    idx = find(strcmpi(level_names, level), 1);
    if isempty(idx)
        idx = 2;
    end
    if idx < min_level
        return;
    end

    if nargin < 3
        fmt = '';
    end
    try
        message = sprintf(fmt, varargin{:});
    catch
        message = fmt;
    end

    timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
    line = sprintf('[%s] [%-5s] [%s] %s\n', timestamp, level_names{idx}, ...
        char(module), message);

    if idx >= 4
        fprintf(2, '%s', line);
    else
        fprintf(1, '%s', line);
    end

    if file_id > 2
        fprintf(file_id, '%s', line);
    end
end
