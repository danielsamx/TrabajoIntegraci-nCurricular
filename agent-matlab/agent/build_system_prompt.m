function text = build_system_prompt(template, cfg)
% BUILD_SYSTEM_PROMPT Completa la plantilla del prompt con los datos de la configuración.
%   {{REPOSO}} -> comando de reposo (cfg.rest_command)
%   {{GESTOS}} -> una línea por gesto: comando, nombre, canales clave y perfil RMS
%   {{IMAGENES}} -> descripción de las imágenes marcadas en cfg.image.send, en orden

lines = '';                                                 % texto de los gestos
for g = 1:numel(cfg.gestures)
    gesture = cfg.gestures(g);                              % gesto actual
    profile = sprintf('%.2f,', gesture.profile);            % perfil con 2 decimales
    lines = [lines, sprintf('- %s = %s. Canales clave: %s. Perfil RMS medio CH1..CH8: [%s]\n', ...
        gesture.command, gesture.name, gesture.hint, profile(1:end - 1))]; %#ok<AGROW>
end

text = strrep(template, '{{GESTOS}}', strtrim(lines));     % inserta los gestos
text = strrep(text, '{{REPOSO}}', cfg.rest_command);        % inserta el comando de reposo

[kinds, ~, descriptions] = image_kinds();                   % las 4 imágenes posibles
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
