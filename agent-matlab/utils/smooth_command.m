function [out, state] = smooth_command(cmd, state, cfg)
% SMOOTH_COMMAND Evita parpadeos: un comando nuevo solo se acepta si se repite
%   (mayoría en los últimos cfg.smoothing.window ciclos) o si llega con confianza alta.
%   state guarda la memoria entre ciclos (empezar con state = []).

if isempty(state)                                           % primer ciclo
    state.history = {};                                     % comandos recientes
    state.current = cmd;                                    % comando vigente
end

state.history{end + 1} = cmd.command;                       % recuerda el comando recibido
opts = cfg.smoothing;                                       % atajo a la configuración del suavizado
state.history = state.history(max(1, end - opts.window + 1):end); % solo los últimos 'window'

votes = sum(strcmp(state.history, cmd.command));            % veces que apareció recientemente
same = strcmp(cmd.command, state.current.command);          % es el comando vigente
has_majority = votes >= ceil(opts.window / 2);              % se repite lo suficiente
is_confident = cmd.confidence >= opts.fast_confidence;      % el clasificador está muy seguro
is_rest = strcmp(cmd.command, cfg.rest_command) && cmd.confidence >= opts.rest_confidence; % reposo: acción segura

if same || has_majority || is_confident || is_rest          % se acepta
    state.current = cmd;                                    % nuevo comando vigente
    out = cmd;
    out.smoothing = 'aceptado';
else                                                        % se ignora por ahora
    out = state.current;                                    % se mantiene el vigente
    out.smoothing = sprintf('mantenido %s (%s visto %d/%d)', out.command, cmd.command, ...
        votes, opts.window);
end
end
