function [pos, ok] = posture_values(command, cfg)
% POSTURE_VALUES Lee 'A100B200C300D400E200F150' (con o sin comas/espacios) como 6 posiciones.
%   pos : posición de cada dedo, recortada a [0, cfg.fingers.max]
%   ok  : true si el texto tiene los 6 dedos en orden con un número cada uno

fg = cfg.fingers;                                           % atajo a la configuración de los dedos
text = regexprep(upper(char(command)), '[\s,;]', '');       % quita espacios y separadores
pattern = ['^' sprintf('%c(\\d+)', fg.letters) '$'];        % ^A(\d+)B(\d+)...F(\d+)$
tokens = regexp(text, pattern, 'tokens', 'once');           % un número por dedo
ok = ~isempty(tokens);
pos = [];
if ok
    pos = min(max(reshape(str2double(tokens), 1, []), 0), fg.max); % números recortados al rango de cada dedo
end
end
