classdef myo_interface < handle
    % MYO_INTERFACE Entrega ventanas de EMG (N x 8) del Myo Armband, por su adaptador USB
    %   (BLED112) o por el Bluetooth del PC. Si el Myo falla, lanza un error que explica el motivo.

    properties (Constant)
        UUID_TAIL = uint8([6 66 72 18 74 127 44 72 71 185 222 4 169 1 0 6 213]) % fin del anuncio del Myo
        EMG_HANDLES = [43 46 49 52]                                 % 0x2B 0x2E 0x31 0x34: datos de EMG
        EMG_CCCD = [44 47 50 53]                                    % 0x2C 0x2F 0x32 0x35: activar sus avisos
        COMMAND_HANDLE = 25                                         % 0x19: comandos del Myo
        CONTROL_SERVICE = 'D5060001-A904-DEB9-4748-2C7F4A124842'   % (Bluetooth del PC) servicio de control
        COMMAND_CHAR = 'D5060401-A904-DEB9-4748-2C7F4A124842'      % (Bluetooth del PC) comandos
        EMG_SERVICE = 'D5060005-A904-DEB9-4748-2C7F4A124842'       % (Bluetooth del PC) servicio de EMG
        EMG_CHARS = {'D5060105-A904-DEB9-4748-2C7F4A124842', 'D5060205-A904-DEB9-4748-2C7F4A124842', ...
            'D5060305-A904-DEB9-4748-2C7F4A124842', 'D5060405-A904-DEB9-4748-2C7F4A124842'}
    end

    properties
        cfg                 % configuración completa (agent_config.m)
        source = 'myo'      % origen de los datos (siempre el brazalete)
        buffer = []         % muestras del Myo aún no leídas (M x 8)
        last_data = []      % tic de la última muestra recibida del Myo
        port = []           % puerto serie del adaptador USB (BLED112)
        rx = uint8([])      % bytes recibidos del adaptador y aún sin procesar
        pending = {}        % mensajes del adaptador ya leídos (que no son EMG) y aún sin usar
        conn = []           % número de conexión con el Myo en el adaptador
        device = []         % objeto ble (Bluetooth del PC)
        command_char = []   % característica de comandos (Bluetooth del PC)
        emg_chars = {}      % características de EMG suscritas (Bluetooth del PC)
    end

    methods
        function obj = myo_interface(cfg)
            % Abre la fuente elegida. Con el Myo, si algo falla se cierra todo y se lanza el error.
            obj.cfg = cfg;
            try
                if strcmp(cfg.myo.link, 'dongle')
                    obj.connect_dongle();                           % adaptador USB del Myo
                else
                    obj.connect_ble();                              % Bluetooth del PC
                end
                obj.wait_first_data();                              % exige que llegue EMG
            catch err
                obj.close();                                        % libera lo que se abrió
                log_msg('MYO', 'No se pudo usar el Myo: %s', err.message);
                error('myo:connect', '%s', err.message);            % el error llega a la UI y a la consola
            end
        end

        function [emg, info] = read_window(obj, n)
            % Devuelve las últimas n muestras x 8 canales del Myo y un texto con su origen.
            [emg, info] = obj.read_myo(n);
        end

        function close(obj)
            % Apaga el EMG del Myo y libera el adaptador o el Bluetooth.
            try
                if ~isempty(obj.conn)                               % conectado por el adaptador
                    obj.write_attr(obj.COMMAND_HANDLE, [1 3 0 0 0]);  % apaga el EMG
                    obj.command(3, 0, obj.conn);                    % desconecta
                end
                if ~isempty(obj.command_char)                       % conectado por Bluetooth del PC
                    write(obj.command_char, [1, 3, 0, 0, 0]);
                end
            catch
            end
            obj.conn = [];
            obj.port = [];                                          % cierra el puerto serie
            obj.emg_chars = {};
            obj.command_char = [];
            obj.device = [];                                        % cierra la conexión BLE
        end
    end

    methods (Access = private)
        %% Adaptador USB del Myo (BLED112, protocolo BGAPI)
        function connect_dongle(obj)
            % Abre el adaptador, busca el Myo, se conecta y activa el EMG.
            name = obj.cfg.myo.dongle_port;                         % 'auto' o un puerto, p. ej. 'COM4'
            if strcmpi(name, 'auto')
                obj.find_dongle();                                  % prueba los puertos libres uno a uno
            else
                log_msg('MYO', 'Abriendo el adaptador USB del Myo en %s...', name);
                try
                    obj.port = serialport(name, 9600, 'Timeout', 1); % el adaptador es un puerto serie
                catch err
                    error(['No se pudo abrir %s (%s). Si es el adaptador del Myo, Myo Connect lo está ' ...
                        'usando: ciérralo por completo (icono de la bandeja > Quit). Si no, elige otro ' ...
                        'puerto o "auto" en Puerto USB.'], name, err.message);
                end
                if ~obj.is_dongle()
                    error(['%s no responde como el adaptador del Myo. Elige "auto" en Puerto USB para ' ...
                        'que se busque solo, o comprueba que el adaptador está enchufado.'], name);
                end
            end
            flush(obj.port);                                        % descarta datos viejos

            obj.command(6, 4, []);                                  % detiene cualquier búsqueda anterior
            for h = 0:2
                obj.command(3, 0, h);                               % cierra conexiones anteriores
            end

            log_msg('MYO', 'Buscando el Myo (hasta %g s)...', obj.cfg.myo.scan_timeout);
            obj.command(6, 2, 1);                                   % empieza a buscar dispositivos
            address = [];
            timer = tic;
            while isempty(address) && toc(timer) < obj.cfg.myo.scan_timeout
                p = obj.next_packet(0.5);                           % siguiente mensaje del adaptador
                if ~isempty(p) && p.type == 128 && p.cls == 6 && p.cmd == 0 && ...
                        numel(p.payload) >= 17 && isequal(p.payload(end - 16:end), obj.UUID_TAIL)
                    address = p.payload(3:8);                       % dirección del Myo encontrado
                end
            end
            obj.command(6, 4, []);                                  % termina la búsqueda
            if isempty(address)
                error(['El adaptador no encontró ningún Myo en %g s. Comprueba que el Myo está ' ...
                    'encendido (se enciende al conectarlo al cable de carga) y, ya encendido, ' ...
                    'desconéctalo de ese cable: mientras carga puede no transmitir. Muévelo para ' ...
                    'despertarlo, acércalo al adaptador y asegúrate de que Myo Connect está cerrado ' ...
                    '(si sigue conectado al brazalete, el Myo no se anuncia).'], obj.cfg.myo.scan_timeout);
            end
            log_msg('MYO', 'Myo encontrado: %s', strjoin(cellstr(dec2hex(fliplr(address))), ':'));

            interval = typecast(uint16([6 6 64 0]), 'uint8');       % intervalo 7,5 ms, timeout 640 ms
            reply = obj.command(6, 3, [address 0 interval]);        % conecta
            if isempty(reply)
                error('El adaptador USB no respondió al pedir la conexión. Desconéctalo, vuelve a enchufarlo e inténtalo de nuevo.');
            end
            obj.conn = reply.payload(end);                          % número de la conexión
            if isempty(obj.wait_event(3, 0, 5))                     % espera la confirmación
                error('El Myo no aceptó la conexión. Apágalo y enciéndelo (conéctalo al cargador un momento).');
            end
            obj.write_attr(obj.COMMAND_HANDLE, [9 1 1]);            % el Myo no se duerme
            obj.write_attr(obj.COMMAND_HANDLE, [10 1 2]);           % el Myo queda desbloqueado
            for h = obj.EMG_CCCD
                obj.write_attr(h, [1 0]);                           % activa los avisos de EMG
            end
            obj.write_attr(obj.COMMAND_HANDLE, [1 3 obj.cfg.myo.emg_mode 0 0]); % EMG sí, IMU y gestos no
            log_msg('MYO', 'Conectado por el adaptador USB (conexión %d, modo EMG %d)', ...
                obj.conn, obj.cfg.myo.emg_mode);
        end

        function find_dongle(obj)
            % Busca el adaptador entre los puertos serie libres: es el que responde al saludo BGAPI.
            stale = serialportfind();                               % puertos que MATLAB dejó abiertos
            if ~isempty(stale)
                log_msg('MYO', 'Cerrando puertos que MATLAB tenía abiertos: %s', strjoin(cellstr([stale.Port]), ' '));
                delete(stale);                                      % los libera (p. ej. de una prueba anterior)
            end
            free = cellstr(serialportlist("available"));            % puertos que nadie usa
            busy = setdiff(cellstr(serialportlist("all")), free);   % puertos abiertos por otro programa
            log_msg('MYO', 'Buscando el adaptador USB en los puertos libres: %s', strjoin(free, ' '));
            for k = 1:numel(free)
                try
                    obj.port = serialport(free{k}, 9600, 'Timeout', 1); % abre el puerto
                    if obj.is_dongle()                              % respondió como el adaptador
                        log_msg('MYO', 'Adaptador USB del Myo encontrado en %s', free{k});
                        obj.cfg.myo.dongle_port = free{k};          % para mostrarlo en la consola y la UI
                        return;
                    end
                catch
                end
                obj.port = [];                                      % no era: lo cierra
            end
            if isempty(busy)
                error(['No se encontró el adaptador USB del Myo. Comprueba que está enchufado (es el ' ...
                    'segundo cable / la llave USB azul, no el cable de carga) y pulsa ↻.']);
            end
            error(['No se encontró el adaptador USB del Myo entre los puertos libres. Hay puertos ' ...
                'ocupados por otro programa (%s): seguramente Myo Connect. Cerrar la ventana de Myo ' ...
                'Connect no basta: ciérralo desde el icono de la bandeja (junto al reloj) > Quit, o ' ...
                'en el Administrador de tareas finaliza "Myo Connect". Después pulsa Probar Myo.'], ...
                strjoin(busy, ', '));
        end

        function ok = is_dongle(obj)
            % Envía el saludo BGAPI (system_hello) y comprueba que llega su respuesta.
            flush(obj.port);
            reply = obj.command(0, 1, [], 0.5);                     % hello: clase 0, comando 1
            ok = ~isempty(reply);
        end

        function reply = command(obj, cls, cmd, payload, timeout)
            % Envía un comando BGAPI y espera su respuesta (los datos que lleguen mientras se guardan).
            if nargin < 5
                timeout = 2;                                        % espera máxima de la respuesta (s)
            end
            write(obj.port, uint8([0 numel(payload) cls cmd payload]), 'uint8');
            reply = [];
            timer = tic;
            while toc(timer) < timeout
                p = obj.next_packet(0.2);
                if ~isempty(p) && p.type == 0 && p.cls == cls && p.cmd == cmd
                    reply = p;                                      % respuesta a este comando
                    return;
                end
            end
        end

        function write_attr(obj, handle, data)
            % Escribe un atributo del Myo y espera a que el adaptador confirme.
            obj.command(4, 5, [obj.conn typecast(uint16(handle), 'uint8') numel(data) data]);
            obj.wait_event(4, 1, 2);                                % "procedimiento completado"
        end

        function p = wait_event(obj, cls, cmd, timeout)
            % Espera un evento concreto del adaptador ([] si no llega a tiempo).
            timer = tic;
            while toc(timer) < timeout
                p = obj.next_packet(0.2);
                if ~isempty(p) && p.type == 128 && p.cls == cls && p.cmd == cmd
                    return;
                end
            end
            p = [];
        end

        function p = next_packet(obj, timeout)
            % Siguiente mensaje del adaptador que no sea EMG ([] si no llega a tiempo).
            timer = tic;
            while isempty(obj.pending)
                obj.drain();                                        % lee y procesa lo recibido
                if ~isempty(obj.pending) || toc(timer) >= timeout
                    break;
                end
                pause(0.002);
            end
            p = [];
            if ~isempty(obj.pending)
                p = obj.pending{1};                                 % el más antiguo
                obj.pending(1) = [];
            end
        end

        function drain(obj)
            % Lee todo lo recibido del adaptador: el EMG va al buffer y el resto a 'pending'.
            if obj.port.NumBytesAvailable > 0
                obj.rx = [obj.rx, uint8(read(obj.port, obj.port.NumBytesAvailable, 'uint8'))];
            end
            rx = obj.rx;                                            % copia local (más rápido)
            emg = zeros(ceil(numel(rx) / 25) * 2 + 2, 8);           % sitio de sobra para las muestras
            count = 0;                                              % muestras de EMG encontradas
            i = 1;                                                  % posición de lectura
            while i < numel(rx)
                if ~any(rx(i) == [0 128 8 136])                     % no es el inicio de un mensaje
                    i = i + 1;
                    continue;
                end
                total = 4 + double(bitand(rx(i), 7)) * 256 + double(rx(i + 1)); % largo del mensaje
                if i + total - 1 > numel(rx)
                    break;                                          % mensaje incompleto: esperar más bytes
                end
                p = struct('type', double(rx(i)), 'cls', double(rx(i + 2)), 'cmd', double(rx(i + 3)), ...
                    'payload', rx(i + 4:i + total - 1));
                i = i + total;
                handle = 0;
                if p.type == 128 && p.cls == 4 && p.cmd == 5 && numel(p.payload) >= 21
                    handle = double(p.payload(2)) + 256 * double(p.payload(3)); % atributo del dato
                end
                if any(handle == obj.EMG_HANDLES)                   % datos de EMG: 2 muestras x 8 canales
                    emg(count + (1:2), :) = reshape(double(typecast(p.payload(6:21), 'int8')), 8, 2).';
                    count = count + 2;
                else
                    obj.pending{end + 1} = p;                       % respuesta o evento para quien lo espere
                end
            end
            obj.rx = rx(i:end);                                     % guarda lo que falta por completar
            if count > 0
                obj.push(emg(1:count, :));                          % todas las muestras de una vez
            end
        end

        %% Bluetooth del PC (función ble de MATLAB)
        function connect_ble(obj)
            % Conecta por el Bluetooth del PC y activa el EMG.
            name = obj.cfg.myo.device_name;
            log_msg('MYO', 'Conectando por el Bluetooth del PC con "%s"...', name);
            try
                obj.device = ble(name);                             % abre la conexión BLE
            catch err
                if contains(err.message, 'radio', 'IgnoreCase', true)
                    error(['MATLAB no encuentra el Bluetooth del PC (está apagado o el equipo no lo tiene). ' ...
                        'Myo Connect usa su propio adaptador USB, que MATLAB no ve como Bluetooth. ' ...
                        'Elige "Adaptador USB" en Conexión Myo, cierra Myo Connect y vuelve a intentarlo.']);
                end
                error(['No se encontró "%s" por Bluetooth (%s). El nombre debe ser el que muestra Myo ' ...
                    'Connect (p. ej. MYO.94) y Myo Connect debe estar cerrado.'], name, err.message);
            end
            obj.command_char = characteristic(obj.device, obj.CONTROL_SERVICE, obj.COMMAND_CHAR);
            for k = 1:numel(obj.EMG_CHARS)                          % cada característica de EMG
                c = characteristic(obj.device, obj.EMG_SERVICE, obj.EMG_CHARS{k});
                c.DataAvailableFcn = @(src, ~) obj.on_ble_data(src);
                subscribe(c, 'notification');
                obj.emg_chars{k} = c;
            end
            write(obj.command_char, [9, 1, 1]);                     % no se duerme
            write(obj.command_char, [10, 1, 2]);                    % desbloqueado
            write(obj.command_char, [1, 3, obj.cfg.myo.emg_mode, 0, 0]); % activa el EMG
            log_msg('MYO', 'Conectado por el Bluetooth del PC (modo EMG %d)', obj.cfg.myo.emg_mode);
        end

        function on_ble_data(obj, src)
            % Callback BLE: 16 bytes = 2 muestras x 8 canales (int8).
            bytes = uint8(read(src, 'oldest'));
            obj.push(reshape(double(typecast(bytes(:)', 'int8')), 8, []).');
        end

        %% Datos del Myo
        function push(obj, samples)
            % Añade muestras al buffer (como máximo 5 s).
            obj.buffer = [obj.buffer; samples];
            obj.buffer = obj.buffer(max(1, end - 5 * obj.cfg.fs + 1):end, :);
            obj.last_data = tic;
        end

        function poll(obj)
            % Procesa lo que haya enviado el Myo.
            if isempty(obj.port)
                pause(0.005);                                       % Bluetooth del PC: corren los callbacks
                return;
            end
            obj.drain();                                            % adaptador: lee todo lo recibido
            obj.pending = {};                                       % durante la sesión solo interesa el EMG
            pause(0.002);
        end

        function wait_first_data(obj)
            % Exige que llegue EMG poco después de conectar.
            obj.last_data = tic;
            timer = tic;
            while isempty(obj.buffer) && toc(timer) < obj.cfg.myo.connect_timeout
                obj.poll();
            end
            if isempty(obj.buffer)
                error(['El Myo se conectó pero no envía EMG en %g s. Comprueba que está en el brazo, ' ...
                    'con el logo hacia arriba, y que tiene batería.'], obj.cfg.myo.connect_timeout);
            end
            log_msg('MYO', 'Recibiendo EMG del Myo');
        end

        function [emg, info] = read_myo(obj, n)
            % Espera n muestras nuevas y devuelve las últimas n.
            obj.poll();                                             % primero, lo que llegó durante el ciclo
            while size(obj.buffer, 1) < n
                if toc(obj.last_data) > obj.cfg.myo.dropout_timeout
                    error('myo:dropout', ['El Myo dejó de enviar EMG hace %.1f s (¿se alejó, se durmió ' ...
                        'o se quedó sin batería?).'], toc(obj.last_data));
                end
                obj.poll();
            end
            emg = obj.buffer(end - n + 1:end, :);                   % las n más recientes
            obj.buffer = [];
            if isempty(obj.port)
                info = sprintf('Myo "%s" (Bluetooth del PC)', obj.cfg.myo.device_name);
            else
                info = sprintf('Myo (adaptador USB %s)', obj.cfg.myo.dongle_port); % puerto real (también con 'auto')
            end
        end
    end
end
