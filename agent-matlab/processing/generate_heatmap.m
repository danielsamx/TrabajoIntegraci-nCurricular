function img_path = generate_heatmap(rms_values, state, timestamp, opts)
    % GENERATE_HEATMAP Genera la imagen de barras de 8 canales que recibe el VLM.
    %
    % GENERATE_HEATMAP Generates the 8-channel bar image sent to the VLM.
    %
    % Especificaciones / Specifications:
    %   - 640x480 px (configurable)
    %   - Escala Y / Y scale: 0.0 - 1.0
    %   - Colores / colors: turbo
    %   - Umbrales / thresholds: 0.15 (rest, discontinua / dashed), 0.40 (active, roja / red)
    %   - Título / title: timestamp y estado / timestamp and state
    %   - Valor numérico sobre cada barra / numeric value above each bar
    %
    % DECISIÓN: gráfico de barras con escala turbo | RAZÓN: máxima legibilidad para el VLM
    %   (altura + color codifican la misma magnitud) | ALTERNATIVA DESCARTADA: espectrograma
    %   (más complejo, no aporta información para clasificar dedos)
    % DECISION: bar chart with turbo scale | REASON: maximum readability for the VLM
    %   (height + color encode the same magnitude) | DISCARDED ALTERNATIVE: spectrogram
    %   (more complex, adds nothing for finger classification)
    %
    % DECISIÓN: figura invisible persistente que solo se actualiza | RAZÓN: crear una
    %   figura por ciclo cuesta >150 ms; actualizar YData/CData cuesta pocos ms |
    %   ALTERNATIVA DESCARTADA: figure()+exportgraphics() en cada ciclo
    % DECISION: persistent invisible figure that is only updated | REASON: creating a
    %   figure per cycle costs >150 ms; updating YData/CData costs a few ms |
    %   DISCARDED ALTERNATIVE: figure()+exportgraphics() every cycle
    %
    % DECISIÓN: modo 'raster' opcional (dibujo directo en píxeles, sin texto) | RAZÓN: es
    %   10-20x más rápido cuando la latencia importa; el texto ya viaja en el payload |
    %   ALTERNATIVA DESCARTADA: insertText (Computer Vision Toolbox, no permitido)
    % DECISION: optional 'raster' mode (direct pixel drawing, no text) | REASON: 10-20x
    %   faster when latency matters; the text already travels in the payload |
    %   DISCARDED ALTERNATIVE: insertText (Computer Vision Toolbox, not allowed)
    %
    % DECISIÓN: reescalado por vecino más cercano hecho a mano | RAZÓN: con escalado de
    %   pantalla (HiDPI) print() puede devolver otro tamaño; imresize es de Image
    %   Processing Toolbox (no permitido) | ALTERNATIVA DESCARTADA: imresize
    % DECISION: hand-made nearest-neighbour resize | REASON: with display scaling (HiDPI)
    %   print() may return another size; imresize belongs to Image Processing Toolbox
    %   (not allowed) | DISCARDED ALTERNATIVE: imresize
    %
    % Entradas / Inputs:
    %   rms_values : RMS 1x8 normalizado / normalized 1x8 RMS  (o 'reset' / or 'reset')
    %   state      : texto del estado / state text
    %   timestamp  : datetime, número (ms) o texto / datetime, number (ms) or text
    %   opts       : (opcional / optional) width, height, render_mode ('figure'|'raster'),
    %                out_path, rest_threshold, active_threshold
    %
    % Salidas / Outputs:
    %   img_path : ruta del PNG generado / path of the generated PNG
    %
    % Ejemplo / Example:
    %   p = generate_heatmap([0.1 0.1 0.2 0.8 0.2 0.1 0.4 0.1], 'ACTIVE', 1234);

    persistent gfx

    if ischar(rms_values) || isstring(rms_values)
        if strcmpi(rms_values, 'reset')
            if ~isempty(gfx) && isgraphics(gfx.fig)
                close(gfx.fig);
            end
            gfx = [];
            img_path = '';
            return;
        end
        error('generate_heatmap:badInput', 'Entrada no válida / Invalid input');
    end

    if nargin < 2 || isempty(state)
        state = 'UNKNOWN';
    end
    if nargin < 3
        timestamp = [];
    end
    if nargin < 4 || isempty(opts)
        opts = struct();
    end

    width = get_opt(opts, 'width', 640);
    height = get_opt(opts, 'height', 480);
    render_mode = lower(get_opt(opts, 'render_mode', 'figure'));
    out_path = get_opt(opts, 'out_path', fullfile(tempdir, 'prosthesis_emg_bars.png'));
    rest_threshold = get_opt(opts, 'rest_threshold', 0.15);
    active_threshold = get_opt(opts, 'active_threshold', 0.40);

    r = double(rms_values(:)');
    r(~isfinite(r)) = 0;
    r = min(max(r, 0), 1);
    if numel(r) ~= 8
        error('generate_heatmap:size', '8 canales requeridos / 8 channels required');
    end

    title_text = sprintf('T=%s | STATE=%s', format_timestamp(timestamp), ...
        upper(char(state)));
    colors = turbo(256);

    switch render_mode
        case 'raster'
            img = render_raster(r, width, height, rest_threshold, active_threshold, ...
                colors, upper(char(state)));
        case 'figure'
            [img, gfx] = render_figure(gfx, r, width, height, rest_threshold, ...
                active_threshold, colors, title_text);
        otherwise
            error('generate_heatmap:mode', ...
                'Modo desconocido / Unknown mode: %s', render_mode);
    end

    img = resize_nearest(img, width, height);
    imwrite(img, out_path);
    img_path = out_path;
end

% -------------------------------------------------------------------------------------------
function [img, gfx] = render_figure(gfx, r, width, height, rest_t, active_t, colors, ...
        title_text)
    % RENDER_FIGURE Crea (una vez) y actualiza la figura invisible; devuelve RGB.
    % RENDER_FIGURE Creates (once) and updates the invisible figure; returns RGB.
    needs_new = isempty(gfx) || ~isgraphics(gfx.fig) || ...
        ~isequal(gfx.size, [width, height]);
    if needs_new
        if ~isempty(gfx) && isgraphics(gfx.fig)
            close(gfx.fig);
        end
        gfx = struct();
        gfx.size = [width, height];
        gfx.fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', ...
            'Position', [100, 100, width, height], 'InvertHardcopy', 'off', ...
            'PaperPositionMode', 'auto', 'MenuBar', 'none', 'ToolBar', 'none', ...
            'HandleVisibility', 'off', 'NumberTitle', 'off', 'Name', 'emg_bars');
        gfx.ax = axes('Parent', gfx.fig, 'Units', 'normalized', ...
            'Position', [0.10, 0.10, 0.78, 0.78]);
        gfx.bars = bar(gfx.ax, 1:8, r, 0.7, 'FaceColor', 'flat', 'EdgeColor', 'k');
        hold(gfx.ax, 'on');
        yline(gfx.ax, rest_t, '--', sprintf('REST %.2f', rest_t), ...
            'Color', [0.25, 0.25, 0.25], 'LineWidth', 2, ...
            'LabelHorizontalAlignment', 'left', 'FontSize', 10);
        yline(gfx.ax, active_t, '-', sprintf('ACTIVE %.2f', active_t), ...
            'Color', [0.85, 0, 0], 'LineWidth', 2, ...
            'LabelHorizontalAlignment', 'left', 'FontSize', 10);
        ylim(gfx.ax, [0, 1]);
        xlim(gfx.ax, [0.4, 8.6]);
        set(gfx.ax, 'XTick', 1:8, 'XTickLabel', ...
            {'CH1', 'CH2', 'CH3', 'CH4', 'CH5', 'CH6', 'CH7', 'CH8'}, ...
            'YTick', 0:0.2:1, 'FontSize', 12, 'Box', 'on');
        grid(gfx.ax, 'on');
        ylabel(gfx.ax, 'RMS (norm.)');
        colormap(gfx.ax, colors);
        clim(gfx.ax, [0, 1]);
        colorbar(gfx.ax, 'Position', [0.91, 0.10, 0.025, 0.78]);
        gfx.labels = gobjects(1, 8);
        for k = 1:8
            gfx.labels(k) = text(gfx.ax, k, 0.05, '0.00', ...
                'HorizontalAlignment', 'center', 'FontSize', 12, ...
                'FontWeight', 'bold', 'Clipping', 'off');
        end
        gfx.title = title(gfx.ax, title_text, 'FontSize', 13, 'Interpreter', 'none');
    end

    color_idx = max(1, min(256, round(r * 255) + 1));
    set(gfx.bars, 'YData', r, 'CData', colors(color_idx, :));
    for k = 1:8
        set(gfx.labels(k), 'Position', [k, min(r(k) + 0.04, 0.97), 0], ...
            'String', sprintf('%.2f', r(k)));
    end
    set(gfx.title, 'String', title_text);

    img = print(gfx.fig, '-RGBImage', '-r0');
