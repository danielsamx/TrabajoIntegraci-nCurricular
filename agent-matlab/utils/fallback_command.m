function cmd = fallback_command(f, prev, cfg) %#ok<INUSD>
% FALLBACK_COMMAND Decide el comando sin el LLM (si no responde o responde mal).
%   Mismo procedimiento que el system prompt, sin umbrales:
%   1. el gesto con la forma más parecida (mayor SIM);
%   2. si la ventana está más cerca del reposo que de ese gesto (DIST), reposo.

[~, g] = max(f.similarity);                                 % gesto con la forma más parecida
if f.rest_distance < f.distance(g)                          % más cerca del reposo que del gesto
    cmd.command = cfg.rest_command;                         % reposo
    margin = f.distance(g) - f.rest_distance;               % cuánto más cerca del reposo
else
    cmd.command = cfg.gestures(g).command;                  % el gesto
    margin = f.rest_distance - f.distance(g);               % cuánto más cerca del gesto
end
cmd.confidence = min(0.95, 0.5 + margin);                   % más separación = más confianza
cmd.source = 'respaldo';                                    % decidido sin el LLM
end
