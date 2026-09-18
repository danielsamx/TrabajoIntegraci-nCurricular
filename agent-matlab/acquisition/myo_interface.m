classdef myo_interface < handle
    % MYO_INTERFACE Interfaz con el Myo Armband (BLE nativo / UDP / simulado) con buffer
    %   circular de 8 canales a 200 Hz.
    %
    % MYO_INTERFACE Interface to the Myo Armband (native BLE / UDP / simulated) with an
    %   8-channel circular buffer at 200 Hz.
    %
    % Fuentes / Sources:
    %   'myo'       : Bluetooth Low Energy con la función ble() de MATLAB base, usando el
    %                 protocolo abierto del Myo (myohw.h). Sin Myo Connect ni MEX.
    %                 Bluetooth Low Energy with base MATLAB ble(), using the open Myo
    %                 protocol (myohw.h). No Myo Connect, no MEX.
    %   'udp'       : paquetes binarios de 16 bytes (2 muestras x 8 canales int8) recibidos
    %                 con udpport() / 16-byte binary packets (2 samples x 8 int8 channels)
    %                 received with udpport()
    %   'simulated' : generador sintético con los patrones del mapa anatómico de referencia
    %                 synthetic generator with the reference anatomical map patterns
    %
    % Uso / Usage:
    %   myo = myo_interface.instance('source', 'myo', 'device_name', "Myo");
    %   [emg, fresh] = myo.read_window(40);
    %   myo_interface.instance('reset');
    %
    % DECISIÓN: buffer circular alimentado por callbacks | RAZÓN: evita perder muestras
    %   entre ciclos (el LLM tarda cientos de ms) | ALTERNATIVA DESCARTADA: leer
    %   directamente del Myo en cada ciclo (bloqueante y con pérdidas)
    % DECISION: circular buffer fed by callbacks | REASON: avoids losing samples between
    %   cycles (the LLM takes hundreds of ms) | DISCARDED ALTERNATIVE: reading the Myo
    %   directly every cycle (blocking and lossy)
    %
    % DECISIÓN: ble() de MATLAB base con el protocolo GATT del Myo | RAZÓN: 100 % MATLAB,
    %   sin MEX/C++ ni SDK descontinuado | ALTERNATIVA DESCARTADA: MyoMex (C++, no permitido)
    % DECISION: base MATLAB ble() with the Myo GATT protocol | REASON: 100 % MATLAB, no
    %   MEX/C++ nor discontinued SDK | DISCARDED ALTERNATIVE: MyoMex (C++, not allowed)
    %
    % DECISIÓN: singleton (instance) | RAZÓN: solo puede haber una conexión BLE al brazalete
    %   y get_signals debe poder usarla sin pasar el objeto | ALTERNATIVA DESCARTADA:
    %   variable global
    % DECISION: singleton (instance) | REASON: only one BLE connection to the armband can
    %   exist and get_signals must reach it without passing the object |
    %   DISCARDED ALTERNATIVE: global variable

    properties (Constant)
        FS = 200                          % Hz (EMG del Myo / Myo EMG)
        N_CHANNELS = 8
        CONTROL_SERVICE = 'D5060001-A904-DEB9-4748-2C7F4A124842'
        COMMAND_CHAR = 'D5060401-A904-DEB9-4748-2C7F4A124842'
        EMG_SERVICE = 'D5060005-A904-DEB9-4748-2C7F4A124842'
        EMG_CHARS = {'D5060105-A904-DEB9-4748-2C7F4A124842', ...
            'D5060205-A904-DEB9-4748-2C7F4A124842', ...
            'D5060305-A904-DEB9-4748-2C7F4A124842', ...
            'D5060405-A904-DEB9-4748-2C7F4A124842'}
        REST_AMPLITUDE = 2                % unidades int8 / int8 units
        MVC_AMPLITUDE = 40                % unidades int8 / int8 units
        SIM_SCHEDULE = {'REST', 'D2', 'REST', 'D3', 'REST', 'D4', 'REST', 'D5', ...
            'REST', 'pulgar', 'REST', '#C', 'REST', '#O', 'REST', '#P'}
    end

    properties
        source = 'simulated'              % 'myo' | 'udp' | 'simulated'
        device_name = 'Myo'               % nombre BLE / BLE name
        device_address = ''               % dirección BLE (opcional) / BLE address
        udp_port = 10001                  % puerto UDP local / local UDP port
        emg_mode = 2                      % 2 = EMG filtrado, 3 = crudo / 2 filtered, 3 raw
        buffer_seconds = 5                % tamaño del buffer / buffer size
        stale_timeout = 1.0               % s sin datos -> no fresco / s without data -> stale
        sim_label = 'auto'                % etiqueta simulada o 'auto' / label or 'auto'
        sim_intensity = 1.0               % intensidad simulada / simulated intensity
        sim_step_seconds = 2.0            % duración de cada paso 'auto' / 'auto' step length
        sim_realtime = true               % false: genera n muestras por lectura (tests)
    end

    properties (SetAccess = private)
        buffer = []
        write_idx = 1
        n_written = 0
        is_connected = false
        ble_device = []
        command_characteristic = []
        emg_characteristics = {}
        udp_object = []
        sim_clock = []
        sim_samples_emitted = 0
        last_sample_tic = []
    end

    methods
        function obj = myo_interface(varargin)
            % MYO_INTERFACE Constructor con pares nombre-valor de las propiedades públicas.
            % MYO_INTERFACE Constructor with name-value pairs of the public properties.
            for k = 1:2:numel(varargin) - 1
                name = char(varargin{k});
                if ~isprop(obj, name)
                    error('myo_interface:property', ...
                        'Propiedad desconocida / Unknown property: %s', name);
                end
                obj.(name) = varargin{k + 1};
            end
            obj.source = lower(char(obj.source));
            n = round(obj.buffer_seconds * obj.FS);
            obj.buffer = zeros(n, obj.N_CHANNELS);
        end

        function connect(obj)
            % CONNECT Abre la fuente de datos configurada. / Opens the configured source.
            switch obj.source
                case 'myo'
                    obj.connect_ble();
                case 'udp'
                    obj.udp_object = udpport('byte', 'LocalPort', obj.udp_port);
                    logger('INFO', 'myo_interface', ...
                        'Escuchando UDP / Listening UDP on port %d', obj.udp_port);
                case 'simulated'
                    obj.sim_clock = tic;
                    obj.sim_samples_emitted = 0;
                    logger('INFO', 'myo_interface', ...
                        'Fuente simulada / Simulated source (label=%s)', obj.sim_label);
                otherwise
                    error('myo_interface:source', ...
                        'Fuente desconocida / Unknown source: %s', obj.source);
            end
            obj.is_connected = true;
        end

        function disconnect(obj)
            % DISCONNECT Libera BLE/UDP y detiene el streaming. / Releases BLE/UDP.
            if strcmp(obj.source, 'myo') && ~isempty(obj.command_characteristic)
                try
                    write(obj.command_characteristic, [1, 3, 0, 0, 0]);   % EMG off
                catch
                    % El brazalete puede estar ya desconectado / may already be gone
                end
                for k = 1:numel(obj.emg_characteristics)
                    try
                        unsubscribe(obj.emg_characteristics{k});
                    catch
                        % Ignorado al cerrar / ignored on shutdown
                    end
                end
            end
            obj.emg_characteristics = {};
            obj.command_characteristic = [];
            obj.ble_device = [];
            obj.udp_object = [];
            obj.is_connected = false;
        end

        function delete(obj)
            % DELETE Destructor: desconecta. / Destructor: disconnects.
            obj.disconnect();
        end

        function [emg, is_fresh] = read_window(obj, n)
            % READ_WINDOW Devuelve las últimas n muestras (n x 8) en orden cronológico.
            % READ_WINDOW Returns the last n samples (n x 8) in chronological order.
            n = min(n, size(obj.buffer, 1));
            obj.poll(n);
            t_wait = tic;
            while obj.n_written < n && toc(t_wait) < obj.stale_timeout
                pause(0.005);
                obj.poll(n);
            end

            if obj.n_written == 0
                emg = zeros(n, obj.N_CHANNELS);
                is_fresh = false;
                return;
            end

            len = size(obj.buffer, 1);
            idx = mod(obj.write_idx - 1 - n + (0:n - 1), len) + 1;
            emg = obj.buffer(idx, :);
            is_fresh = ~isempty(obj.last_sample_tic) && ...
                toc(obj.last_sample_tic) <= obj.stale_timeout;
        end

        function push_samples(obj, samples)
            % PUSH_SAMPLES Escribe muestras (m x 8) en el buffer circular.
            % PUSH_SAMPLES Writes samples (m x 8) into the circular buffer.
            m = size(samples, 1);
            if m == 0
                return;
            end
            len = size(obj.buffer, 1);
            if m > len
                samples = samples(end - len + 1:end, :);
                m = len;
            end
            idx = mod(obj.write_idx - 1 + (0:m - 1), len) + 1;
            obj.buffer(idx, :) = double(samples);
            obj.write_idx = mod(obj.write_idx - 1 + m, len) + 1;
            obj.n_written = min(obj.n_written + m, len);
            obj.last_sample_tic = tic;
        end

        function set_sim_label(obj, label, intensity)
            % SET_SIM_LABEL Cambia el gesto simulado. / Changes the simulated gesture.
            obj.sim_label = label;
            if nargin >= 3
                obj.sim_intensity = intensity;
            end
        end

        function vibrate(obj, strength)
            % VIBRATE Vibración corta del Myo (1=corta, 2=media, 3=larga).
            % VIBRATE Short Myo vibration (1=short, 2=medium, 3=long).
            if nargin < 2
                strength = 1;
            end
            if strcmp(obj.source, 'myo') && ~isempty(obj.command_characteristic)
                try
                    write(obj.command_characteristic, [3, 1, strength]);
                catch err
                    logger('DEBUG', 'myo_interface', 'vibrate: %s', err.message);
                end
            end
        end
    end

    methods (Access = private)
        function connect_ble(obj)
            % CONNECT_BLE Conecta por BLE, desactiva el sueño y activa el streaming EMG.
            % CONNECT_BLE Connects over BLE, disables sleep and enables EMG streaming.
            %
            % Comandos (myohw.h) / Commands (myohw.h):
            %   [0x09 0x01 0x01]            set_sleep_mode = never_sleep
            %   [0x0A 0x01 0x02]            unlock = hold
            %   [0x01 0x03 emg 0x00 0x00]   set_mode (EMG on, IMU off, classifier off)
            if strlength(string(obj.device_address)) > 0
                target = obj.device_address;
            else
                target = obj.device_name;
            end
            logger('INFO', 'myo_interface', 'Conectando BLE / Connecting BLE: %s', target);
            obj.ble_device = ble(target);
            obj.command_characteristic = characteristic(obj.ble_device, ...
                obj.CONTROL_SERVICE, obj.COMMAND_CHAR);

            obj.emg_characteristics = cell(1, numel(obj.EMG_CHARS));
            for k = 1:numel(obj.EMG_CHARS)
                c = characteristic(obj.ble_device, obj.EMG_SERVICE, obj.EMG_CHARS{k});
                c.DataAvailableFcn = @(src, evt) obj.on_ble_data(src, evt);
                try
                    subscribe(c, 'notification');
                catch err
                    logger('DEBUG', 'myo_interface', 'subscribe: %s', err.message);
                end
                obj.emg_characteristics{k} = c;
            end

            write(obj.command_characteristic, [9, 1, 1]);
            write(obj.command_characteristic, [10, 1, 2]);
            write(obj.command_characteristic, [1, 3, obj.emg_mode, 0, 0]);
            obj.vibrate(1);
            logger('INFO', 'myo_interface', 'Myo conectado / connected (EMG mode %d)', ...
                obj.emg_mode);
        end

        function on_ble_data(obj, src, ~)
            % ON_BLE_DATA Callback BLE: 16 bytes = 2 muestras x 8 canales int8.
            % ON_BLE_DATA BLE callback: 16 bytes = 2 samples x 8 int8 channels.
            try
                data = read(src, 'oldest');
                obj.push_samples(decode_packet(data));
            catch err
                logger('DEBUG', 'myo_interface', 'BLE read: %s', err.message);
            end
        end

        function poll(obj, n)
            % POLL Da oportunidad a los callbacks o genera/lee datos pendientes.
            % POLL Lets callbacks run or generates/reads pending data.
            switch obj.source
                case 'myo'
                    pause(0.001);   % permite ejecutar callbacks BLE / lets BLE callbacks run
                case 'udp'
                    if isempty(obj.udp_object)
                        return;
                    end
                    n_bytes = obj.udp_object.NumBytesAvailable;
                    n_bytes = n_bytes - mod(n_bytes, 8);
                    if n_bytes > 0
                        data = read(obj.udp_object, n_bytes, 'uint8');
                        obj.push_samples(decode_packet(data));
                    end
                case 'simulated'
                    obj.poll_simulated(n);
            end
        end

        function poll_simulated(obj, n)
            % POLL_SIMULATED Genera las muestras que "llegaron" desde la última lectura.
            % POLL_SIMULATED Generates the samples that "arrived" since the last read.
            if isempty(obj.sim_clock)
                obj.sim_clock = tic;
            end
            if obj.sim_realtime
                due = floor(toc(obj.sim_clock) * obj.FS) - obj.sim_samples_emitted;
            else
                due = n;
            end
            due = min(due, size(obj.buffer, 1));
            if due <= 0
                return;
            end
            label = obj.current_sim_label();
            samples = myo_interface.synthetic_window(label, due, obj.sim_intensity);
            obj.push_samples(samples);
            obj.sim_samples_emitted = obj.sim_samples_emitted + due;
        end

        function label = current_sim_label(obj)
            % CURRENT_SIM_LABEL Etiqueta activa (fija o del guion 'auto').
            % CURRENT_SIM_LABEL Active label (fixed or from the 'auto' script).
            if ~strcmpi(obj.sim_label, 'auto')
                label = obj.sim_label;
                return;
            end
            elapsed = obj.sim_samples_emitted / obj.FS;
            step = floor(elapsed / obj.sim_step_seconds);
            label = obj.SIM_SCHEDULE{mod(step, numel(obj.SIM_SCHEDULE)) + 1};
        end
    end

    methods (Static)
        function obj = instance(varargin)
            % INSTANCE Devuelve (y crea si hace falta) la conexión única.
            % INSTANCE Returns (and creates if needed) the single connection.
            %   myo_interface.instance('source','myo', ...)  -> (re)configura / reconfigures
            %   myo_interface.instance()                     -> instancia existente / existing
            %   myo_interface.instance('reset')              -> desconecta / disconnects
            persistent singleton

            if numel(varargin) == 1 && strcmpi(char(varargin{1}), 'reset')
                if ~isempty(singleton) && isvalid(singleton)
                    singleton.disconnect();
                end
                singleton = [];
                obj = [];
                return;
            end

            needs_new = isempty(singleton) || ~isvalid(singleton) || ~isempty(varargin);
            if needs_new
                if ~isempty(singleton) && isvalid(singleton)
                    singleton.disconnect();
                end
                if isempty(varargin)
                    logger('WARN', 'myo_interface', ['Sin configurar: fuente simulada ', ...
                        '/ Not configured: simulated source']);
                end
                singleton = myo_interface(varargin{:});
                singleton.connect();
            end
            obj = singleton;
        end

        function activation = synthetic_profile(label)
            % SYNTHETIC_PROFILE Activación relativa por canal (0-1) de cada gesto sintético.
            % SYNTHETIC_PROFILE Relative per-channel activation (0-1) of each synthetic gesture.
            %
            % Coherente con el mapa anatómico de referencia del system prompt:
            % Consistent with the system prompt reference anatomical map:
            %   CH1 FCU->D5 | CH2 FDS cubital->D4 | CH3 FDS central->D3 | CH4 FDS/FDP radial->D2
            %   CH5 FPL/FCR->D1 | CH6 APL/EPB->D1 ext | CH7 ED/EI->D2-D3 ext | CH8 EDM/ECU->D4-D5
            switch lower(char(label))
                case 'rest'
                    activation = 0.04 * ones(1, 8);
                case 'pulgar'
                    activation = [0.06, 0.06, 0.08, 0.20, 0.84, 0.52, 0.10, 0.06];
                case 'd2'
                    activation = [0.06, 0.08, 0.22, 0.82, 0.18, 0.06, 0.44, 0.07];
                case 'd3'
                    activation = [0.08, 0.24, 0.83, 0.26, 0.10, 0.05, 0.40, 0.08];
                case 'd4'
                    activation = [0.28, 0.82, 0.30, 0.10, 0.07, 0.05, 0.12, 0.42];
                case 'd5'
                    activation = [0.80, 0.30, 0.12, 0.06, 0.08, 0.05, 0.10, 0.50];
                case '#c'
                    activation = [0.80, 0.82, 0.80, 0.84, 0.72, 0.20, 0.24, 0.22];
                case '#o'
                    activation = [0.10, 0.12, 0.10, 0.12, 0.18, 0.66, 0.78, 0.72];
                case '#p'
                    activation = [0.10, 0.12, 0.14, 0.72, 0.70, 0.24, 0.30, 0.10];
                otherwise
                    error('myo_interface:label', ...
                        'Etiqueta sintética desconocida / Unknown synthetic label: %s', label);
            end
        end

        function samples = synthetic_window(label, n, intensity)
            % SYNTHETIC_WINDOW Genera n x 8 muestras int8 (ruido gaussiano modulado).
            % SYNTHETIC_WINDOW Generates n x 8 int8 samples (modulated Gaussian noise).
            if nargin < 3 || isempty(intensity)
                intensity = 1.0;
            end
            activation = min(1, myo_interface.synthetic_profile(label) * intensity);
            amplitude = myo_interface.REST_AMPLITUDE + ...
                (myo_interface.MVC_AMPLITUDE - myo_interface.REST_AMPLITUDE) * activation;
            jitter = max(1 + 0.08 * randn(1, 8), 0.5);
            samples = randn(n, 8) .* (amplitude .* jitter);
            samples = max(min(round(samples), 127), -128);
        end
    end
end

% -------------------------------------------------------------------------------------------
function samples = decode_packet(data)
    % DECODE_PACKET Convierte bytes (múltiplo de 8) en muestras m x 8 con signo.
    % DECODE_PACKET Converts bytes (multiple of 8) into signed m x 8 samples.
    bytes = uint8(data(:)');
    bytes = bytes(1:end - mod(numel(bytes), 8));
    values = double(typecast(bytes, 'int8'));
    samples = reshape(values, 8, []).';
end
