function summary = main_debug(varargin)
    % MAIN_DEBUG Ejecuta main.m con un panel de depuración visual en tiempo real.
    %
    % MAIN_DEBUG Runs main.m with a real-time visual debugging dashboard.
    %
    % Paneles / Panels:
    %   1. EMG filtrado de la última ventana (8 canales apilados)
    %      Filtered EMG of the last window (8 stacked channels)
    %   2. RMS normalizado con umbrales 0.15 / 0.40 (lo mismo que ve el VLM)
    %      Normalized RMS with 0.15 / 0.40 thresholds (same as the VLM sees)
    %   3. Latencia del LLM y del ciclo (últimos 100 ciclos)
    %      LLM and cycle latency (last 100 cycles)
    %   4. Origen de la decisión por ciclo: LLM (verde) / LDA (naranja)
    %      Decision source per cycle: LLM (green) / LDA (orange)
    %   5. Texto: payload, respuesta JSON y comando enviado
    %      Text: payload, JSON answer and command sent
    %   6. Imagen exacta enviada al VLM / exact image sent to the VLM
    %
    % Cerrar la ventana detiene el bucle (y main.m envía '#R' a la prótesis).
    % Closing the window stops the loop (and main.m sends '#R' to the prosthesis).
    %
    % DECISIÓN: reutilizar main.m mediante el callback OnCycle | RAZÓN: una sola
    %   implementación del pipeline; la depuración nunca diverge de producción |
    %   ALTERNATIVA DESCARTADA: copiar el bucle de main.m (dos versiones que mantener)
    % DECISION: reuse main.m through the OnCycle callback | REASON: a single pipeline
    %   implementation; debugging never diverges from production |
    %   DISCARDED ALTERNATIVE: copying main.m's loop (two versions to maintain)
    %
    % DECISIÓN: drawnow limitrate | RAZÓN: limita el refresco a ~20 Hz y no penaliza la
    %   latencia del ciclo | ALTERNATIVA DESCARTADA: drawnow completo en cada ciclo
    % DECISION: drawnow limitrate | REASON: caps refresh at ~20 Hz and does not penalize
    %   cycle latency | DISCARDED ALTERNATIVE: full drawnow every cycle
    %
    % Entradas / Inputs:
    %   varargin : mismos pares nombre-valor que main.m / same name-value pairs as main.m
    %
    % Salidas / Outputs:
    %   summary : resumen devuelto por main.m / summary returned by main.m
    %
    % Ejemplo / Example:
    %   main_debug('Source', 'simulated')
    %   main_debug('Source', 'myo', 'MyoDevice', 'Myo')

    history_len = 100;
    ui = build_dashboard(history_len);
    summary = main(varargin{:}, 'OnCycle', @(info) update_dashboard(ui, info));
end

% -------------------------------------------------------------------------------------------
function ui = build_dashboard(history_len)
    % BUILD_DASHBOARD Crea la figura y guarda los handles en un contenedor por referencia.
    % BUILD_DASHBOARD Creates the figure and stores the handles in a by-reference container.
    %
    % DECISIÓN: containers.Map como almacén mutable | RAZÓN: es un objeto handle, el
    %   callback puede actualizar el historial sin variables globales | ALTERNATIVA
    %   DESCARTADA: variables globales
    % DECISION: containers.Map as mutable storage | REASON: it is a handle object, the
    %   callback can update the history without globals | DISCARDED ALTERNATIVE: globals
    ui = containers.Map();
    fig = figure('Name', 'Prosthesis agent debug / Depuración del agente', ...
        'NumberTitle', 'off', 'Color', 'w', 'Position', [60, 60, 1400, 820]);
    layout = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

    % 1) EMG
    ax_emg = nexttile(layout, 1, [2, 1]);
    hold(ax_emg, 'on');
    emg_lines = gobjects(1, 8);
    colors = turbo(8);
    for k = 1:8
        emg_lines(k) = plot(ax_emg, 1:40, zeros(1, 40) + (9 - k), ...
            'Color', colors(k, :), 'LineWidth', 1);
    end
    set(ax_emg, 'YTick', 1:8, 'YTickLabel', {'CH8', 'CH7', 'CH6', 'CH5', 'CH4', ...
        'CH3', 'CH2', 'CH1'});
    ylim(ax_emg, [0, 9]);
    title(ax_emg, 'EMG filtrado / filtered');
    xlabel(ax_emg, 'muestra / sample');
    grid(ax_emg, 'on');

    % 2) RMS
    ax_rms = nexttile(layout, 2);
    rms_bars = bar(ax_rms, 1:8, zeros(1, 8), 'FaceColor', 'flat');
    hold(ax_rms, 'on');
    yline(ax_rms, 0.15, '--', 'REST');
    yline(ax_rms, 0.40, 'r-', 'ACTIVE');
    ylim(ax_rms, [0, 1]);
    set(ax_rms, 'XTick', 1:8, 'XTickLabel', compose('CH%d', 1:8));
    title(ax_rms, 'RMS normalizado / normalized');

    % 3) Latencias / latencies
    ax_lat = nexttile(layout, 3);
    hold(ax_lat, 'on');
    llm_line = plot(ax_lat, nan(1, history_len), 'b-', 'LineWidth', 1.5);
    cycle_line = plot(ax_lat, nan(1, history_len), 'k--');
    legend(ax_lat, {'LLM', 'ciclo / cycle'}, 'Location', 'northwest');
    ylabel(ax_lat, 'ms');
    title(ax_lat, 'Latencia / latency');
    grid(ax_lat, 'on');

    % 4) Origen / source
    ax_src = nexttile(layout, 5);
    src_image = image(ax_src, ones(1, history_len, 3));
    set(ax_src, 'YTick', []);
    title(ax_src, 'Origen: verde=LLM, naranja=LDA / Source: green=LLM, orange=LDA');
    xlabel(ax_src, 'ciclos recientes / recent cycles');

    % 5) Texto / text
    ax_txt = nexttile(layout, 6);
    axis(ax_txt, 'off');
    info_text = text(ax_txt, 0, 1, '', 'VerticalAlignment', 'top', ...
        'FontName', 'Consolas', 'FontSize', 9, 'Interpreter', 'none');

    % 6) Imagen del VLM / VLM image
    ax_img = nexttile(layout, 7, [1, 3]);
    vlm_image = image(ax_img, ones(480, 640, 3));
    axis(ax_img, 'image', 'off');
    title(ax_img, 'Imagen enviada al VLM / Image sent to the VLM');

    ui('fig') = fig;
    ui('emg_lines') = emg_lines;
    ui('ax_emg') = ax_emg;
    ui('rms_bars') = rms_bars;
    ui('llm_line') = llm_line;
    ui('cycle_line') = cycle_line;
    ui('src_image') = src_image;
    ui('info_text') = info_text;
    ui('vlm_image') = vlm_image;
    ui('llm_hist') = nan(1, history_len);
    ui('cycle_hist') = nan(1, history_len);
    ui('src_hist') = ones(1, history_len, 3);
    ui('colors') = turbo(256);
