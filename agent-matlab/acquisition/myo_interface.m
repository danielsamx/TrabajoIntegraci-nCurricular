classdef myo_interface < handle
    % MYO_INTERFACE Entrega ventanas de EMG (N x 8) del Myo por Bluetooth.
    %   Si el Myo no conecta, no envía datos o se corta, usa samples/muestra_1..N.csv.

    properties (Constant)
        CONTROL_SERVICE = 'D5060001-A904-DEB9-4748-2C7F4A124842'   % servicio de control del Myo
        COMMAND_CHAR = 'D5060401-A904-DEB9-4748-2C7F4A124842'      % característica de comandos
        EMG_SERVICE = 'D5060005-A904-DEB9-4748-2C7F4A124842'       % servicio de EMG
        EMG_CHARS = {'D5060105-A904-DEB9-4748-2C7F4A124842', ...   % las 4 características de EMG
            'D5060205-A904-DEB9-4748-2C7F4A124842', ...
            'D5060305-A904-DEB9-4748-2C7F4A124842', ...
            'D5060405-A904-DEB9-4748-2C7F4A124842'}
    end

    properties
        cfg                 % configuración completa (agent_config.m)
        source              % fuente activa: 'myo' o 'samples'
        buffer = []         % muestras recibidas del Myo y aún no leídas (M x 8)
        last_data = []      % tic de la última muestra recibida del Myo
        device = []         % objeto ble del brazalete
        command_char = []   % característica para enviar comandos al Myo
        emg_chars = {}      % características suscritas de EMG
        file_index = 0      % número del archivo de muestras actual
        file_data = []      % contenido del archivo actual (filas x 8)
        file_row = 1        % siguiente fila del archivo por leer
    end

    methods
        function obj = myo_interface(cfg)
            % Abre la fuente configurada; si el Myo falla, pasa a las muestras.
            obj.cfg = cfg;                                          % guarda la configuración
            obj.source = cfg.source;                                % fuente pedida
            if strcmp(obj.source, 'myo')                            % se pidió el brazalete
                try
                    obj.connect_myo();                              % intenta conectar
                    return;                                         % conectado: listo
                catch err
                    log_msg('MYO', 'El Myo no está activo: %s', err.message); % motivo del fallo
                    obj.close();                                    % libera lo que se haya abierto
                end
            end
            obj.start_samples();                                    % usa las muestras grabadas
        end

        function [emg, info] = read_window(obj, n)
            % Devuelve n muestras x 8 canales y un texto con su origen; [] si no hay más.
            if strcmp(obj.source, 'myo')                            % leyendo del brazalete
                [emg, info] = obj.read_myo(n);                      % última ventana del Myo
                if ~isempty(emg)                                    % llegaron datos
                    return;                                         % se entrega la ventana
                end
                obj.close();                                        % el Myo dejó de enviar
                obj.start_samples();                                % se continúa con las muestras
            end
            [emg, info] = obj.read_samples(n);                      % siguiente ventana grabada
        end

        function close(obj)
            % Detiene el EMG del Myo y libera el Bluetooth.
            try
                write(obj.command_char, [1, 3, 0, 0, 0]);           % apaga el streaming de EMG
            catch
            end
            obj.emg_chars = {};                                     % suelta las suscripciones
            obj.command_char = [];                                  % suelta la característica
            obj.device = [];                                        % cierra la conexión BLE
        end
    end

    methods (Access = private)
        function connect_myo(obj)
            % Conecta por Bluetooth, activa el EMG y exige que lleguen datos.
            log_msg('MYO', 'Conectando con "%s"...', obj.cfg.myo.device_name);
            obj.device = ble(obj.cfg.myo.device_name);              % abre la conexión BLE
            obj.command_char = characteristic(obj.device, ...       % característica de comandos
                obj.CONTROL_SERVICE, obj.COMMAND_CHAR);
            for k = 1:numel(obj.EMG_CHARS)                          % cada característica de EMG
                c = characteristic(obj.device, obj.EMG_SERVICE, obj.EMG_CHARS{k});
                c.DataAvailableFcn = @(src, ~) obj.on_data(src);    % función que recibe los datos
                subscribe(c, 'notification');                       % activa las notificaciones
                obj.emg_chars{k} = c;                               % la guarda
            end
            write(obj.command_char, [9, 1, 1]);                     % el Myo no se duerme
            write(obj.command_char, [10, 1, 2]);                    % el Myo queda desbloqueado
            write(obj.command_char, [1, 3, obj.cfg.myo.emg_mode, 0, 0]); % activa el EMG

            timer = tic;                                            % espera el primer dato
            while isempty(obj.buffer) && toc(timer) < obj.cfg.myo.connect_timeout
                pause(0.05);                                        % deja correr los callbacks
            end
            if isempty(obj.buffer)                                  % conectó pero no envía
                error('conectado pero sin EMG en %g s', obj.cfg.myo.connect_timeout);
            end
            obj.source = 'myo';                                     % fuente activa: brazalete
            log_msg('MYO', 'Myo conectado y enviando EMG (modo %d)', obj.cfg.myo.emg_mode);
        end

        function on_data(obj, src)
            % Callback BLE: cada paquete trae 16 bytes = 2 muestras x 8 canales (int8).
            bytes = uint8(read(src, 'oldest'));                     % bytes recibidos
            values = double(typecast(bytes(:)', 'int8'));           % bytes -> enteros con signo
            obj.buffer = [obj.buffer; reshape(values, 8, []).'];    % añade las muestras al buffer
            obj.buffer = obj.buffer(max(1, end - 5 * obj.cfg.fs + 1):end, :); % guarda como máximo 5 s
            obj.last_data = tic;                                    % hora del último dato
        end

        function [emg, info] = read_myo(obj, n)
            % Espera a tener n muestras nuevas y devuelve las últimas n.
            emg = [];                                               % vacío si el Myo se corta
            info = '';
            while size(obj.buffer, 1) < n                           % aún faltan muestras
                if toc(obj.last_data) > obj.cfg.myo.dropout_timeout % demasiado tiempo sin datos
                    log_msg('MYO', 'Sin EMG desde hace %.1f s', toc(obj.last_data));
                    return;                                         % se avisa con emg vacío
                end
                pause(0.005);                                       % deja correr los callbacks
            end
            emg = obj.buffer(end - n + 1:end, :);                   % las n muestras más recientes
            obj.buffer = [];                                        % vacía el buffer
            info = sprintf('Myo "%s" (BLE)', obj.cfg.myo.device_name); % origen de la ventana
        end

        function start_samples(obj)
            % Empieza a reproducir los archivos de muestras desde el primero.
            obj.source = 'samples';                                 % fuente activa: muestras
            obj.file_index = 0;                                     % ningún archivo cargado aún
            log_msg('MUESTRA', 'Fuente: %d archivos en %s', obj.cfg.samples.count, ...
                obj.cfg.samples.folder);
            obj.load_next_file();                                   % carga muestra_1.csv
        end

        function load_next_file(obj)
            % Carga el siguiente archivo muestra_k.csv (o termina si no quedan).
            obj.file_index = obj.file_index + 1;                    % siguiente número de archivo
            if obj.file_index > obj.cfg.samples.count               % ya se leyeron todos
                if ~obj.cfg.samples.loop                            % sin repetición
                    obj.file_data = [];                             % marca el final
                    return;
                end
                obj.file_index = 1;                                 % vuelve al primero
            end
            name = sprintf('muestra_%d.csv', obj.file_index);       % nombre del archivo
            data = readmatrix(fullfile(obj.cfg.samples.folder, name)); % lee la tabla (sin cabecera)
            data = data(all(isfinite(data), 2), 1:8);               % quita filas vacías, 8 canales
            obj.file_data = data;                                   % guarda el contenido
            obj.file_row = 1;                                       % empieza por la primera fila
            log_msg('MUESTRA', '%s cargado: %d filas x 8 canales (CH0..CH7 = CH1..CH8)', ...
                name, size(data, 1));
        end

        function [emg, info] = read_samples(obj, n)
            % Devuelve las siguientes n filas del archivo actual.
            emg = [];                                               % vacío si no quedan muestras
            info = '';
            while ~isempty(obj.file_data)                           % mientras haya archivo
                last = obj.file_row + n - 1;                        % última fila de la ventana
                if last <= size(obj.file_data, 1)                   % caben n filas
                    emg = obj.file_data(obj.file_row:last, :);      % extrae la ventana
                    info = sprintf('muestra_%d.csv, filas %d-%d de %d', obj.file_index, ...
                        obj.file_row, last, size(obj.file_data, 1));
                    obj.file_row = last + 1;                        % avanza para la siguiente
                    return;
                end
                left = size(obj.file_data, 1) - obj.file_row + 1;   % filas sobrantes (< n)
                log_msg('MUESTRA', 'muestra_%d.csv terminado (%d filas sobrantes, menos de %d)', ...
                    obj.file_index, left, n);
                obj.load_next_file();                               % pasa al siguiente archivo
            end
            log_msg('MUESTRA', 'No quedan muestras por procesar');
        end
    end
end
