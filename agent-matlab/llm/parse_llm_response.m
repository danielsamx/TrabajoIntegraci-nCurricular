function [cmd, ok, reason] = parse_llm_response(text, cfg)
% PARSE_LLM_RESPONSE Extrae {"command":..,"confidence":..,"reason":..} del texto del LLM y lo valida.
%   command válido: S, C, O o la posición de los 6 dedos ('A100B200C300D200E60F50')
%   cmd    : struct con command, confidence, reason y source
%   ok     : true si el comando se puede enviar a la prótesis
%   reason : motivo del rechazo ('' si ok)

cmd = [];                                                   % sin comando hasta validarlo
ok = false;                                                 % se asume inválido

text = regexprep(char(text), '<think>.*?</think>', '');     % quita el razonamiento visible
text = regexprep(text, '```(json)?', '');                   % quita las marcas de código markdown
first = find(text == '{', 1);                               % inicio del objeto JSON
if isempty(first)                                           % no hay JSON
    reason = 'la respuesta no contiene JSON';
    return;
end
json = strtrim(text(first:end));                            % desde la primera llave
last = find(json == '}', 1, 'last');                        % última llave de cierre
if isempty(last)
    json = [json '}'];                                      % cierra la llave que corta el stop
else
    json = json(1:last);                                    % descarta lo que venga después
end

try
    data = jsondecode(json);                                % texto -> struct
catch err
    reason = ['JSON no válido: ' err.message];
    return;
end
if ~isstruct(data) || ~isfield(data, 'command') || ~isfield(data, 'confidence')
    reason = 'faltan los campos command o confidence';
    return;
end

primitives = [{cfg.rest_command}, {cfg.gestures.command}]; % comandos de una letra: S, C, O
cmd.command = upper(strtrim(char(data.command)));           % comando en mayúsculas
cmd.command = strrep(cmd.command, '#', '');                 % por si el modelo añade '#'
cmd.confidence = double(data.confidence);                   % confianza
cmd.reason = '';                                            % motivo que da el modelo (opcional)
if isfield(data, 'reason')
    cmd.reason = char(data.reason);
end
cmd.source = 'llm';                                         % decidido por el LLM

if ~any(strcmp(cmd.command, primitives))                    % no es S, C ni O: ¿posición de los dedos?
    [pos, is_posture] = posture_values(cmd.command, cfg);
    if is_posture
        parts = cell(1, numel(pos));                        % 'A100', 'B200', ...
        for k = 1:numel(pos)
            parts{k} = sprintf('%c%d', cfg.fingers.letters(k), pos(k));
        end
        cmd.command = strjoin(parts, cfg.fingers.separator); % formato limpio y dentro del rango
    end
else
    is_posture = false;
end

if ~any(strcmp(cmd.command, primitives)) && ~is_posture     % ni comando ni posición válida
    reason = sprintf('comando "%s" no permitido (solo %s o %s con números)', cmd.command, ...
        strjoin(primitives, ', '), sprintf('%c..', cfg.fingers.letters));
elseif ~isscalar(cmd.confidence) || ~(cmd.confidence >= 0 && cmd.confidence <= 1)
    reason = 'confidence fuera de [0,1]';
else
    ok = true;                                              % comando válido
    reason = '';
end
end