end

% -------------------------------------------------------------------------------------------
function keep_running = update_dashboard(ui, info)
    % UPDATE_DASHBOARD Callback OnCycle: refresca los paneles; false si se cerró la figura.
    % UPDATE_DASHBOARD OnCycle callback: refreshes panels; false if the figure was closed.
    fig = ui('fig');
    keep_running = isgraphics(fig);
    if ~keep_running
        return;
    end

    try
        % 1) EMG
        emg = info.emg_filtered;
        scale = max(max(abs(emg(:))), 1) * 2.2;
        emg_lines = ui('emg_lines');
        n = size(emg, 1);
        for k = 1:8
            set(emg_lines(k), 'XData', 1:n, 'YData', emg(:, k)' / scale + (9 - k));
        end
        xlim(ui('ax_emg'), [1, max(n, 2)]);

        % 2) RMS
        colors = ui('colors');
        idx = max(1, min(256, round(info.rms * 255) + 1));
        set(ui('rms_bars'), 'YData', info.rms, 'CData', colors(idx, :));

        % 3) Latencias / latencies
        llm_hist = [ui('llm_hist'), info.llm_latency_ms];
        cycle_hist = [ui('cycle_hist'), info.cycle_ms];
        llm_hist = llm_hist(2:end);
        cycle_hist = cycle_hist(2:end);
        ui('llm_hist') = llm_hist;
        ui('cycle_hist') = cycle_hist;
        set(ui('llm_line'), 'YData', llm_hist);
        set(ui('cycle_line'), 'YData', cycle_hist);

        % 4) Origen / source
        if strcmp(info.source, 'llm')
            color = [0.20, 0.70, 0.30];
        else
            color = [0.95, 0.55, 0.10];
        end
        src_hist = ui('src_hist');
        src_hist = cat(2, src_hist(:, 2:end, :), reshape(color, 1, 1, 3));
        ui('src_hist') = src_hist;
        set(ui('src_image'), 'CData', src_hist);

        % 5) Texto / text
        payload = info.payload;
        if numel(payload) > 70
            payload = [payload(1:70), newline, '  ', payload(71:end)];
        end
        text_rows = {
            sprintf('Ciclo / cycle : %d   (%s)', info.cycle, info.state)
            sprintf('Puerto / port : %g   intentos / attempts: %d', info.port, info.attempts)
            sprintf('LLM ok/valid  : %d / %d   %s', info.llm_ok, info.llm_valid, info.llm_error)
            ['Payload       : ', payload]
            ['Respuesta     : ', info.llm_content]
            sprintf('Decisión      : %s %s %d (%.2f) [%s]', info.command, info.action, ...
                round(info.value), info.confidence, info.source)
            sprintf('Enviado / sent: %s %d [%s]  prótesis %d', info.smoothed_command, ...
                round(info.smoothed_value), info.smoothing, info.prosthesis_ok)
            };
        set(ui('info_text'), 'String', text_rows);

        % 6) Imagen / image
        if isfile(info.img_path)
            set(ui('vlm_image'), 'CData', imread(info.img_path));
        end

        drawnow limitrate;
    catch err
        fprintf(2, 'main_debug: %s\n', err.message);
    end
end
