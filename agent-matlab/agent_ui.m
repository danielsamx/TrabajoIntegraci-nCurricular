 classdef agent_ui < handle
    % AGENT_UI Interfaz gráfica del agente. Ejecute:  agent_ui
    %   Cabecera      : logo, Dashboard / Prompt, Iniciar / Detener (solo uno activo a la vez).
    %   Barra lateral : Adquisición, Servidor LLM y Prótesis (con Probar conexión);
    %                   al final, Guardar configuración.
    %   Dashboard     : indicadores, 8 canales, vista general, imagen del LLM, comandos.
    %   Prompt        : plantilla editable del system prompt y prompt final.
    %   Todo sigue imprimiéndose en la consola, igual que con main.

    properties (Constant)
        RED = [238 46 36] / 255         % #EE2E24  acción principal, ACTIVE, alertas
        NAVY = [0 42 92] / 255          % #002A5C  texto, títulos, líneas
        YELLOW = [253 190 87] / 255     % #FDBE57  acentos, TRANSITION
        WHITE = [1 1 1]                 % superficies
        BG = [0.95 0.96 0.98]           % fondo de la ventana (blanco azulado muy claro)
        MUTED = [0.42 0.48 0.58]        % texto secundario (azul grisáceo)
        HISTORY_S = 2                   % segundos de señal visibles en los gráficos
        OFFSET = 150                    % separación vertical entre canales en la vista general
    end

    properties
        cfg                 % configuración base (agent_config.m)
        fig                 % ventana principal
        controls = struct() % campos de la barra lateral, por nombre de campo de cfg
        spec = struct()     % campos por sección: {ruta en cfg, etiqueta, tipo, opciones}
        btn = struct()      % botones que cambian de estado (iniciar, detener, pestañas)
        status_text         % mensaje de la última acción (bajo Guardar configuración)
        views = struct()    % paneles de contenido: dashboard y prompt
        tiles = struct()    % valores de los indicadores del dashboard
        chan_lines          % líneas de los 8 canales
        overview_ax         % ejes de la vista general
        overview_lines      % líneas de la vista general
        bars_ax             % ejes de la imagen enviada al LLM
        bars_img            % imagen enviada al LLM
        hist_ax             % ejes del historial de comandos
        hist_line           % línea del historial de comandos
        detail              % texto con el detalle del ciclo
        prompt_file         % desplegable con el archivo del prompt
        prompt_edit         % plantilla editable
        prompt_final        % prompt final (solo lectura)
        history             % últimos 2 s de EMG (muestras x 8)
        commands = {}       % comandos enviados (historial)
        command_list = {}   % comandos posibles, en el orden del eje Y
        running = false     % true mientras el agente está en marcha
        closing = false     % true si se cerró la ventana durante la ejecución
    end

    methods
        function obj = agent_ui()
            % Construye la ventana con la configuración de agent_config.m.
            add_project_paths();                                    % carpetas del proyecto al path
            obj.cfg = agent_config();                               % configuración base
            obj.define_fields();                                    % campos de la barra lateral
            obj.build();                                            % crea todos los componentes
            obj.load_prompt();                                      % carga el prompt del archivo
            obj.show_view('dashboard');                             % vista inicial
        end
    end

    methods (Access = private)
        %% Construcción de la ventana
        function define_fields(obj)
            % Campos editables: ruta en cfg, etiqueta, tipo de control y opciones.
            obj.spec.acq = {
                'source',                  'Fuente',               'dropdown', {'myo', 'samples'}
                'myo.device_name',         'Nombre del Myo',       'text',     []
                'samples.folder',          'Carpeta de muestras',  'folder',   []
                'samples.count',           'Archivos',             'numeric',  []
                'samples.loop',            'Repetir al terminar',  'check',    []
                'fs',                      'Muestreo (Hz)',        'numeric',  []
                'window_ms',               'Ventana (ms)',         'numeric',  []
                'period_s',                'Periodo mínimo (s)',   'numeric',  []
                'max_cycles',              'Ciclos máx. (Inf)',    'numeric',  []
                'signal.rest_threshold',   'Umbral REST',          'numeric',  []
                'signal.active_threshold', 'Umbral ACTIVE',        'numeric',  []
                'signal.powerline_hz',     'Red eléctrica (Hz)',   'numeric',  []
                'console.raw_window',      'Consola: señal cruda', 'check',    []
                'console.filtered_window', 'Consola: filtrada',    'check',    []};
            obj.spec.llm = {
                'llm.ip',                  'IP',                   'text',     []
                'llm.ports',               'Puertos',              'vector',   []
                'llm.endpoint',            'Endpoint',             'text',     []
                'llm.model',               'Modelo',               'text',     []
                'llm.api_key',             'API key',              'text',     []
                'llm.timeout',             'Timeout (s)',          'numeric',  []
                'llm.max_tokens',          'Tokens máximos',       'numeric',  []
                'llm.temperature',         'Temperatura',          'numeric',  []};
            obj.spec.pro = {
                'prosthesis.host',         'Host',                 'text',     []
                'prosthesis.port',         'Puerto',               'numeric',  []
                'prosthesis.endpoint',     'Endpoint',             'text',     []
                'prosthesis.timeout',      'Timeout (s)',          'numeric',  []
                'rest_command',            'Comando de reposo',    'text',     []
                'prosthesis.safe_command', 'Comando al detener',   'text',     []};
        end

        function build(obj)
            % Cabecera con logo, línea de acento, barra lateral y área de contenido.
            obj.fig = uifigure('Name', 'Agente prótesis sEMG + LLM', 'Position', [40 40 1560 900], ...
                'Color', obj.BG);
            obj.fig.CloseRequestFcn = @(~, ~) obj.on_close();       % cierre seguro
            root = uigridlayout(obj.fig, [3 2], 'RowHeight', {68, 3, '1x'}, ...
                'ColumnWidth', {330, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0, ...
                'ColumnSpacing', 0, 'BackgroundColor', obj.BG);

            obj.build_header(root);                                 % fila 1, ambas columnas
            accent = uipanel(root, 'BorderType', 'none', 'BackgroundColor', obj.YELLOW); % línea amarilla
            accent.Layout.Row = 2;
            accent.Layout.Column = [1 2];

            obj.build_sidebar(root);                                % fila 3, columna 1
            content = uigridlayout(root, [1 1], 'Padding', [14 14 14 14], 'BackgroundColor', obj.BG);
            content.Layout.Row = 3;
            content.Layout.Column = 2;
            obj.views.dashboard = uipanel(content, 'BorderType', 'none', 'BackgroundColor', obj.BG);
            obj.views.prompt = uipanel(content, 'BorderType', 'none', 'BackgroundColor', obj.BG);
            obj.views.prompt.Layout.Row = 1;                        % misma celda que el dashboard
            obj.views.prompt.Layout.Column = 1;
            obj.build_dashboard(obj.views.dashboard);
            obj.build_prompt_view(obj.views.prompt);
        end

        function build_header(obj, root)
            % Logo, título, navegación entre vistas e Iniciar / Detener.
            head = uigridlayout(root, [1 7], 'ColumnWidth', {290, '1x', 110, 110, 24, 110, 110}, ...
                'Padding', [16 10 16 10], 'ColumnSpacing', 10, 'BackgroundColor', obj.WHITE);
            head.Layout.Row = 1;
            head.Layout.Column = [1 2];
            logo = fullfile(fileparts(mfilename('fullpath')), 'assets', 'logo-laboratorio-alan-turing.png');
            if isfile(logo)
                uiimage(head, 'ImageSource', logo, 'ScaleMethod', 'fit', 'HorizontalAlignment', 'left');
            else
                uilabel(head, 'Text', '');                          % sin logo, hueco vacío
            end
            uilabel(head, 'Text', 'Control de prótesis  ·  sEMG + LLM', 'FontSize', 18, ...
                'FontWeight', 'bold', 'FontColor', obj.NAVY);
            obj.btn.tab_dashboard = uibutton(head, 'Text', 'Dashboard', ...
                'ButtonPushedFcn', @(~, ~) obj.show_view('dashboard'));
            obj.btn.tab_prompt = uibutton(head, 'Text', 'Prompt', ...
                'ButtonPushedFcn', @(~, ~) obj.show_view('prompt'));
            uilabel(head, 'Text', '');                              % separación entre vistas y acciones
            obj.btn.start = make_button(head, '▶  Iniciar', obj.RED, obj.WHITE, @(~, ~) obj.on_start());
            obj.btn.stop = make_button(head, '■  Detener', obj.NAVY, obj.WHITE, @(~, ~) obj.on_stop());
            obj.set_running(false);                                 % al abrir: Iniciar activo, Detener apagado
        end

        function build_sidebar(obj, root)
            % Tres secciones con sus campos (LLM y prótesis con su botón) y el guardado al final.
            n = [size(obj.spec.acq, 1), size(obj.spec.llm, 1), size(obj.spec.pro, 1)]; % filas por sección
            heights = num2cell(n * 30 + [44 84 84]);                % título + campos (+ botones)
            side = uigridlayout(root, [4 1], 'RowHeight', [heights, {96}], 'Scrollable', 'on', ...
                'Padding', [16 14 12 14], 'RowSpacing', 18, 'BackgroundColor', obj.WHITE);
            side.Layout.Row = 3;
            side.Layout.Column = 1;

            obj.build_section(side, 1, 'Adquisición', obj.spec.acq, false);

            buttons = obj.build_section(side, 2, 'Servidor LLM', obj.spec.llm, true);
            make_button(buttons, 'Probar conexión', obj.WHITE, obj.NAVY, @(~, ~) obj.on_test_llm());

            buttons = obj.build_section(side, 3, 'Prótesis', obj.spec.pro, true);
            make_button(buttons, 'Probar conexión', obj.WHITE, obj.NAVY, @(~, ~) obj.on_test_prosthesis());

            foot = uigridlayout(side, [2 1], 'RowHeight', {34, '1x'}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 6, 'BackgroundColor', obj.WHITE);
            place(foot, 4, 1);
            place(make_button(foot, 'Guardar configuración', obj.YELLOW, obj.NAVY, ...
                @(~, ~) obj.on_save_config()), 1, 1);
            obj.status_text = uilabel(foot, 'Text', '', 'WordWrap', 'on', 'FontSize', 11, ...
                'FontColor', obj.MUTED, 'VerticalAlignment', 'top');
            place(obj.status_text, 2, 1);
        end

        function buttons = build_section(obj, parent, row, title, fields, with_buttons)
            % Título con acento amarillo, una fila por campo y, si se pide, una fila de botones.
            rows = size(fields, 1);
            heights = [{24}, repmat({24}, 1, rows)];                % título y campos
            if with_buttons
                heights{end + 1} = 34;                              % fila de botones
            end
            g = uigridlayout(parent, [numel(heights), 2], 'ColumnWidth', {132, '1x'}, ...
                'RowHeight', heights, 'RowSpacing', 6, 'Padding', [0 0 0 0], 'BackgroundColor', obj.WHITE);
            place(g, row, 1);                                       % fila de la barra lateral
            head = uigridlayout(g, [1 2], 'ColumnWidth', {4, '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 8, 'BackgroundColor', obj.WHITE);
            place(head, 1, [1 2]);                                  % título a lo ancho
            uipanel(head, 'BorderType', 'none', 'BackgroundColor', obj.YELLOW); % barra de acento
            uilabel(head, 'Text', upper(title), 'FontSize', 12, 'FontWeight', 'bold', 'FontColor', obj.NAVY);

            for k = 1:rows
                [path, label, kind, options] = fields{k, :};        % datos del campo
                place(uilabel(g, 'Text', label, 'FontColor', obj.MUTED), k + 1, 1); % etiqueta
                value = get_path(obj.cfg, path);                    % valor actual en cfg
                switch kind
                    case 'dropdown'
                        c = uidropdown(g, 'Items', options, 'Value', value);
                    case 'text'
                        c = uieditfield(g, 'text', 'Value', value);
                    case 'numeric'
                        c = uieditfield(g, 'numeric', 'Value', value);
                    case 'vector'
                        c = uieditfield(g, 'text', 'Value', num2str(value));
                    case 'check'
                        c = uicheckbox(g, 'Text', '', 'Value', value);
                    case 'folder'
                        sub = uigridlayout(g, [1 2], 'ColumnWidth', {'1x', 28}, 'Padding', [0 0 0 0], ...
                            'ColumnSpacing', 4, 'BackgroundColor', obj.WHITE);
                        c = uieditfield(sub, 'text', 'Value', value);
                        make_button(sub, '…', obj.WHITE, obj.NAVY, @(~, ~) obj.pick_folder(c));
                        place(sub, k + 1, 2);                       % el grupo va en la columna del control
                end
                if ~strcmp(kind, 'folder')
                    place(c, k + 1, 2);                             % control a la derecha de su etiqueta
                end
                if ~strcmp(kind, 'check')
                    c.FontColor = obj.NAVY;                         % texto de los campos en azul
                end
                obj.controls.(strrep(path, '.', '_')) = c;          % guarda el control por su ruta
            end

            buttons = [];                                           % sección sin botones
            if with_buttons
                buttons = uigridlayout(g, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', obj.WHITE);
                place(buttons, rows + 2, [1 2]);                    % botón a lo ancho
            end
        end

        function build_dashboard(obj, parent)
            % Indicadores, canales, vista general, imagen del LLM, historial y detalle.
            g = uigridlayout(parent, [3 3], 'RowHeight', {78, '2.2x', '1.4x'}, ...
                'ColumnWidth', {'1x', '1x', '1.1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 12, ...
                'ColumnSpacing', 12, 'BackgroundColor', obj.BG);

            strip = uigridlayout(g, [1 6], 'Padding', [0 0 0 0], 'ColumnSpacing', 12, 'BackgroundColor', obj.BG);
            place(strip, 1, [1 3]);                                 % indicadores a lo ancho
            names = {'cycle', 'Ciclo'; 'origin', 'Fuente'; 'state', 'Estado'; ...
                'decision', 'Decidió'; 'command', 'Comando'; 'latency', 'Latencia LLM'};
            for k = 1:size(names, 1)
                obj.tiles.(names{k, 1}) = obj.make_tile(strip, k, names{k, 2});
            end

            n = obj.HISTORY_S * obj.cfg.fs;                         % muestras visibles
            t = (-(n - 1):0) / obj.cfg.fs;                          % eje de tiempo (s)
            obj.history = zeros(n, 8);                              % historial vacío
            obj.chan_lines = gobjects(1, 8);                        % espacio para las 8 líneas
            obj.overview_lines = gobjects(1, 8);

            body = obj.make_card(g, [2 1 2], sprintf('Canales · últimos %d s', obj.HISTORY_S)); % fila 2, columnas 1-2
            cg = uigridlayout(body, [4 2], 'Padding', [0 0 0 0], 'RowSpacing', 2, 'ColumnSpacing', 8, ...
                'BackgroundColor', obj.WHITE);
            for k = 1:8
                ax = obj.make_axes(cg);                             % ejes del canal k
                obj.chan_lines(k) = plot(ax, t, zeros(1, n), 'Color', obj.NAVY, 'LineWidth', 0.8);
                ax.YLim = [-128 127];                               % rango del Myo (int8)
                ax.XLim = [t(1) 0];
                ax.XTickLabel = {};                                 % sin números en X (más limpio)
                text(ax, t(1), 110, sprintf(' CH%d', k), 'FontSize', 9, 'FontWeight', 'bold', ...
                    'Color', obj.RED, 'VerticalAlignment', 'top');  % nombre del canal dentro del gráfico
            end

            [body, actions] = obj.make_card(g, [2 3], 'Vista general · 8 canales');
            make_button(actions, 'Exportar PNG', obj.WHITE, obj.NAVY, @(~, ~) obj.on_export());
            og = uigridlayout(body, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', obj.WHITE);
            obj.overview_ax = obj.make_axes(og);
            hold(obj.overview_ax, 'on');
            for k = 1:8                                             % un canal encima de otro
                color = obj.NAVY;                                   % canales impares en azul
                if mod(k, 2) == 0
                    color = obj.RED;                                % canales pares en rojo
                end
                obj.overview_lines(k) = plot(obj.overview_ax, t, zeros(1, n) + (9 - k) * obj.OFFSET, ...
                    'Color', color, 'LineWidth', 0.8);
            end
            obj.overview_ax.YTick = (1:8) * obj.OFFSET;             % una marca por canal
            obj.overview_ax.YTickLabel = arrayfun(@(k) sprintf('CH%d', k), 8:-1:1, 'UniformOutput', false);
            obj.overview_ax.YLim = [0 9 * obj.OFFSET];
            obj.overview_ax.XLim = [t(1) 0];
            xlabel(obj.overview_ax, 'tiempo (s)', 'Color', obj.MUTED);

            body = obj.make_card(g, [3 1], 'Imagen enviada al LLM');
            ig = uigridlayout(body, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', obj.WHITE);
            obj.bars_ax = obj.make_axes(ig);
            obj.bars_img = image(obj.bars_ax, uint8(255 * ones(obj.cfg.image.height, obj.cfg.image.width, 3)));
            axis(obj.bars_ax, 'image');                             % sin deformar la imagen
            obj.bars_ax.Visible = 'off';                            % sin ejes alrededor

            body = obj.make_card(g, [3 2], 'Comandos enviados');
            hg = uigridlayout(body, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', obj.WHITE);
            obj.hist_ax = obj.make_axes(hg);
            obj.hist_line = plot(obj.hist_ax, NaN, NaN, '-o', 'Color', obj.NAVY, 'LineWidth', 1.2, ...
                'MarkerSize', 4, 'MarkerFaceColor', obj.RED, 'MarkerEdgeColor', obj.RED);
            xlabel(obj.hist_ax, 'ciclo', 'Color', obj.MUTED);

            body = obj.make_card(g, [3 3], 'Detalle del ciclo');
            dg = uigridlayout(body, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', obj.WHITE);
            obj.detail = uitextarea(dg, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11, ...
                'FontColor', obj.NAVY, 'Value', {'Pulse Iniciar en Adquisición para comenzar.'});
        end

        function build_prompt_view(obj, parent)
            % Plantilla editable y prompt final, en una tarjeta con su barra de botones.
            g = uigridlayout(parent, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', obj.BG);
            [body, actions] = obj.make_card(g, [1 1], 'System prompt');
            actions.ColumnWidth = {150, 100, 100, 170};             % espacio para 4 controles
            [~, name, ext] = fileparts(obj.cfg.llm.prompt_file);    % archivo configurado
            obj.prompt_file = uidropdown(actions, 'Items', {'system_es.txt', 'system_en.txt'}, ...
                'Value', [name ext], 'FontColor', obj.NAVY, 'ValueChangedFcn', @(~, ~) obj.load_prompt());
            make_button(actions, 'Recargar', obj.WHITE, obj.NAVY, @(~, ~) obj.load_prompt());
            make_button(actions, 'Guardar', obj.YELLOW, obj.NAVY, @(~, ~) obj.save_prompt());
            make_button(actions, 'Ver prompt final', obj.NAVY, obj.WHITE, @(~, ~) obj.preview_prompt());

            pg = uigridlayout(body, [2 2], 'RowHeight', {22, '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 12, 'BackgroundColor', obj.WHITE);
            uilabel(pg, 'Text', 'Plantilla editable · marcadores {{GESTOS}} y {{REPOSO}}', ...
                'FontColor', obj.MUTED);
            uilabel(pg, 'Text', 'Prompt final que recibe el LLM', 'FontColor', obj.MUTED);
            obj.prompt_edit = uitextarea(pg, 'FontName', 'Consolas', 'FontSize', 12, 'FontColor', obj.NAVY);
            obj.prompt_final = uitextarea(pg, 'FontName', 'Consolas', 'FontSize', 12, 'Editable', 'off', ...
                'FontColor', obj.NAVY, 'BackgroundColor', [0.98 0.98 0.99]);
        end

        %% Piezas de diseño
        function [body, actions] = make_card(obj, parent, pos, title)
            % Tarjeta blanca en pos = [fila columna(s)], con título y zona de botones a la derecha.
            panel = uipanel(parent, 'BorderType', 'none', 'BackgroundColor', obj.WHITE);
            place(panel, pos(1), pos(2:end));                       % celda de la tarjeta
            g = uigridlayout(panel, [2 2], 'RowHeight', {26, '1x'}, 'ColumnWidth', {'1x', 'fit'}, ...
                'Padding', [14 10 14 12], 'RowSpacing', 8, 'BackgroundColor', obj.WHITE);
            place(uilabel(g, 'Text', title, 'FontSize', 13, 'FontWeight', 'bold', 'FontColor', obj.NAVY), 1, 1);
            actions = uigridlayout(g, [1 4], 'ColumnWidth', {'fit', 'fit', 'fit', 'fit'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', obj.WHITE);
            place(actions, 1, 2);                                   % botones arriba a la derecha
            body = uipanel(g, 'BorderType', 'none', 'BackgroundColor', obj.WHITE);
            place(body, 2, [1 2]);                                  % contenido a lo ancho
        end

        function value_label = make_tile(obj, parent, column, title)
            % Indicador: tarjeta blanca con línea amarilla arriba, título pequeño y valor grande.
            panel = uipanel(parent, 'BorderType', 'none', 'BackgroundColor', obj.WHITE);
            place(panel, 1, column);                                % columna de la fila de indicadores
            g = uigridlayout(panel, [3 1], 'RowHeight', {3, 16, '1x'}, 'Padding', [14 8 14 0], ...
                'RowSpacing', 6, 'BackgroundColor', obj.WHITE);
            place(uipanel(g, 'BorderType', 'none', 'BackgroundColor', obj.YELLOW), 1, 1); % acento arriba
            title_label = uilabel(g, 'Text', upper(title), 'FontSize', 10, 'FontWeight', 'bold', ...
                'FontColor', obj.MUTED, 'HorizontalAlignment', 'left');
            place(title_label, 2, 1);                               % título debajo del acento
            value_label = uilabel(g, 'Text', '–', 'FontSize', 22, 'FontWeight', 'bold', ...
                'FontColor', obj.NAVY, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'center');
            place(value_label, 3, 1);                               % valor grande abajo
        end

        function ax = make_axes(obj, parent)
            % Ejes minimalistas: sin caja ni barra de herramientas, rejilla suave.
            ax = uiaxes(parent);
            ax.Toolbar.Visible = 'off';                             % sin barra de herramientas
            disableDefaultInteractivity(ax);                        % sin zoom ni desplazamiento
            ax.FontSize = 9;
            ax.Color = obj.WHITE;
            ax.XColor = obj.MUTED;                                  % ejes en azul grisáceo
            ax.YColor = obj.MUTED;
            ax.GridColor = obj.NAVY;
            ax.GridAlpha = 0.08;                                    % rejilla casi invisible
            ax.Box = 'off';
            grid(ax, 'on');
        end

        function show_view(obj, name)
            % Muestra 'dashboard' o 'prompt' y marca el botón activo de la cabecera.
            obj.views.dashboard.Visible = strcmp(name, 'dashboard');
            obj.views.prompt.Visible = strcmp(name, 'prompt');
            style_tab(obj.btn.tab_dashboard, strcmp(name, 'dashboard'), obj);
            style_tab(obj.btn.tab_prompt, strcmp(name, 'prompt'), obj);
        end

        function set_running(obj, running)
            % Iniciar activo solo cuando está detenido; Detener activo solo cuando está en marcha.
            obj.running = running;                                  % estado del agente
            obj.btn.start.Enable = ~running;                        % Iniciar se apaga en ejecución
            obj.btn.stop.Enable = running;                          % Detener se apaga sin ejecución
        end

        %% Configuración
        function cfg = read_controls(obj)
            % cfg = configuración base + valores de la barra lateral.
            cfg = obj.cfg;                                          % parte de agent_config.m
            fields = [obj.spec.acq; obj.spec.llm; obj.spec.pro];    % todos los campos
            for k = 1:size(fields, 1)
                [path, ~, kind] = fields{k, 1:3};                   % ruta y tipo
                value = obj.controls.(strrep(path, '.', '_')).Value; % valor en la UI
                if strcmp(kind, 'vector')
                    value = sscanf(value, '%f')';                   % '1234 1235' -> [1234 1235]
                end
                cfg = set_path(cfg, path, value);                   % lo copia en cfg
            end
        end

        function on_save_config(obj)
            % Escribe los valores de la UI en config/agent_config.m (conserva los comentarios).
            cfg = obj.read_controls();                              % valores actuales
            file = which('agent_config');                           % ruta del archivo
            lines = splitlines(string(read_text(file)));            % una línea por elemento
            fields = [obj.spec.acq; obj.spec.llm; obj.spec.pro];
            for k = 1:size(fields, 1)
                path = fields{k, 1};                                % ruta en cfg
                value = get_path(cfg, path);                        % valor nuevo
                if isequal(value, get_path(obj.cfg, path))          % no cambió
                    continue;
                end
                pattern = ['^(cfg\.' regexptranslate('escape', path) '\s*=\s*)[^;]*;'];
                code = value_to_code(value);                        % valor como código MATLAB
                lines = regexprep(lines, pattern, ['$1' regexprep(code, '([\\$])', '\\$1') ';'], 'once');
            end
            write_text(file, char(strjoin(lines, newline)));        % guarda el archivo
            obj.cfg = cfg;                                          % nueva configuración base
            obj.note(sprintf('Configuración guardada en %s', file));
        end

        function pick_folder(obj, field)
            % Elige una carpeta con el explorador y la pone en el campo.
            folder = uigetdir(field.Value, 'Carpeta de muestras');  % abre el explorador
            figure(obj.fig);                                        % devuelve el foco a la UI
            if ischar(folder)                                       % no se canceló
                field.Value = folder;
            end
        end

        %% Prompt
        function load_prompt(obj)
            % Carga en el editor el archivo de prompt elegido.
            file = fullfile(fileparts(which('agent_config')), obj.prompt_file.Value);
            obj.prompt_edit.Value = cellstr(splitlines(string(read_text(file))));
            obj.preview_prompt();                                   % actualiza el prompt final
        end

        function save_prompt(obj)
            % Guarda la plantilla editada en su archivo.
            file = fullfile(fileparts(which('agent_config')), obj.prompt_file.Value);
            write_text(file, obj.template());                       % escribe el texto
            obj.note(sprintf('Prompt guardado en %s', file));
        end

        function preview_prompt(obj)
            % Muestra el prompt final con los gestos y el comando de reposo insertados.
            text = build_system_prompt(obj.template(), obj.read_controls());
            obj.prompt_final.Value = cellstr(splitlines(string(text)));
        end

        function text = template(obj)
            % Texto actual del editor de la plantilla.
            text = strjoin(obj.prompt_edit.Value, newline);
        end

        %% Ejecución
        function on_start(obj)
            % Inicia el agente y actualiza el dashboard en cada ciclo.
            if obj.running
                return;                                             % ya está en marcha
            end
            cfg = obj.read_controls();                              % configuración de la UI
            obj.preview_prompt();                                   % prompt final actualizado
            try
                session = agent_session(cfg, obj.template());       % registro, prompt y fuente
            catch err
                uialert(obj.fig, err.message, 'No se pudo iniciar');
                return;
            end
            obj.reset_dashboard(cfg);                               % gráficos vacíos
            obj.set_running(true);                                  % Iniciar apagado, Detener activo
            obj.note(sprintf('Fuente: %s. Registro: %s', session.device.source, session.log_file));
            try
                while obj.running && session.stats.cycles < cfg.max_cycles
                    r = session.step();                             % un ciclo completo
                    if r.done                                       % no quedan muestras
                        break;
                    end
                    obj.update_dashboard(r, cfg);                   % refresca la UI
                    drawnow limitrate;                              % atiende botones y redibuja
                    pause(max(0, cfg.period_s - r.cycle_ms / 1000)); % completa el periodo
                end
                summary = session.finish();                         % resumen y reposo
                obj.note(sprintf('Terminado: %d ciclos, %d del LLM, %d de respaldo.', ...
                    summary.cycles, summary.llm_ok, summary.fallback));
            catch err
                session.finish();                                   % deja la prótesis en reposo
                obj.note(['Error: ' err.message]);
                if ~obj.closing
                    uialert(obj.fig, err.message, 'Error durante la ejecución');
                end
            end
            obj.running = false;                                    % estado: detenido
            if obj.closing                                          % se pidió cerrar la ventana
                delete(obj.fig);
                return;
            end
            obj.set_running(false);                                 % Iniciar activo, Detener apagado
        end

        function on_stop(obj)
            % Detiene el bucle al terminar el ciclo actual.
            obj.running = false;                                    % el bucle sale tras este ciclo
            obj.btn.stop.Enable = false;                            % evita pulsarlo dos veces
            obj.note('Deteniendo al final del ciclo actual...');
        end

        function on_close(obj)
            % Cierra la ventana; si el agente corre, primero lo detiene.
            if obj.running
                obj.closing = true;                                 % on_start cerrará la ventana
                obj.running = false;
            else
                delete(obj.fig);
            end
        end

        %% Dashboard
        function reset_dashboard(obj, cfg)
            % Vacía los gráficos al iniciar una sesión.
            obj.history(:) = 0;                                     % señal a cero
            obj.commands = {};                                      % sin comandos enviados
            obj.command_list = [{cfg.rest_command}, {cfg.gestures.command}]; % S, C, O
            obj.hist_ax.YTick = 1:numel(obj.command_list);          % una marca por comando
            obj.hist_ax.YTickLabel = obj.command_list;
            obj.hist_ax.YLim = [0.5, numel(obj.command_list) + 0.5];
            set(obj.hist_line, 'XData', NaN, 'YData', NaN);
        end

        function update_dashboard(obj, r, cfg)
            % Muestra los resultados de un ciclo.
            obj.history = [obj.history(size(r.emg, 1) + 1:end, :); r.emg]; % desplaza y añade la ventana
            for k = 1:8
                obj.chan_lines(k).YData = obj.history(:, k);        % canal k
                obj.overview_lines(k).YData = obj.history(:, k) + (9 - k) * obj.OFFSET; % vista general
            end

            img = imread(r.image_file);                             % imagen enviada al LLM
            [h, w, ~] = size(img);                                  % su tamaño en píxeles
            set(obj.bars_img, 'CData', img, 'XData', [1 w], 'YData', [1 h]);
            obj.bars_ax.XLim = [0.5 w + 0.5];                       % ajusta los ejes a la imagen
            obj.bars_ax.YLim = [0.5 h + 0.5];

            obj.commands{end + 1} = r.sent.command;                 % historial de comandos
            y = cellfun(@(c) find(strcmp(obj.command_list, c), 1), obj.commands); % comando -> fila
            x = 1:numel(y);                                         % número de ciclo
            keep = max(1, numel(y) - 59):numel(y);                  % últimos 60 ciclos
            set(obj.hist_line, 'XData', x(keep), 'YData', y(keep));
            obj.hist_ax.XLim = [x(keep(1)) - 0.5, x(keep(end)) + 0.5];

            obj.tiles.cycle.Text = sprintf('%d', r.cycle);
            obj.tiles.origin.Text = r.source;
            obj.tiles.state.Text = r.f.state;
            obj.tiles.state.FontColor = obj.state_color(r.f.state);
            obj.tiles.decision.Text = upper(r.decided.source);      % 'LLM' o 'RESPALDO'
            obj.tiles.decision.FontColor = ternary(r.valid, obj.NAVY, obj.RED);
            obj.tiles.command.Text = r.sent.command;
            obj.tiles.command.FontColor = ternary(strcmp(r.sent.command, cfg.rest_command), obj.NAVY, obj.RED);
            obj.tiles.latency.Text = sprintf('%.0f ms', r.reply.latency_ms);

            sim = '';                                               % similitud con cada gesto
            for g = 1:numel(cfg.gestures)
                sim = [sim, sprintf('%s=%.2f  ', cfg.gestures(g).command, r.f.similarity(g))]; %#ok<AGROW>
            end
            if r.reply.ok
                answer = r.reply.content;                           % texto del modelo
            else
                answer = ['sin respuesta: ' r.reply.error];         % motivo del fallo
            end
            obj.detail.Value = {
                sprintf('Ciclo %d · T = %d ms · %.0f ms', r.cycle, r.t_ms, r.cycle_ms)
                sprintf('Origen     %s', r.origin)
                sprintf('RMS        %s', sprintf('%.2f ', r.f.rms))
                sprintf('Similitud  %s', sim)
                sprintf('Estado     %s %s', r.f.state, r.f.noise)
                ''
                sprintf('Payload    %s', r.payload)
                sprintf('LLM        %s', answer)
                sprintf('Validación %s', ternary(r.valid, 'válido', r.reason))
                sprintf('Decidido   %s (%.2f, %s)', r.decided.command, r.decided.confidence, r.decided.source)
                sprintf('Enviado    %s (%s)', r.sent.command, r.sent.smoothing)
                sprintf('Prótesis   %s', ternary(r.prosthesis_ok, 'aceptado', 'fallo'))};
        end

        function color = state_color(obj, state)
            % Color del estado: ACTIVE rojo, TRANSITION amarillo, NOISE rojo, REST azul.
            switch state
                case {'ACTIVE', 'NOISE'}
                    color = obj.RED;
                case 'TRANSITION'
                    color = obj.YELLOW;
                otherwise
                    color = obj.NAVY;
            end
        end

        function on_export(obj)
            % Guarda la vista general de los 8 canales como PNG en logs/.
            cfg = obj.read_controls();
            if ~isfolder(cfg.log_folder)
                mkdir(cfg.log_folder);
            end
            file = fullfile(cfg.log_folder, ['vista_general_' datestr(now, 'yyyymmdd_HHMMSS') '.png']);
            exportgraphics(obj.overview_ax, file, 'Resolution', 150); % imagen de los 8 canales
            obj.note(sprintf('Vista general guardada en %s', file));
        end

        %% Pruebas de conexión
        function on_test_llm(obj)
            % Pide a LM Studio la lista de modelos de cada puerto.
            cfg = obj.read_controls();
            options = weboptions('Timeout', 5, 'HeaderFields', {'Authorization', ['Bearer ' cfg.llm.api_key]});
            report = {};
            for port = cfg.llm.ports
                url = sprintf('http://%s:%d/v1/models', cfg.llm.ip, port);
                try
                    reply = webread(url, options);                  % lista de modelos
                    data = reply.data;                              % modelos cargados
                    if iscell(data)
                        data = [data{:}];                           % celda -> array de structs
                    end
                    ids = strjoin({data.id}, ', ');                 % nombres de los modelos
                    report{end + 1} = sprintf('%s: OK (%s)', url, ids); %#ok<AGROW>
                catch err
                    report{end + 1} = sprintf('%s: %s', url, err.message); %#ok<AGROW>
                end
            end
            log_msg('UI', 'Prueba LLM: %s', strjoin(report, ' | '));
            uialert(obj.fig, strjoin(report, newline), 'Servidor LLM', 'Icon', 'info');
        end

        function on_test_prosthesis(obj)
            % Envía el comando de reposo para comprobar que la prótesis responde.
            cfg = obj.read_controls();
            ok = send_prosthesis_command(cfg.prosthesis, cfg.rest_command);
            message = sprintf('POST %s a %s:%d%s -> %s (detalle en la consola)', cfg.rest_command, ...
                cfg.prosthesis.host, cfg.prosthesis.port, cfg.prosthesis.endpoint, ternary(ok, 'aceptado', 'fallo'));
            uialert(obj.fig, message, 'Prótesis', 'Icon', ternary(ok, 'success', 'error'));
        end

        function note(obj, text)
            % Mensaje de la última acción (bajo Guardar configuración y en la consola).
            obj.status_text.Text = text;
            log_msg('UI', '%s', text);
        end
    end
end

%% Funciones auxiliares
function b = make_button(parent, text, background, foreground, callback)
% Botón plano con los colores indicados.
b = uibutton(parent, 'Text', text, 'BackgroundColor', background, 'FontColor', foreground, ...
    'FontWeight', 'bold', 'ButtonPushedFcn', callback);
end

function place(component, row, column)
% Coloca un componente en una celda (o rango de celdas) de su cuadrícula.
component.Layout.Row = row;
component.Layout.Column = column;
end

function style_tab(button, active, ui)
% Botón de navegación: activo en azul, inactivo en blanco.
if active
    button.BackgroundColor = ui.NAVY;
    button.FontColor = ui.WHITE;
else
    button.BackgroundColor = ui.WHITE;
    button.FontColor = ui.NAVY;
end
button.FontWeight = 'bold';
end

function value = get_path(s, path)
% Lee un campo anidado: get_path(cfg, 'llm.ip') = cfg.llm.ip
parts = strsplit(path, '.');
value = getfield(s, parts{:});
end

function s = set_path(s, path, value)
% Escribe un campo anidado: set_path(cfg, 'llm.ip', '1.2.3.4')
parts = strsplit(path, '.');
s = setfield(s, parts{:}, value);
end

function code = value_to_code(value)
% Convierte un valor en el texto MATLAB que lo crea (para guardar agent_config.m).
if ischar(value)
    code = ['''' strrep(value, '''', '''''') ''''];         % 'texto' con comillas escapadas
elseif islogical(value)
    code = ternary(value, 'true', 'false');                 % true / false
elseif isscalar(value)
    code = num2str(value, 10);                              % número (Inf incluido)
else
    code = mat2str(value);                                  % vector, p. ej. [1234 1235]
end
end

function out = ternary(condition, a, b)
% out = a si condition es verdadera; si no, b.
if condition
    out = a;
else
    out = b;
end
end