end

% -------------------------------------------------------------------------------------------
function img = render_raster(r, width, height, rest_t, active_t, colors, state)
    % RENDER_RASTER Dibuja barras, rejilla y umbrales directamente en una matriz RGB.
    % RENDER_RASTER Draws bars, grid and thresholds directly into an RGB matrix.
    img = uint8(255 * ones(height, width, 3));
    left = round(0.08 * width);
    right = round(0.97 * width);
    top = round(0.08 * height);
    bottom = round(0.93 * height);
    plot_h = bottom - top;
    cols = left:right;

    % Rejilla cada 0.2 / grid every 0.2
    for level = 0.2:0.2:1.0
        row = round(bottom - level * plot_h);
        img(row, cols, :) = 220;
    end

    % Barras / bars
    slot = (right - left) / 8;
    bar_w = max(1, round(slot * 0.7));
    for k = 1:8
        x0 = round(left + (k - 1) * slot + (slot - bar_w) / 2) + 1;
        x1 = min(width, x0 + bar_w - 1);
        y1 = bottom - 1;
        y0 = max(top, round(bottom - r(k) * plot_h));
        if y0 <= y1
            color = colors(max(1, min(256, round(r(k) * 255) + 1)), :);
            for c = 1:3
                img(y0:y1, x0:x1, c) = uint8(255 * color(c));
            end
        end
    end

    % Ejes / axes
    img(top:bottom, left, :) = 0;
    img(bottom, cols, :) = 0;

    % Umbrales (2 px): reposo discontinuo gris, activo continuo rojo
    % Thresholds (2 px): rest dashed grey, active solid red
    rest_row = round(bottom - rest_t * plot_h);
    active_row = round(bottom - active_t * plot_h);
    dashed = cols(mod(cols, 12) < 6);
    img(rest_row:rest_row + 1, dashed, :) = 60;
    img(active_row:active_row + 1, cols, 1) = 220;
    img(active_row:active_row + 1, cols, 2) = 0;
    img(active_row:active_row + 1, cols, 3) = 0;

    % Indicador de estado (banda superior) / state indicator (top band)
    switch state
        case 'ACTIVE'
            band = [0, 170, 0];
        case 'TRANSITION'
            band = [230, 180, 0];
        case 'NOISE'
            band = [200, 0, 0];
        otherwise
            band = [150, 150, 150];
    end
    band_rows = 1:max(1, round(0.04 * height));
    for c = 1:3
        img(band_rows, :, c) = band(c);
    end
