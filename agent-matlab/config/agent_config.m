function cfg = agent_config()
% AGENT_CONFIG Toda la configuración del proyecto. Es el único archivo que hay que editar.

root = fileparts(fileparts(mfilename('fullpath')));        % carpeta raíz del proyecto

%% Fuente de la señal
cfg.source = 'myo';                                         % 'myo' (si no responde usa las muestras) o 'samples'
cfg.myo.device_name = 'Myo';                                % nombre Bluetooth del brazalete
cfg.myo.emg_mode = 2;                                       % 2 = EMG filtrado por el Myo, 3 = EMG crudo
cfg.myo.connect_timeout = 3;                                % s para recibir el primer EMG tras conectar
cfg.myo.dropout_timeout = 3;                                % s sin EMG antes de pasar a las muestras
cfg.samples.folder = fullfile(root, 'samples');             % carpeta con muestra_1.csv ... muestra_N.csv
cfg.samples.count = 15;                                     % número de archivos de muestras
cfg.samples.loop = false;                                   % true = volver a empezar al terminar

%% Ciclo de control
cfg.fs = 200;                                               % frecuencia de muestreo del Myo (Hz)
cfg.window_ms = 200;                                        % duración de cada ventana (ms) -> 40 muestras
cfg.period_s = 0.2;                                         % duración mínima de cada ciclo (s)
cfg.max_cycles = Inf;                                       % ciclos máximos (Inf = sin límite)

%% Procesamiento de la señal
cfg.signal.band_hz = [20 95];                               % banda del filtro pasa-banda (Hz)
cfg.signal.powerline_hz = 60;                               % frecuencia de la red eléctrica (Hz)
cfg.signal.rest_rms = [2 2 6 4 5 3 2 2];                    % RMS de cada canal en reposo
cfg.signal.max_rms = [50 50 50 50 50 50 50 50];             % RMS de cada canal en contracción máxima
cfg.signal.rest_mav = 0.8 * cfg.signal.rest_rms;            % MAV en reposo (MAV ~ 0.8 x RMS)
cfg.signal.max_mav = 0.8 * cfg.signal.max_rms;              % MAV en contracción máxima
cfg.signal.rest_threshold = 0.15;                           % por debajo: REST
cfg.signal.active_threshold = 0.40;                         % por encima: ACTIVE
cfg.signal.saturation_level = 127;                          % valor de saturación del Myo (int8)

%% Imagen que recibe el LLM
cfg.image.width = 640;                                      % ancho en píxeles
cfg.image.height = 480;                                     % alto en píxeles
cfg.image.file = fullfile(tempdir, 'emg_bars.png');         % archivo temporal de la imagen

%% Servidor del LLM (LM Studio)
cfg.llm.ip = '100.78.75.38';                                % IP del servidor
cfg.llm.ports = 1234;                                       % puertos; se prueban en orden, p. ej. [1234 1235]
cfg.llm.endpoint = '/v1/chat/completions';                  % endpoint compatible con OpenAI
cfg.llm.model = 'mistralai/ministral-3-3b';                 % modelo cargado en LM Studio
cfg.llm.api_key = 'lm-studio';                              % clave (LM Studio no la valida)
cfg.llm.timeout = 0.5;                                      % s de espera por puerto
cfg.llm.max_tokens = 200;                                   % tokens máximos de la respuesta
cfg.llm.temperature = 0;                                    % 0 = respuesta determinista
cfg.llm.stop = {['}' newline], ['}' char(13) newline]};     % cortar al cerrar el JSON
cfg.llm.prompt_file = fullfile(root, 'config', 'system_es.txt'); % system prompt (o system_en.txt)

%% Prótesis
cfg.prosthesis.host = '100.73.114.17';                      % IP del servidor de la prótesis
cfg.prosthesis.port = 8000;                                 % puerto
cfg.prosthesis.endpoint = '/api/command';                   % ruta del POST
cfg.prosthesis.timeout = 0.5;                               % s de espera por comando
cfg.prosthesis.safe_command = '#R';                         % comando de reposo al terminar

%% Suavizado del comando
cfg.smoothing.window = 3;                                   % comandos recordados para el voto
cfg.smoothing.alpha = 0.5;                                  % peso del valor nuevo (media móvil)
cfg.smoothing.fast_confidence = 0.85;                       % confianza para cambiar sin esperar el voto
cfg.smoothing.rest_confidence = 0.60;                       % confianza para pasar a reposo sin esperar

%% Consola y registros
cfg.console.system_prompt = true;                           % imprimir el system prompt al iniciar
cfg.console.raw_window = true;                              % imprimir las 40x8 muestras de cada ventana
cfg.console.filtered_window = true;                         % imprimir la ventana filtrada
cfg.log_folder = fullfile(root, 'logs');                    % la consola completa se guarda aquí
end
