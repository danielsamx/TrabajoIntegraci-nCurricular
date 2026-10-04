function text = build_system_prompt(template, cfg)
% BUILD_SYSTEM_PROMPT Completa la plantilla del prompt con los datos de la configuración.
%   {{REPOSO}} -> comando de reposo (cfg.rest_command)
%   {{GESTOS}} -> una línea por gesto: comando, nombre, canales clave y perfil RMS

lines = '';                                                 % texto de los gestos
for g = 1:numel(cfg.gestures)
    gesture = cfg.gestures(g);                              % gesto actual
    profile = sprintf('%.2f,', gesture.profile);            % perfil con 2 decimales
    lines = [lines, sprintf('- %s = %s. Canales clave: %s. Perfil RMS medio CH1..CH8: [%s]\n', ...
        gesture.command, gesture.name, gesture.hint, profile(1:end - 1))]; %#ok<AGROW>
end

text = strrep(template, '{{GESTOS}}', strtrim(lines));     % inserta los gestos
text = strrep(text, '{{REPOSO}}', cfg.rest_command);        % inserta el comando de reposo
end
