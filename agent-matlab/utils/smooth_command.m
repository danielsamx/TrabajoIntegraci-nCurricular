function [out, state] = smooth_command(cmd, state, opts)
% SMOOTH_COMMAND Evita parpadeos: un comando nuevo solo se acepta si se repite
%   (mayoría en los últimos opts.window ciclos) o si llega con confianza alta.
%   El valor del comando actual se suaviza con una media móvil exponencial.
%   state guarda la memoria entre ciclos (empezar con state = []).

if isempty(state)                                           % primer ciclo
    state.history = {};                                     % comandos recientes
    state.current = cmd;                                    % comando vigente
end

state.history{end + 1} = cmd.command;                       % recuerda el comando recibido
state.history = state.history(max(1, end - opts.window + 1):end); % solo los últimos 'window'

if strcmp(cmd.command, state.current.command)               % mismo comando que el vigente
    if ~strcmp(cmd.action, 'hold')                          % con valor nuevo
        cmd.value = round(opts.alpha * cmd.value + (1 - opts.alpha) * state.current.value); % suaviza
    end
    state.current = cmd;                                    % actualiza el vigente
    out = cmd;                                              % se envía
    out.smoothing = 'suavizado';
    return;
end

votes = sum(strcmp(state.history, cmd.command));            % veces que apareció recientemente
has_majority = votes >= ceil(opts.window / 2);              % se repite lo suficiente
is_confident = cmd.confidence >= opts.fast_confidence;      % el clasificador está muy seguro
is_rest = strcmp(cmd.command, '#R') && cmd.confidence >= opts.rest_confidence; % reposo: acción segura

if has_majority || is_confident || is_rest                  % se acepta el cambio
    state.current = cmd;                                    % nuevo comando vigente
    out = cmd;
    out.smoothing = 'cambio';
else                                                        % se ignora por ahora
    out = state.current;                                    % se mantiene el vigente
    out.action = 'hold';                                    % sin mover la prótesis
    out.smoothing = sprintf('mantenido (%s visto %d/%d)', cmd.command, votes, opts.window);
end
end
