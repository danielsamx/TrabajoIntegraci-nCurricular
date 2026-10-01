function [cmd, ok, reason] = parse_llm_response(text, cfg)
% PARSE_LLM_RESPONSE Extrae {"command":"C","confidence":0.90} del texto del LLM y lo valida.
%   cmd    : struct con command, confidence y source
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

allowed = [{cfg.rest_command}, {cfg.gestures.command}];     % comandos válidos: R, C, O
cmd.command = upper(strtrim(char(data.command)));           % comando en mayúsculas
cmd.command = strrep(cmd.command, '#', '');                 % por si el modelo añade '#'
cmd.confidence = double(data.confidence);                   % confianza
cmd.source = 'llm';                                         % decidido por el LLM

if ~any(strcmp(cmd.command, allowed))                       % comando fuera de la lista
    reason = sprintf('comando "%s" no permitido (solo %s)', cmd.command, strjoin(allowed, ', '));
elseif ~isscalar(cmd.confidence) || ~(cmd.confidence >= 0 && cmd.confidence <= 1)
    reason = 'confidence fuera de [0,1]';
else
    ok = true;                                              % comando válido
    reason = '';
end
end