end

% -------------------------------------------------------------------------------------------
function img = resize_nearest(img, width, height)
    % RESIZE_NEAREST Reescala por vecino más cercano. / Nearest-neighbour resize.
    [h, w, ~] = size(img);
    if h == height && w == width
        return;
    end
    rows = min(h, max(1, round((1:height) * h / height)));
    cols = min(w, max(1, round((1:width) * w / width)));
    img = img(rows, cols, :);
end

% -------------------------------------------------------------------------------------------
function text = format_timestamp(timestamp)
    % FORMAT_TIMESTAMP Convierte el timestamp en texto. / Converts the timestamp to text.
    if isempty(timestamp)
        text = char(datetime('now', 'Format', 'HH:mm:ss.SSS'));
    elseif isdatetime(timestamp)
        timestamp.Format = 'HH:mm:ss.SSS';
        text = char(timestamp);
    elseif isnumeric(timestamp)
        text = sprintf('%d ms', round(timestamp));
    else
        text = char(timestamp);
    end
end

% -------------------------------------------------------------------------------------------
function value = get_opt(opts, name, default_value)
    % GET_OPT Lee un campo opcional. / Reads an optional field.
    if isfield(opts, name) && ~isempty(opts.(name))
        value = opts.(name);
    else
        value = default_value;
    end
end
