function file = generate_image(f, t_ms, cfg)
% GENERATE_IMAGE Guarda un PNG con 8 barras (RMS normalizado por canal) para el LLM.
%   Líneas de umbral en 0.15 (REST) y 0.40 (ACTIVE); título con T y STATE.

persistent fig ax bars labels heading                       % la figura se crea una vez y se reutiliza

if isempty(fig) || ~isgraphics(fig)                         % primera llamada o figura cerrada
    fig = figure('Visible', 'off', 'Color', 'w', ...        % figura invisible
        'Position', [100 100 cfg.image.width cfg.image.height]);
    ax = axes(fig);                                         % ejes de la gráfica
    bars = bar(ax, 1:8, zeros(1, 8), 0.7, 'FaceColor', 'flat'); % 8 barras, color por barra
    hold(ax, 'on');                                         % para añadir más elementos
    yline(ax, cfg.signal.rest_threshold, '--k', 'REST');    % umbral de reposo
    yline(ax, cfg.signal.active_threshold, '-r', 'ACTIVE'); % umbral de actividad
    ylim(ax, [0 1]);                                        % eje Y fijo de 0 a 1
    xticks(ax, 1:8);                                        % una marca por canal
    xticklabels(ax, {'CH1' 'CH2' 'CH3' 'CH4' 'CH5' 'CH6' 'CH7' 'CH8'}); % nombres de los canales
    ylabel(ax, 'RMS normalizado');                          % título del eje Y
    grid(ax, 'on');                                         % rejilla de referencia
    labels = text(ax, 1:8, zeros(1, 8), '', ...             % un texto con el valor sobre cada barra
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    heading = title(ax, '', 'Interpreter', 'none');         % título que cambia en cada ciclo
end

colors = turbo(256);                                        % escala de color azul -> rojo
bars.CData = colors(round(f.rms * 255) + 1, :);             % color según la altura
bars.YData = f.rms;                                         % altura de cada barra
for k = 1:8                                                 % cada canal
    labels(k).Position = [k, min(f.rms(k) + 0.04, 0.97)];   % el texto justo encima de la barra
    labels(k).String = sprintf('%.2f', f.rms(k));           % valor con 2 decimales
end
heading.String = sprintf('T=%d ms | STATE=%s', round(t_ms), f.state); % tiempo y estado

file = cfg.image.file;                                      % ruta del PNG
imwrite(print(fig, '-RGBImage', '-r0'), file);              % captura la figura y la guarda como PNG
end
