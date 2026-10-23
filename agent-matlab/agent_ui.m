classdef agent_ui < handle
    % AGENT_UI Interfaz gráfica del agente. Ejecute:  agent_ui
    %   Cabecera      : logo, Dashboard / Prompt, Iniciar / Detener (solo uno activo a la vez).
    %   Barra lateral : Adquisición, Servidor LLM y Prótesis (HTTP o puerto serie); Guardar.
    %   Dashboard     : indicadores, 8 canales individuales, las 3 imágenes y comandos enviados.
    %   Prompt        : imágenes que se envían al LLM, plantilla editable y prompt final.
    %   Todo sigue imprimiéndose en la consola, igual que con main.

    properties (Constant)
        RED = [238 46 36] / 255         % #EE2E24  Detener y alertas
        NAVY = [0 42 92] / 255          % #002A5C  botones, títulos, texto
        YELLOW = [253 190 87] / 255     % #FDBE57  solo acentos (nunca texto)
        WHITE = [1 1 1]                 % superficies
        BG = [0.95 0.96 0.98]           % fondo de la ventana
        MUTED = [0.42 0.48 0.58]        % texto secundario
        SOFT = [0.36 0.47 0.62]         % botón de pestaña inactiva
        HISTORY_S = 2                   % segundos visibles en los canales individuales
    end

    properties
        cfg                 % configuración base (agent_config.m)
        fig                 % ventana principal
        fields = {}         % campos editables: {ruta en cfg, etiqueta, tipo, opciones}
        controls = struct() % control de cada campo, por ruta (con '_' en lugar de '.')
        btn = struct()      % botones que cambian de estado
        mode_grids = struct() % filas de HTTP y de puerto serie (se muestra una)
        status_text         % mensaje de la última acción
        views = struct()    % paneles de contenido: dashboard y prompt
        tiles = struct()    % valores de los indicadores
        img_axes = struct() % ejes de cada imagen del dashboard
        img_badges = struct() % etiqueta "se envía / no se envía" de cada imagen
        hist_ax             % ejes del historial de comandos
        hist_line           % línea del historial de comandos
        chan_lines          % líneas de los 8 canales individuales
        history             % últimos segundos de EMG crudo (muestras x 8)
        prompt_file         % desplegable con el archivo del prompt
        prompt_edit         % plantilla editable
        prompt_final        % prompt final (solo lectura)
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
            obj.build();                                            % crea todos los componentes
            obj.load_prompt();                                      % carga el prompt del archivo
            obj.update_mode();                                      % HTTP o serie, según cfg
            obj.update_badges();                                    % imágenes marcadas
            obj.show_view('dashboard');                             % vista inicial
        end
    end

    methods (Access = private)
        %% Ventana
        function build(obj)
            % Cabecera, línea de acento, barra lateral y área de contenido.
            obj.fig = uifigure('Name', 'Agente prótesis sEMG + LLM', 'Position', [30 30 1600 900], ...
                'Color', obj.BG);
            obj.fig.CloseRequestFcn = @(~, ~) obj.on_close();       % cierre seguro
            obj.fig.WindowState = 'maximized';                      % ocupa toda la pantalla (nada queda fuera)
            root = uigridlayout(obj.fig, [3 2], 'RowHeight', {64, 3, '1x'}, 'ColumnWidth', {350, '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 0, 'ColumnSpacing', 0, 'BackgroundColor', obj.BG);
            obj.build_header(root);                                 % fila 1
            place(uipanel(root, 'BorderType', 'none', 'BackgroundColor', obj.YELLOW), 2, [1 2]); % acento
            obj.build_sidebar(root);                                % fila 3, columna 1
            content = uigridlayout(root, [1 1], 'Padding', [14 14 14 14], 'BackgroundColor', obj.BG);
            place(content, 3, 2);
            obj.views.dashboard = uipanel(content, 'BorderType', 'none', 'BackgroundColor', obj.BG);
            obj.views.prompt = uipanel(content, 'BorderType', 'none', 'BackgroundColor', obj.BG);
            place(obj.views.dashboard, 1, 1);                       % las dos vistas en la misma celda
            place(obj.views.prompt, 1, 1);
            obj.build_dashboard(obj.views.dashboard);
            obj.build_prompt_view(obj.views.prompt);
        end

        function build_header(obj, root)
            % Logo, título, navegación e Iniciar / Detener.
            head = uigridlayout(root, [1 7], 'ColumnWidth', {280, '1x', 110, 110, 30, 120, 120}, ...
                'Padding', [16 12 16 12], 'ColumnSpacing', 8, 'BackgroundColor', obj.WHITE);
            place(head, 1, [1 2]);
            logo = fullfile(fileparts(mfilename('fullpath')), 'assets', 'logo-laboratorio-alan-turing.png');
            if isfile(logo)
                place(uiimage(head, 'ImageSource', logo, 'ScaleMethod', 'fit', ...
                    'HorizontalAlignment', 'left'), 1, 1);
            end
            place(uilabel(head, 'Text', 'Control de prótesis  ·  sEMG + LLM', 'FontSize', 18, ...
                'FontWeight', 'bold', 'FontColor', obj.NAVY), 1, 2);
            obj.btn.tab_dashboard = obj.button(head, 'Dashboard', obj.NAVY, @(~, ~) obj.show_view('dashboard'));
            obj.btn.tab_prompt = obj.button(head, 'Prompt', obj.NAVY, @(~, ~) obj.show_view('prompt'));
            obj.btn.start = obj.button(head, '▶  Iniciar', obj.NAVY, @(~, ~) obj.on_start());
            obj.btn.stop = obj.button(head, '■  Detener', obj.RED, @(~, ~) obj.on_stop());
            place(obj.btn.tab_dashboard, 1, 3);
            place(obj.btn.tab_prompt, 1, 4);
            place(obj.btn.start, 1, 6);
            place(obj.btn.stop, 1, 7);
            obj.set_running(false);                                 % al abrir: Iniciar activo
        end

        %% Barra lateral (sin desplazamiento)
        function build_sidebar(obj, root)
            % Adquisición, Servidor LLM, Prótesis y Guardar configuración.
            side = uigridlayout(root, [4 1], 'RowHeight', {'6x', '8x', '7x', '2.2x'}, ... % reparto según filas
                'Padding', [16 12 14 12], 'RowSpacing', 14, 'BackgroundColor', obj.WHITE); % ocupa todo el alto
            place(side, 3, 1);

            g = obj.section(side, 1, 'Adquisición (Myo)', 4, true);
            obj.add_row(g, 2, {{'myo.link', 'Conexión Myo', 'choice', ...
                {{'Adaptador USB', 'Bluetooth del PC'}, {'dongle', 'bluetooth'}}}});
            obj.mode_grids.dongle = obj.subrows(g, 3);              % fila solo para el adaptador USB
            obj.add_row(obj.mode_grids.dongle, 1, {{'myo.dongle_port', 'Puerto USB', 'serial', []}});
            obj.mode_grids.bluetooth = obj.subrows(g, 3);           % fila solo para Bluetooth del PC
            obj.add_row(obj.mode_grids.bluetooth, 1, {{'myo.device_name', 'Nombre del Myo', 'text', []}});
            obj.add_row(g, 4, {{'window_ms', 'Ventana (ms)', 'numeric', []}, ...
                {'period_s', 'Periodo (s)', 'numeric', []}});
            obj.add_row(g, 5, {{'max_cycles', 'Ciclos máx.', 'numeric', []}, ...
                {'signal.powerline_hz', 'Red (Hz)', 'numeric', []}});
            place(obj.button(g, 'Probar Myo', obj.NAVY, @(~, ~) obj.on_test_myo()), 6, [1 2]);

            g = obj.section(side, 2, 'Servidor LLM', 6, true);
            obj.add_row(g, 2, {{'llm.ip', 'IP', 'text', []}});
            obj.add_row(g, 3, {{'llm.ports', 'Puertos', 'vector', []}, {'llm.timeout', 'Timeout (s)', 'numeric', []}});
            obj.add_row(g, 4, {{'llm.endpoint', 'Endpoint', 'text', []}});
            obj.add_row(g, 5, {{'llm.model', 'Modelo', 'model', []}}); % lista de modelos del servidor
            obj.add_row(g, 6, {{'llm.api_key', 'API key', 'text', []}});
            obj.add_row(g, 7, {{'llm.max_tokens', 'Tokens', 'numeric', []}, ...
                {'llm.temperature', 'Temperatura', 'numeric', []}});
            place(obj.button(g, 'Probar conexión', obj.NAVY, @(~, ~) obj.on_test_llm()), 8, [1 2]);

            g = obj.section(side, 3, 'Prótesis', 5, true);
            obj.add_row(g, 2, {{'prosthesis.mode', 'Comunicación', 'switch', {'HTTP', 'Serial'}}});
            obj.mode_grids.http = obj.subrows(g, [3 4]);            % filas solo para HTTP
            obj.add_row(obj.mode_grids.http, 1, {{'prosthesis.host', 'Host', 'text', []}});
            obj.add_row(obj.mode_grids.http, 2, {{'prosthesis.port', 'Puerto', 'numeric', []}, ...
                {'prosthesis.endpoint', 'Ruta', 'text', []}});
            obj.mode_grids.serial = obj.subrows(g, [3 4]);          % filas solo para puerto serie
            obj.add_row(obj.mode_grids.serial, 1, {{'prosthesis.serial_port', 'Puerto serie', 'serial', []}});
            obj.add_row(obj.mode_grids.serial, 2, {{'prosthesis.baud_rate', 'Baudios', 'numeric', []}, ...
                {'prosthesis.terminator', 'Fin', 'dropdown', {'LF', 'CR', 'CR/LF'}}});
            obj.add_row(g, 5, {{'prosthesis.timeout', 'Timeout (s)', 'numeric', []}, ...
                {'rest_command', 'Reposo', 'text', []}});
            obj.add_row(g, 6, {{'prosthesis.safe_command', 'Al detener', 'text', []}});
            place(obj.button(g, 'Probar conexión', obj.NAVY, @(~, ~) obj.on_test_prosthesis()), 7, [1 2]);

            foot = uigridlayout(side, [2 1], 'RowHeight', {34, '1x'}, 'Padding', [0 4 0 0], ...
                'RowSpacing', 6, 'BackgroundColor', obj.WHITE);
            place(foot, 4, 1);
            place(obj.button(foot, 'Guardar configuración', obj.NAVY, @(~, ~) obj.on_save_config()), 1, 1);
            obj.status_text = uilabel(foot, 'Text', '', 'WordWrap', 'on', 'FontSize', 11, ...
                'FontColor', obj.MUTED, 'VerticalAlignment', 'top');
            place(obj.status_text, 2, 1);
        end

        function g = section(obj, parent, row, title, rows, with_button)
            % Sección: título con marca amarilla, 'rows' filas de campos y, si se pide, un botón.
            %   Todas las filas miden '1x': la barra lateral se reparte el alto visible, sin scroll.
            heights = repmat({'1x'}, 1, rows + 1 + with_button);   % título, campos y botón
            g = uigridlayout(parent, [numel(heights) 2], 'RowHeight', heights, 'ColumnWidth', {104, '1x'}, ...
                'RowSpacing', 5, 'ColumnSpacing', 8, 'Padding', [0 0 0 0], 'BackgroundColor', obj.WHITE);
            place(g, row, 1);
            head = uigridlayout(g, [1 2], 'ColumnWidth', {4, '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 8, 'BackgroundColor', obj.WHITE);
            place(head, 1, [1 2]);
            place(uipanel(head, 'BorderType', 'none', 'BackgroundColor', obj.YELLOW), 1, 1); % marca
            place(uilabel(head, 'Text', upper(title), 'FontSize', 12, 'FontWeight', 'bold', ...
                'FontColor', obj.NAVY), 1, 2);
        end

        function sub = subrows(obj, g, rows)
            % Filas de campos dentro de una sección que se muestran u ocultan (HTTP / serie, USB / Bluetooth).
            sub = uigridlayout(g, [numel(rows) 2], 'RowHeight', repmat({'1x'}, 1, numel(rows)), ...
                'ColumnWidth', {104, '1x'}, ...
                'RowSpacing', 5, 'ColumnSpacing', 8, 'Padding', [0 0 0 0], 'BackgroundColor', obj.WHITE);
            place(sub, rows, [1 2]);
        end

        function add_row(obj, g, row, specs)
            % Una fila: etiqueta + control, o etiqueta + control + etiqueta + control.
            place(uilabel(g, 'Text', specs{1}{2}, 'FontColor', obj.MUTED), row, 1);
            if numel(specs) == 1
                place(obj.make_control(g, specs{1}), row, 2);       % un solo control
                return;
            end
            pair = uigridlayout(g, [1 3], 'ColumnWidth', {'1x', 'fit', '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', obj.WHITE);
            place(pair, row, 2);
            place(obj.make_control(pair, specs{1}), 1, 1);          % primer control
            place(uilabel(pair, 'Text', specs{2}{2}, 'FontColor', obj.MUTED), 1, 2); % segunda etiqueta
            place(obj.make_control(pair, specs{2}), 1, 3);          % segundo control
        end

        function holder = make_control(obj, parent, spec)
            % Crea el control de un campo con su valor actual; devuelve lo que hay que colocar.
            [path, ~, kind, options] = spec{:};
            value = get_path(obj.cfg, path);                        % valor en agent_config.m
            switch kind
                case 'dropdown'
                    c = uidropdown(parent, 'Items', options, 'Value', value);
                case 'choice'                                       % texto visible / valor guardado
                    c = uidropdown(parent, 'Items', options{1}, 'ItemsData', options{2}, 'Value', value, ...
                        'ValueChangedFcn', @(~, ~) obj.update_mode());
                case 'text'
                    c = uieditfield(parent, 'text', 'Value', value);
                case 'numeric'
                    c = uieditfield(parent, 'numeric', 'Value', value);
                case 'vector'
                    c = uieditfield(parent, 'text', 'Value', num2str(value));
                case 'check'
                    c = uicheckbox(parent, 'Text', '', 'Value', value);
                case 'switch'
                    c = uiswitch(parent, 'slider', 'Items', options, ...
                        'Value', options{strcmpi(options, value)}, ...
                        'ValueChangedFcn', @(~, ~) obj.update_mode());
                case 'model'                                        % lista de modelos + botón Cargar
                    holder = uigridlayout(parent, [1 2], 'ColumnWidth', {'1x', 66}, 'Padding', [0 0 0 0], ...
                        'ColumnSpacing', 4, 'BackgroundColor', obj.WHITE);
                    c = uidropdown(holder, 'Editable', 'on', 'Items', {value}, 'Value', value);
                    obj.button(holder, 'Cargar', obj.NAVY, @(~, ~) obj.on_load_models(c));
                case {'folder', 'serial'}
                    holder = uigridlayout(parent, [1 2], 'ColumnWidth', {'1x', 28}, 'Padding', [0 0 0 0], ...
                        'ColumnSpacing', 4, 'BackgroundColor', obj.WHITE);
                    if strcmp(kind, 'folder')
                        c = uieditfield(holder, 'text', 'Value', value);
                        obj.button(holder, '…', obj.NAVY, @(~, ~) obj.pick_folder(c));
                    else
                        auto = strcmp(path, 'myo.dongle_port');     % el adaptador del Myo admite 'auto'
                        c = uidropdown(holder, 'Editable', 'on', 'Items', serial_ports(value, auto), 'Value', value);
                        obj.button(holder, '↻', obj.NAVY, @(~, ~) set(c, 'Items', serial_ports(c.Value, auto)));
                    end
            end
            if ~any(strcmp(kind, {'check', 'switch'}))
                c.FontColor = obj.NAVY;                             % texto de los campos en azul
            end
            if ~any(strcmp(kind, {'folder', 'serial', 'model'}))
                holder = c;                                         % se coloca el propio control
            end
            obj.register(spec, c);
        end

        function register(obj, spec, c)
            % Guarda el campo y su control para leerlos y guardarlos después.
            obj.fields(end + 1, :) = spec;
            obj.controls.(strrep(spec{1}, '.', '_')) = c;
        end

        %% Dashboard
        function build_dashboard(obj, parent)
            % Indicadores, 8 canales, 3 imágenes y comandos enviados.
            g = uigridlayout(parent, [3 3], 'RowHeight', {74, '1.15x', '1x'}, 'ColumnWidth', {'1x', '1x', '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 12, 'ColumnSpacing', 12, 'BackgroundColor', obj.BG);

            strip = uigridlayout(g, [1 6], 'Padding', [0 0 0 0], 'ColumnSpacing', 12, 'BackgroundColor', obj.BG);
            place(strip, 1, [1 3]);
            names = {'cycle', 'Ciclo'; 'command', 'Comando'; 'confidence', 'Confianza'; ...
                'decision', 'Decidió'; 'latency', 'Latencia LLM'; 'duration', 'Duración del ciclo'};
            for k = 1:size(names, 1)
                obj.tiles.(names{k, 1}) = obj.make_tile(strip, k, names{k, 2}, strcmp(names{k, 1}, 'command'));
            end

            n = obj.HISTORY_S * obj.cfg.fs;                         % muestras visibles por canal
            t = (-(n - 1):0) / obj.cfg.fs;                          % eje de tiempo (s)
            obj.history = zeros(n, 8);                              % historial vacío
            obj.chan_lines = gobjects(1, 8);
            body = obj.make_card(g, [2 1 2], sprintf('Canales individuales · EMG crudo, últimos %d s', obj.HISTORY_S));
            cg = uigridlayout(body, [4 2], 'Padding', [0 0 0 0], 'RowSpacing', 2, 'ColumnSpacing', 10, ...
                'BackgroundColor', obj.WHITE);
            for k = 1:8                                             % un gráfico por canal
                ax = obj.make_axes(cg);
                obj.chan_lines(k) = plot(ax, t, zeros(1, n), 'Color', obj.NAVY, 'LineWidth', 0.8);
                set(ax, 'YLim', [-128 127], 'XLim', [t(1) 0], 'XTickLabel', {});
                text(ax, t(1), 120, sprintf(' CH%d', k), 'FontSize', 9, 'FontWeight', 'bold', ...
                    'Color', obj.RED, 'VerticalAlignment', 'top'); % nombre del canal
            end

            [kinds, titles] = image_kinds();                        % las 3 imágenes
            cells = [2 3; 3 1; 3 2];                                % posición de cada una
            for k = 1:numel(kinds)
                [body, actions] = obj.make_card(g, cells(k, :), titles{k});
                obj.img_badges.(kinds{k}) = uilabel(actions, 'Text', '', 'FontSize', 11, 'FontWeight', 'bold');
                kind = kinds{k};
                obj.button(actions, 'PNG', obj.NAVY, @(~, ~) obj.on_export(kind));
                bg = uigridlayout(body, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', obj.WHITE);
                obj.img_axes.(kind) = obj.make_axes(bg);
            end

            body = obj.make_card(g, [3 3], 'Comandos enviados');
            hg = uigridlayout(body, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', obj.WHITE);
            obj.hist_ax = obj.make_axes(hg);
            obj.hist_line = plot(obj.hist_ax, NaN, NaN, '-o', 'Color', obj.NAVY, 'LineWidth', 1.2, ...
                'MarkerSize', 4, 'MarkerFaceColor', obj.RED, 'MarkerEdgeColor', obj.RED);
            xlabel(obj.hist_ax, 'ciclo');
        end

        function update_badges(obj)
            % Indica en cada imagen del dashboard si se envía al LLM.
            kinds = image_kinds();
            for k = 1:numel(kinds)
                badge = obj.img_badges.(kinds{k});
                if obj.controls.(['image_send_' kinds{k}]).Value     % marcada en la vista Prompt
                    badge.Text = '● Se envía al LLM';
                    badge.FontColor = obj.NAVY;
                else
                    badge.Text = 'No se envía';
                    badge.FontColor = obj.MUTED;
                end
            end
        end

        %% Vista Prompt
        function build_prompt_view(obj, parent)
            % Imágenes que se envían, plantilla editable y prompt final.
            g = uigridlayout(parent, [2 1], 'RowHeight', {92, '1x'}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 12, 'BackgroundColor', obj.BG);

            body = obj.make_card(g, [1 1], 'Imágenes que se envían al LLM');
            cg = uigridlayout(body, [1 3], 'Padding', [0 0 0 0], 'ColumnSpacing', 16, 'BackgroundColor', obj.WHITE);
            [kinds, titles] = image_kinds();
            for k = 1:numel(kinds)
                path = ['image.send.' kinds{k}];                    % campo en cfg
                c = uicheckbox(cg, 'Text', titles{k}, 'Value', get_path(obj.cfg, path), ...
                    'FontColor', obj.NAVY, 'FontWeight', 'bold', 'ValueChangedFcn', @(~, ~) obj.on_images_changed());
                place(c, 1, k);
                obj.register({path, titles{k}, 'check', []}, c);
            end

            [body, actions] = obj.make_card(g, [2 1], 'System prompt');
            [~, name, ext] = fileparts(obj.cfg.llm.prompt_file);    % archivo configurado
            obj.prompt_file = uidropdown(actions, 'Items', {'system_es.txt', 'system_en.txt'}, ...
                'Value', [name ext], 'FontColor', obj.NAVY, 'ValueChangedFcn', @(~, ~) obj.load_prompt());
            obj.button(actions, 'Recargar', obj.NAVY, @(~, ~) obj.load_prompt());
            obj.button(actions, 'Guardar', obj.NAVY, @(~, ~) obj.save_prompt());
            obj.button(actions, 'Ver prompt final', obj.NAVY, @(~, ~) obj.preview_prompt());
            pg = uigridlayout(body, [2 2], 'RowHeight', {22, '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 12, 'BackgroundColor', obj.WHITE);
            place(uilabel(pg, 'Text', 'Plantilla editable · marcadores {{GESTOS}}, {{REPOSO}} e {{IMAGENES}}', ...
                'FontColor', obj.MUTED), 1, 1);
            place(uilabel(pg, 'Text', 'Prompt final que recibe el LLM', 'FontColor', obj.MUTED), 1, 2);
            obj.prompt_edit = uitextarea(pg, 'FontName', 'Consolas', 'FontSize', 12, 'FontColor', obj.NAVY);
            obj.prompt_final = uitextarea(pg, 'FontName', 'Consolas', 'FontSize', 12, 'Editable', 'off', ...
                'FontColor', obj.NAVY, 'BackgroundColor', [0.98 0.98 0.99]);
            place(obj.prompt_edit, 2, 1);
            place(obj.prompt_final, 2, 2);
        end

        function on_images_changed(obj)
            % Al marcar o desmarcar una imagen: actualiza el prompt final y el dashboard.
            obj.preview_prompt();
            obj.update_badges();
        end

        %% Piezas de diseño
        function b = button(obj, parent, text, color, callback)
            % Botón con fondo de color y letra blanca en negrita.
            b = uibutton(parent, 'Text', text, 'BackgroundColor', color, 'FontColor', obj.WHITE, ...
                'FontWeight', 'bold', 'ButtonPushedFcn', callback);
        end

        function [body, actions] = make_card(obj, parent, pos, title)
            % Tarjeta blanca en pos = [fila columna(s)], con título y zona de acciones a la derecha.
            panel = uipanel(parent, 'BorderType', 'none', 'BackgroundColor', obj.WHITE);
            place(panel, pos(1), pos(2:end));
            g = uigridlayout(panel, [2 2], 'RowHeight', {26, '1x'}, 'ColumnWidth', {'1x', 'fit'}, ...
                'Padding', [14 10 14 12], 'RowSpacing', 8, 'BackgroundColor', obj.WHITE);
            place(uilabel(g, 'Text', title, 'FontSize', 13, 'FontWeight', 'bold', 'FontColor', obj.NAVY), 1, 1);
            actions = uigridlayout(g, [1 4], 'ColumnWidth', {'fit', 'fit', 'fit', 'fit'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 8, 'BackgroundColor', obj.WHITE);
            place(actions, 1, 2);
            body = uipanel(g, 'BorderType', 'none', 'BackgroundColor', obj.WHITE);
            place(body, 2, [1 2]);
        end

        function value_label = make_tile(obj, parent, column, title, accent)
            % Indicador: título pequeño y valor grande; 'accent' añade una línea amarilla arriba.
            panel = uipanel(parent, 'BorderType', 'none', 'BackgroundColor', obj.WHITE);
            place(panel, 1, column);
            g = uigridlayout(panel, [3 1], 'RowHeight', {3, 16, '1x'}, 'Padding', [14 6 14 0], ...
                'RowSpacing', 4, 'BackgroundColor', obj.WHITE);
            if accent
                place(uipanel(g, 'BorderType', 'none', 'BackgroundColor', obj.YELLOW), 1, 1);
            end
            place(uilabel(g, 'Text', upper(title), 'FontSize', 10, 'FontWeight', 'bold', ...
                'FontColor', obj.MUTED), 2, 1);
            value_label = uilabel(g, 'Text', '–', 'FontSize', 22, 'FontWeight', 'bold', 'FontColor', obj.NAVY);
            place(value_label, 3, 1);
        end

        function ax = make_axes(obj, parent)
            % Ejes minimalistas: sin caja ni barra de herramientas, rejilla suave.
            ax = uiaxes(parent);
            ax.Toolbar.Visible = 'off';
            disableDefaultInteractivity(ax);
            ax.FontSize = 9;
            ax.XColor = obj.MUTED;
            ax.YColor = obj.MUTED;
            ax.GridColor = obj.NAVY;
            ax.GridAlpha = 0.08;
            ax.Box = 'off';
            grid(ax, 'on');
        end

        function show_view(obj, name)
            % Muestra 'dashboard' o 'prompt' y resalta su botón.
            obj.views.dashboard.Visible = strcmp(name, 'dashboard');
            obj.views.prompt.Visible = strcmp(name, 'prompt');
            obj.btn.tab_dashboard.BackgroundColor = ternary(strcmp(name, 'dashboard'), obj.NAVY, obj.SOFT);
            obj.btn.tab_prompt.BackgroundColor = ternary(strcmp(name, 'prompt'), obj.NAVY, obj.SOFT);
        end

        function update_mode(obj)
            % Muestra solo las filas que aplican: HTTP o serie, adaptador USB o Bluetooth del PC.
            serial = strcmpi(obj.controls.prosthesis_mode.Value, 'Serial');
            obj.mode_grids.http.Visible = ~serial;
            obj.mode_grids.serial.Visible = serial;
            dongle = strcmp(obj.controls.myo_link.Value, 'dongle');
            obj.mode_grids.dongle.Visible = dongle;
            obj.mode_grids.bluetooth.Visible = ~dongle;
        end

        function set_running(obj, running)
            % Iniciar activo solo cuando está detenido; Detener activo solo cuando está en marcha.
            obj.running = running;
            obj.btn.start.Enable = ~running;
            obj.btn.stop.Enable = running;
        end

        %% Configuración
        function cfg = read_controls(obj)
            % cfg = configuración base + valores de la interfaz.
            cfg = obj.cfg;
            for k = 1:size(obj.fields, 1)
                [path, ~, kind] = obj.fields{k, 1:3};
                value = obj.controls.(strrep(path, '.', '_')).Value; % valor en la UI
                if strcmp(kind, 'vector')
                    value = sscanf(value, '%f')';                   % '1234 1235' -> [1234 1235]
                elseif strcmp(kind, 'switch')
                    value = lower(value);                           % 'HTTP' -> 'http'
                end
                cfg = set_path(cfg, path, value);
            end
        end

        function on_save_config(obj)
            % Escribe los valores de la interfaz en config/agent_config.m (conserva los comentarios).
            cfg = obj.read_controls();
            file = which('agent_config');
            lines = splitlines(string(read_text(file)));            % una línea por elemento
            for k = 1:size(obj.fields, 1)
                path = obj.fields{k, 1};
                value = get_path(cfg, path);                        % valor nuevo
                if isequal(value, get_path(obj.cfg, path))          % no cambió
                    continue;
                end
                pattern = ['^(cfg\.' regexptranslate('escape', path) '\s*=\s*)[^;]*;'];
                code = value_to_code(value);                        % valor como código MATLAB
                lines = regexprep(lines, pattern, ['$1' regexprep(code, '([\\$])', '\\$1') ';'], 'once');
            end
            write_text(file, char(strjoin(lines, newline)));
            obj.cfg = cfg;                                          % nueva configuración base
            obj.note(sprintf('Configuración guardada en %s', file));
        end

        function pick_folder(obj, field)
            % Elige una carpeta con el explorador.
            folder = uigetdir(field.Value, 'Carpeta de muestras');
            figure(obj.fig);                                        % devuelve el foco a la UI
            if ischar(folder)
                field.Value = folder;
            end
        end

        %% Prompt
        function load_prompt(obj)
            % Carga en el editor el archivo de prompt elegido.
            file = fullfile(fileparts(which('agent_config')), obj.prompt_file.Value);
            obj.prompt_edit.Value = cellstr(splitlines(string(read_text(file))));
            obj.preview_prompt();
        end

        function save_prompt(obj)
            % Guarda la plantilla editada en su archivo.
            file = fullfile(fileparts(which('agent_config')), obj.prompt_file.Value);
            write_text(file, obj.template());
            obj.note(sprintf('Prompt guardado en %s', file));
        end

        function preview_prompt(obj)
            % Muestra el prompt final con gestos, reposo e imágenes insertados.
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
                return;
            end
            cfg = obj.read_controls();
            obj.preview_prompt();
            try
                session = agent_session(cfg, obj.template());       % registro, prompt y fuente
            catch err
                uialert(obj.fig, err.message, 'No se pudo iniciar', 'Icon', 'error');
                obj.note(['No se pudo iniciar: ' err.message]);
                return;
            end
            obj.reset_dashboard(cfg);
            obj.set_running(true);                                  % Iniciar apagado, Detener activo
            obj.note(sprintf('Myo conectado. Registro: %s', session.log_file));
            try
                while obj.running && session.stats.cycles < cfg.max_cycles
                    r = session.step();                             % un ciclo completo
                    if r.done
                        break;
                    end
                    obj.update_dashboard(r, cfg);
                    drawnow limitrate;                              % atiende botones y redibuja
                    pause(max(0, cfg.period_s - r.cycle_ms / 1000)); % completa el periodo
                end
                summary = session.finish();
                obj.note(sprintf('Terminado: %d ciclos, %d del LLM, %d de respaldo.', ...
                    summary.cycles, summary.llm_ok, summary.fallback));
            catch err
                log_msg('UI', 'Error en el ciclo:\n%s', getReport(err, 'extended', 'hyperlinks', 'off')); % dónde falló
                session.finish();                                   % deja la prótesis en reposo
                obj.note(['Error: ' err.message]);
                if ~obj.closing
                    uialert(obj.fig, err.message, 'Error durante la ejecución');
                end
            end
            obj.running = false;
            if obj.closing                                          % se pidió cerrar la ventana
                delete(obj.fig);
                return;
            end
            obj.set_running(false);                                 % Iniciar activo, Detener apagado
        end

        function on_stop(obj)
            % Detiene el bucle al terminar el ciclo actual.
            obj.running = false;
            obj.btn.stop.Enable = false;
            obj.note('Deteniendo al final del ciclo actual...');
        end

        function on_close(obj)
            % Cierra la ventana; si el agente corre, primero lo detiene.
            if obj.running
                obj.closing = true;                                 % on_start cerrará la ventana
                obj.running = false;
            else
                send_prosthesis_command('close');                   % libera el puerto serie, si se abrió
                delete(obj.fig);
            end
        end

        %% Actualización del dashboard
        function reset_dashboard(obj, cfg)
            % Vacía el historial al iniciar una sesión.
            obj.commands = {};
            obj.history(:) = 0;                                     % canales a cero
            obj.command_list = [{cfg.rest_command}, {cfg.gestures.command}]; % S, C, O
            obj.hist_ax.YTick = 1:numel(obj.command_list);
            obj.hist_ax.YTickLabel = obj.command_list;
            obj.hist_ax.YLim = [0.5, numel(obj.command_list) + 0.5];
            set(obj.hist_line, 'XData', NaN, 'YData', NaN);
        end

        function update_dashboard(obj, r, cfg)
            % Muestra los resultados de un ciclo.
            obj.history = [obj.history(size(r.emg, 1) + 1:end, :); r.emg]; % desplaza y añade la ventana
            for k = 1:8
                obj.chan_lines(k).YData = obj.history(:, k);        % canal k
            end
            kinds = image_kinds();
            for k = 1:numel(kinds)                                  % las 3 imágenes, siempre
                draw_emg_image(obj.img_axes.(kinds{k}), kinds{k}, r.vis, r.f, cfg);
            end

            obj.commands{end + 1} = r.sent.command;                 % historial de comandos
            y = cellfun(@(c) find(strcmp(obj.command_list, c), 1), obj.commands);
            x = 1:numel(y);
            keep = max(1, numel(y) - 59):numel(y);                  % últimos 60 ciclos
            set(obj.hist_line, 'XData', x(keep), 'YData', y(keep));
            obj.hist_ax.XLim = [x(keep(1)) - 0.5, x(keep(end)) + 0.5];

            obj.tiles.cycle.Text = sprintf('%d', r.cycle);
            obj.tiles.confidence.Text = sprintf('%.2f', r.decided.confidence);
            obj.tiles.duration.Text = sprintf('%.0f ms', r.cycle_ms);
            obj.tiles.decision.Text = upper(r.decided.source);
            obj.tiles.decision.FontColor = ternary(r.valid, obj.NAVY, obj.RED);
            obj.tiles.command.Text = r.sent.command;
            obj.tiles.command.FontColor = ternary(strcmp(r.sent.command, cfg.rest_command), obj.NAVY, obj.RED);
            obj.tiles.latency.Text = sprintf('%.0f ms', r.reply.latency_ms);
        end

        function on_export(obj, kind)
            % Guarda una imagen del dashboard como PNG en logs/.
            cfg = obj.read_controls();
            if ~isfolder(cfg.log_folder)
                mkdir(cfg.log_folder);
            end
            file = fullfile(cfg.log_folder, sprintf('%s_%s.png', kind, datestr(now, 'yyyymmdd_HHMMSS')));
            exportgraphics(obj.img_axes.(kind), file, 'Resolution', 150);
            obj.note(sprintf('Imagen guardada en %s', file));
        end

        %% Pruebas de conexión
        function on_test_myo(obj)
            % Conecta con el Myo, lee una ventana y muestra el resultado (o el motivo del fallo).
            if obj.running
                uialert(obj.fig, 'Detén el agente antes de probar el Myo.', 'Myo', 'Icon', 'warning');
                return;
            end
            cfg = obj.read_controls();
            progress = uiprogressdlg(obj.fig, 'Title', 'Myo', 'Indeterminate', 'on', ...
                'Message', 'Conectando con el Myo...');
            try
                device = myo_interface(cfg);                        % conecta y espera el primer EMG
                [emg, info] = device.read_window(round(cfg.window_ms / 1000 * cfg.fs)); % una ventana
                device.close();
                close(progress);
                level = sqrt(mean((emg - mean(emg, 1)) .^ 2, 1));   % RMS crudo por canal
                uialert(obj.fig, sprintf('Recibiendo EMG de %s.\nRMS crudo CH1..CH8: %s', info, ...
                    sprintf('%.1f  ', level)), 'Myo conectado', 'Icon', 'success');
            catch err
                close(progress);
                uialert(obj.fig, err.message, 'No se puede leer el Myo', 'Icon', 'error');
            end
        end

        function [models, report] = fetch_models(obj)
            % GET /v1/models en cada puerto del servidor LLM: modelos disponibles y un informe.
            cfg = obj.read_controls();
            options = weboptions('Timeout', 5, 'HeaderFields', {'Authorization', ['Bearer ' cfg.llm.api_key]});
            models = {};
            report = {};
            for port = cfg.llm.ports
                url = sprintf('http://%s:%d/v1/models', cfg.llm.ip, port);
                try
                    reply = webread(url, options);                  % lista de modelos
                    data = reply.data;
                    if iscell(data)
                        data = [data{:}];                           % celda -> array de structs
                    end
                    ids = cellfun(@char, {data.id}, 'UniformOutput', false); % nombres de los modelos
                    models = [models, ids]; %#ok<AGROW>
                    report{end + 1} = sprintf('%s: OK (%d modelos)', url, numel(ids)); %#ok<AGROW>
                catch err
                    report{end + 1} = sprintf('%s: %s', url, err.message); %#ok<AGROW>
                end
            end
            models = unique(models, 'stable');                      % sin repetidos
            log_msg('UI', 'Modelos del servidor LLM: %s | %s', strjoin(models, ', '), strjoin(report, ' | '));
        end

        function on_load_models(obj, field)
            % Botón Cargar: rellena la lista de Modelo con los modelos que tiene el servidor.
            [models, report] = obj.fetch_models();
            if isempty(models)
                uialert(obj.fig, strjoin(report, newline), 'No se pudieron cargar los modelos', 'Icon', 'error');
                return;
            end
            current = field.Value;
            field.Items = models;                                   % opciones = modelos del servidor
            if any(strcmp(models, current))
                field.Value = current;                              % conserva el elegido si existe
            else
                field.Value = models{1};                            % si no, el primero de la lista
            end
            obj.note(sprintf('%d modelos cargados del servidor LLM. Seleccionado: %s', numel(models), field.Value));
        end

        function on_test_llm(obj)
            % Comprueba el servidor LLM y muestra sus modelos.
            [models, report] = obj.fetch_models();
            message = strjoin(report, newline);
            if ~isempty(models)
                message = sprintf('%s\n\nModelos: %s', message, strjoin(models, ', '));
            end
            uialert(obj.fig, message, 'Servidor LLM', 'Icon', ternary(isempty(models), 'error', 'info'));
        end

        function on_test_prosthesis(obj)
            % Envía el comando de reposo por HTTP o por puerto serie, según el interruptor.
            cfg = obj.read_controls();
            ok = send_prosthesis_command(cfg.prosthesis, cfg.rest_command);
            if strcmp(cfg.prosthesis.mode, 'serial')
                target = sprintf('%s a %d baudios', cfg.prosthesis.serial_port, cfg.prosthesis.baud_rate);
            else
                target = sprintf('http://%s:%d%s', cfg.prosthesis.host, cfg.prosthesis.port, cfg.prosthesis.endpoint);
            end
            message = sprintf('%s -> %s: %s (detalle en la consola)', cfg.rest_command, target, ...
                ternary(ok, 'enviado', 'fallo'));
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
function place(component, row, column)
% Coloca un componente en una celda (o rango de celdas) de su cuadrícula.
component.Layout.Row = row;
component.Layout.Column = column;
end

function ports = serial_ports(current, with_auto)
% Puertos serie del equipo más el configurado; con with_auto, 'auto' va primero.
try
    ports = cellstr(serialportlist("all"));                 % COM1, COM3, ...
catch
    ports = {};                                             % sin soporte de puertos serie
end
if with_auto
    ports = [{'auto'}, ports];                              % búsqueda automática del adaptador
end
ports = unique([ports, {char(current)}], 'stable');         % incluye el valor actual
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
    code = ['''' strrep(value, '''', '''''') ''''];
elseif islogical(value)
    code = ternary(value, 'true', 'false');
elseif isscalar(value)
    code = num2str(value, 10);
else
    code = mat2str(value);
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
