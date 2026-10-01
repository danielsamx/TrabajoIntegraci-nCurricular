function log_msg(tag, fmt, varargin)
% LOG_MSG Imprime en consola una línea con hora y etiqueta: [hh:mm:ss.fff] [TAG] mensaje.

stamp = datestr(now, 'HH:MM:SS.FFF');                       % hora actual con milisegundos
message = sprintf(fmt, varargin{:});                        % aplica el formato tipo sprintf
fprintf('[%s] [%-6s] %s\n', stamp, tag, message);           % imprime la línea completa
end
