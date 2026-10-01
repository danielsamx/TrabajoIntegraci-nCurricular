function cmd = fallback_command(f, prev, cfg)
% FALLBACK_COMMAND Decide el comando sin el LLM (si no responde o responde mal).
%   Mismo procedimiento que el system prompt: ruido -> PREV, sin actividad -> R,
%   con actividad -> el gesto cuyo perfil se parece más (mayor similitud).

if strcmp(f.state, 'NOISE')                                 % señal mala
    cmd.command = prev.command;                             % se mantiene el anterior
    cmd.confidence = 0.50;
elseif max(f.rms) < cfg.signal.rest_threshold               % sin actividad
    cmd.command = cfg.rest_command;                         % reposo
    cmd.confidence = 0.90;
else
    [best, g] = max(f.similarity);                          % gesto más parecido
    second = max([f.similarity(1:g - 1), f.similarity(g + 1:end), 0]); % el siguiente más parecido
    cmd.command = cfg.gestures(g).command;                  % su comando
    cmd.confidence = 0.70 + 0.20 * (best - second >= 0.15); % 0.90 si la diferencia es clara
end
cmd.source = 'respaldo';                                    % decidido sin el LLM
end
