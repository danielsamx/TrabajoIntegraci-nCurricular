function [out, state] = smooth_command(cmd, state, cfg)
% SMOOTH_COMMAND Evita parpadeos: un tipo de comando nuevo solo se acepta si se repite
%   (mayoría en los últimos cfg.smoothing.window ciclos) o si llega con confianza alta.
%   Tipos: S, C, O o POS (cualquier posición de los dedos). Dentro de POS los valores se actualizan
%   cada ciclo (control proporcional). state guarda la memoria entre ciclos (empezar con state = []).

kind = command_kind(cmd.command, cfg);                      % S, C, O o POS
if isempty(state)                                           % primer ciclo
    state.history = {};                                     % tipos recientes
    state.current = cmd;                                    % comando vigente
end

state.history{end + 1} = kind;                              % recuerda el tipo recibido
opts = cfg.smoothing;                                       % atajo a la configuración del suavizado
state.history = state.history(max(1, end - opts.window + 1):end); % solo los últimos 'window'

votes = sum(strcmp(state.history, kind));                   % veces que apareció recientemente
same = strcmp(kind, command_kind(state.current.command, cfg)); % mismo tipo que el vigente
has_majority = votes >= ceil(opts.window / 2);              % se repite lo suficiente
is_confident = cmd.confidence >= opts.fast_confidence;      % el modelo está muy seguro
is_rest = strcmp(kind, cfg.rest_command) && cmd.confidence >= opts.rest_confidence; % reposo: acción segura

if same || has_majority || is_confident || is_rest          % se acepta
    state.current = cmd;                                    % nuevo comando vigente
    out = cmd;
    out.smoothing = 'aceptado';
else                                                        % se ignora por ahora
    out = state.current;                                    % se mantiene el vigente
    out.smoothing = sprintf('mantenido %s (%s visto %d/%d)', out.command, kind, votes, opts.window);
end
end

function kind = command_kind(command, cfg)
% Tipo de comando: la propia letra (S, C, O) o 'POS' si es una posición de los dedos.
if any(strcmp(command, [{cfg.rest_command}, {cfg.gestures.command}]))
    kind = command;
else
    kind = 'POS';
end
end
