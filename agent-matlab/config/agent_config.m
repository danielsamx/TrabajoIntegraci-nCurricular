function cfg = agent_config()
% AGENT_CONFIG Toda la configuración del proyecto. Es el único archivo que hay que editar.

root = fileparts(fileparts(mfilename('fullpath')));        % carpeta raíz del proyecto

%% Myo Armband (única fuente de señal)
cfg.myo.link = 'dongle';                                    % 'dongle' = adaptador USB del Myo, 'bluetooth' = Bluetooth del PC
cfg.myo.dongle_port = 'auto';                               % puerto del adaptador USB (BLED112); 'auto' lo busca
cfg.myo.device_name = 'MYO.94';                             % nombre del brazalete (solo para Bluetooth del PC)
cfg.myo.scan_timeout = 10;                                  % s buscando el Myo con el adaptador
cfg.myo.emg_mode = 2;                                       % 2 = EMG filtrado por el Myo, 3 = EMG crudo
cfg.myo.connect_timeout = 3;                                % s para recibir el primer EMG tras conectar
cfg.myo.dropout_timeout = 3;                                % s sin EMG antes de avisar que el Myo se cortó

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

%% Comandos de la prótesis (sin '#')
cfg.rest_command = 'S';                                     % reposo: mano relajada, ligeramente abierta
cfg.gestures(1).command = 'C';                              % comando de la mano cerrada
cfg.gestures(1).name = 'mano cerrada (puño)';               % nombre para el prompt y la consola
cfg.gestures(1).hint = 'CH7 alto y CH3 casi 0';             % canales que lo distinguen
cfg.gestures(1).profile = [0.59 0.29 0.02 0.37 0.17 0.08 0.45 0.46]; % RMS medio CH1..CH8 en las muestras
cfg.gestures(2).command = 'O';                              % comando de la mano abierta
cfg.gestures(2).name = 'mano abierta';                      % nombre para el prompt y la consola
cfg.gestures(2).hint = 'CH3 alto y CH7 casi 0';             % canales que lo distinguen
cfg.gestures(2).profile = [0.33 0.10 0.44 0.31 0.02 0.01 0.03 0.42]; % RMS medio CH1..CH8 en las muestras

%% Imágenes que recibe el LLM (todas se ven en el dashboard)
cfg.image.send.features = true;                             % matriz de características (RMS, MAV, WL, ZC, SSC)
cfg.image.send.waves = true;                                % ondas normalizadas de los canales
cfg.image.send.envelope = false;                            % envolvente general (media de los 8 canales)
cfg.image.context_s = 1;                                    % segundos de señal en ondas y envolvente
cfg.image.envelope_ms = 50;                                 % ventana de la envolvente RMS móvil (ms)
cfg.image.width = 640;                                      % ancho de cada imagen en píxeles
cfg.image.height = 480;                                     % alto de cada imagen en píxeles

%% Servidor del LLM (LM Studio)
cfg.llm.ip = '100.92.219.95';                                % IP del servidor
cfg.llm.ports = 1234;                                       % puertos; se prueban en orden, p. ej. [1234 1235]
cfg.llm.endpoint = '/v1/chat/completions';                  % endpoint compatible con OpenAI
cfg.llm.model = 'mistralai/ministral-3-3b';                 % modelo cargado en LM Studio
cfg.llm.api_key = 'lm-studio';                              % clave (LM Studio no la valida)
cfg.llm.timeout = 0.5;                                      % s de espera por puerto
cfg.llm.max_tokens = 40;                                    % la respuesta es un JSON corto
cfg.llm.temperature = 0;                                    % 0 = respuesta determinista
cfg.llm.stop = {['}' newline], ['}' char(13) newline]};     % cortar al cerrar el JSON
cfg.llm.prompt_file = fullfile(root, 'config', 'system_es.txt'); % system prompt (o system_en.txt)

%% Prótesis
cfg.prosthesis.mode = 'http';                               % comunicación: 'http' o 'serial'
cfg.prosthesis.host = '100.73.114.17';                      % IP del servidor de la prótesis
cfg.prosthesis.port = 8000;                                 % puerto
cfg.prosthesis.endpoint = '/api/command';                   % ruta del POST
cfg.prosthesis.timeout = 0.5;                               % s de espera por comando
cfg.prosthesis.serial_port = 'COM3';                        % puerto serie (Windows: COMx)
cfg.prosthesis.baud_rate = 115200;                          % velocidad del puerto serie
cfg.prosthesis.terminator = 'LF';                           % fin de línea: 'LF', 'CR' o 'CR/LF'
cfg.prosthesis.safe_command = 'S';                          % comando de reposo al terminar

%% Suavizado del comando
cfg.smoothing.window = 3;                                   % comandos recordados para el voto
cfg.smoothing.fast_confidence = 0.85;                       % confianza para cambiar sin esperar el voto
cfg.smoothing.rest_confidence = 0.60;                       % confianza para pasar a reposo sin esperar

%% Consola y registros
cfg.console.system_prompt = true;                           % imprimir el system prompt al iniciar
cfg.console.raw_window = true;                              % imprimir las 40x8 muestras de cada ventana
cfg.console.filtered_window = true;                         % imprimir la ventana filtrada
cfg.log_folder = fullfile(root, 'logs');                    % la consola completa se guarda aquí
end
