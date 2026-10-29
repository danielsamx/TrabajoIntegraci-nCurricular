function text = posture_string(closure, cfg)
% POSTURE_STRING Posición de los 6 dedos para un cierre de 0 (abierta) a 1 (cerrada).
%   posture_string(0.5, cfg) -> 'A180B180C220D180E60F50' (rangos de cfg.fingers)

fg = cfg.fingers;                                           % atajo a la configuración de los dedos
closure = min(max(closure, 0), 1);                          % cierre en [0, 1]
if ~fg.open_at_zero
    closure = 1 - closure;                                  % el firmware usa 0 = flexionado
end
pos = round(closure * fg.max / fg.step) * fg.step;          % posición de cada dedo, redondeada al paso
pos = min(pos, fg.max);                                     % nunca por encima del máximo
parts = arrayfun(@(k) sprintf('%c%d', fg.letters(k), pos(k)), 1:numel(fg.max), 'UniformOutput', false);
text = strjoin(parts, fg.separator);                        % une los dedos con el separador
end
