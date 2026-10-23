function draw_emg_image(ax, kind, v, f, cfg)
% DRAW_EMG_IMAGE Dibuja una de las 3 imágenes en unos ejes (sirve para el dashboard y el LLM).
%   kind : 'features' | 'waves' | 'envelope'

navy = [0 42 92] / 255;                                     % azul del laboratorio
red = [238 46 36] / 255;                                    % rojo del laboratorio
names = arrayfun(@(k) sprintf('CH%d', k), 1:8, 'UniformOutput', false); % CH1..CH8
cla(ax);                                                    % borra el dibujo anterior
hold(ax, 'on');                                             % varios elementos en los mismos ejes

switch kind
    case 'features'                                         % matriz: una fila por canal
        m = v.features;                                     % 8 canales x 5 características
        n = size(f.filtered, 1);                            % muestras de la ventana
        shade = m;                                          % RMS y MAV ya están en [0,1]
        shade(:, 3) = m(:, 3) ./ (n * cfg.signal.max_rms(:)); % WL relativo al de una contracción máxima
        shade(:, 4:5) = m(:, 4:5) / (n - 1);                % ZC y SSC relativos al máximo posible
        shade = min(max(shade, 0), 1);                      % color en [0,1]
        imagesc(ax, shade);                                 % celdas coloreadas
        set(ax, 'CLim', [0 1]);                             % escala de color fija
        colormap(ax, (1 - linspace(0, 1, 256)') * [1 1 1] + linspace(0, 1, 256)' * navy); % blanco -> azul
        for r = 1:8                                         % cada canal
            for c = 1:numel(v.feature_names)                % cada característica
                if c <= 2
                    label = sprintf('%.2f', m(r, c));       % RMS y MAV con 2 decimales
                else
                    label = sprintf('%.0f', m(r, c));       % WL, ZC y SSC enteros
                end
                ink = navy;                                 % texto azul sobre celdas claras
                if shade(r, c) > 0.55
                    ink = [1 1 1];                          % texto blanco sobre celdas oscuras
                end
                text(ax, c, r, label, 'HorizontalAlignment', 'center', 'Color', ink, ...
                    'FontSize', 9, 'FontWeight', 'bold');
            end
        end
        set(ax, 'XTick', 1:numel(v.feature_names), 'XTickLabel', v.feature_names, 'YTick', 1:8, ...
            'YTickLabel', names, 'YDir', 'reverse', 'XAxisLocation', 'top');
        axis(ax, [0.5 numel(v.feature_names) + 0.5 0.5 8.5]);
        title(ax, 'Características por canal', 'Color', navy);

    case 'waves'                                            % ondas normalizadas apiladas
        for k = 1:8
            color = navy;                                   % canales impares en azul
            if mod(k, 2) == 0
                color = red;                                % canales pares en rojo
            end
            plot(ax, v.t, v.waves(:, k) + (9 - k) * 3, 'Color', color, 'LineWidth', 0.8); % separadas 3 unidades
        end
        set(ax, 'YTick', (1:8) * 3, 'YTickLabel', fliplr(names), 'XLim', [v.t(1) 0], 'YLim', [0 27]);
        xlabel(ax, 'tiempo (s)');
        title(ax, 'Ondas normalizadas (señal / RMS máximo)', 'Color', navy);

    case 'envelope'                                         % una sola curva para los 8 canales
        area(ax, v.t, v.envelope, 'FaceColor', navy, 'FaceAlpha', 0.15, 'EdgeColor', navy, 'LineWidth', 1.8);
        set(ax, 'XLim', [v.t(1) 0], 'YLim', [0 1]);
        xlabel(ax, 'tiempo (s)');
        title(ax, 'Envolvente general (media de los 8 canales)', 'Color', navy);
end
hold(ax, 'off');
end
