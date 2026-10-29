function text = build_system_prompt(template, cfg)
% BUILD_SYSTEM_PROMPT Completa la plantilla del prompt con los datos de la configuración.
%   {{REPOSO}}   -> comando de reposo (cfg.rest_command)
%   {{GESTOS}}   -> una línea por gesto: comando, nombre, canales clave y perfil RMS
%   {{DEDOS}}    -> una línea por dedo: letra, nombre y rango de posición
%   {{FILTRO}}   -> filtros usados (banda y red eléctrica)
%   {{POS:x}}    -> posición de los dedos para un cierre x (0 a 1), p. ej. {{POS:0.5}}
%   {{IMAGENES}} -> descripción de las imágenes marcadas en cfg.image.send, en orden

lines = '';                                                 % texto de los gestos
for g = 1:numel(cfg.gestures)
    gesture = cfg.gestures(g);                              % gesto actual
    profile = sprintf('%.2f,', gesture.profile);            % perfil con 2 decimales
    lines = [lines, sprintf('   - %s = %s (cierre %d). Canales clave: %s. Perfil RMS medio CH1..CH8: [%s]\n', ...
        gesture.command, gesture.name, gesture.closure, gesture.hint, profile(1:end - 1))]; %#ok<AGROW>
end
text = strrep(template, '{{GESTOS}}', lines(1:end - 1)); % inserta los gestos (sin el último salto)
text = strrep(text, '{{REPOSO}}', cfg.rest_command);        % inserta el comando de reposo

fg = cfg.fingers;                                           % dedos de la mano
if fg.open_at_zero
    direction = '0 = extendido, máximo = flexionado';       % sentido de las posiciones
else
    direction = '0 = flexionado, máximo = extendido';
end
fingers = sprintf('Posiciones: %s.\n', direction);
for k = 1:numel(fg.max)
    fingers = [fingers, sprintf('- %c = %s, de 0 a %d\n', fg.letters(k), fg.names{k}, fg.max(k))]; %#ok<AGROW>
end
text = strrep(text, '{{DEDOS}}', strtrim(fingers));        % inserta los dedos

text = strrep(text, '{{FILTRO}}', sprintf('pasa-banda %d-%d Hz y notch de %d Hz', ...
    cfg.signal.band_hz, cfg.signal.powerline_hz));          % inserta los filtros

[tokens, marks] = regexp(text, '\{\{POS:([\d.]+)\}\}', 'tokens', 'match'); % ejemplos de posición
for k = 1:numel(marks)
    text = strrep(text, marks{k}, posture_string(str2double(tokens{k}{1}), cfg));
end

[kinds, ~, descriptions] = image_kinds();                   % las imágenes posibles
images = '';                                                % descripción de las que se envían
n = 0;
for k = 1:numel(kinds)
    if cfg.image.send.(kinds{k})                            % imagen marcada
        n = n + 1;
        images = [images, sprintf('%d. %s\n', n, descriptions{k})]; %#ok<AGROW>
    end
end
if n == 0
    images = 'Ninguna: decide solo con el texto.';          % sin imágenes
end
text = strrep(text, '{{IMAGENES}}', strtrim(images));       % inserta la lista de imágenes
end
