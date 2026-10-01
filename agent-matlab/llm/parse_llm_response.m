function [cmd, ok, reason] = parse_llm_response(text)
% PARSE_LLM_RESPONSE Extrae el JSON del texto del LLM y comprueba que es un comando válido.
%   cmd    : struct con command, finger, action, confidence, trigger_channels, value, source
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
if ~isempty(last)
    json = json(1:last);                                    % descarta lo que venga después
end
json = [json, repmat(']', 1, sum(json == '[') - sum(json == ']'))]; % cierra corchetes cortados
json = [json, repmat('}', 1, sum(json == '{') - sum(json == '}'))]; % cierra la llave que corta el stop

try
    data = jsondecode(json);                                % texto -> struct
catch err
    reason = ['JSON no válido: ' err.message];
    return;
end

fields = {'command', 'finger', 'action', 'confidence', 'trigger_channels', 'value'};
if ~isstruct(data) || ~all(isfield(data, fields))           % faltan campos obligatorios
    reason = 'faltan campos en el JSON';
    return;
end

cmd.command = upper(strtrim(char(data.command)));           % código del comando
cmd.finger = upper(strtrim(char(data.finger)));             % dedo
cmd.action = lower(strtrim(char(data.action)));             % acción
cmd.confidence = double(data.confidence);                   % confianza
cmd.trigger_channels = double(data.trigger_channels(:)');   % canales como vector fila
cmd.value = double(data.value);                             % ángulo o fuerza
cmd.source = 'llm';                                         % decidido por el LLM

[ok, reason] = validate_command(cmd);                       % comprueba coherencia y rangos
end
