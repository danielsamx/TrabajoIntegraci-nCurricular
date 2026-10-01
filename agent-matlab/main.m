function summary = main(source)
% MAIN Agente de control de la prótesis: EMG -> LLM -> prótesis, impreso todo en consola.
%   main            usa la fuente de agent_config.m (Myo; si no está activo, las muestras)
%   main('samples') reproduce directamente samples/muestra_1..15.csv
%   Toda la configuración está en config/agent_config.m. Ctrl+C detiene el agente.

root = fileparts(mfilename('fullpath'));                    % carpeta del proyecto
folders = {'config', 'acquisition', 'processing', 'llm', 'prosthesis', 'utils'};
for k = 1:numel(folders)
    addpath(fullfile(root, folders{k}));                    % añade cada carpeta al path
end

cfg = agent_config();                                       % carga toda la configuración
if nargin >= 1
    cfg.source = source;                                    % la fuente pedida al llamar
end

if ~isfolder(cfg.log_folder)
    mkdir(cfg.log_folder);                                  % crea la carpeta de registros
end
log_file = fullfile(cfg.log_folder, ['sesion_' datestr(now, 'yyyymmdd_HHMMSS') '.txt']);
diary(log_file);                                            % copia toda la consola a este archivo

print_title('INICIO');
log_msg('MAIN', 'Registro de la consola: %s', log_file);
print_config(cfg);                                          % muestra la configuración usada

fid = fopen(cfg.llm.prompt_file, 'r', 'n', 'UTF-8');       % abre el prompt como UTF-8 (tildes)
system_prompt = fread(fid, [1 Inf], '*char');               % reglas que sigue el LLM
fclose(fid);                                                % cierra el archivo
system_prompt = strrep(system_prompt, '{{GESTOS}}', gesture_lines(cfg)); % añade los gestos de la configuración
log_msg('MAIN', 'System prompt: %s (%d caracteres)', cfg.llm.prompt_file, numel(system_prompt));
if cfg.console.system_prompt
    fprintf('%s\n', system_prompt);                         % lo imprime completo
end

device = myo_interface(cfg);                                % Myo o muestras
n = round(cfg.window_ms / 1000 * cfg.fs);                   % muestras por ventana (40)
cleanup = onCleanup(@() finish(device, cfg));               % al salir: reposo, liberar Myo, cerrar log

prev = struct('command', cfg.rest_command);                 % último comando enviado (al inicio, reposo)
smoothing = [];                                             % memoria del suavizado
stats = struct('cycles', 0, 'llm_ok', 0, 'fallback', 0, 'prosthesis_ok', 0, 'llm_ms', 0);
session = tic;                                              % reloj de la sesión

while stats.cycles < cfg.max_cycles
    cycle_timer = tic;                                      % reloj de este ciclo
    t_ms = round(1000 * toc(session));                      % tiempo desde el inicio

    % 1. Adquisición
    [emg, origin] = device.read_window(n);                  % siguiente ventana de 40 x 8
    if isempty(emg)                                         % no quedan datos
        break;
    end
    stats.cycles = stats.cycles + 1;                        % cuenta el ciclo
    print_title(sprintf('CICLO %d | T = %d ms | %s', stats.cycles, t_ms, origin));
    if cfg.console.raw_window
        print_matrix('Señal cruda', emg, '%6d');            % las 40 x 8 muestras recibidas
    end

    % 2. Procesamiento
    f = process_signals(emg, cfg);                          % filtro, RMS, MAV y estado
    if cfg.console.filtered_window
        print_matrix('Señal filtrada (20-95 Hz + notch)', f.filtered, '%6.1f');
    end
    print_vector('RMS crudo  ', f.rms_raw, '%6.2f');
    print_vector('RMS [0,1]  ', f.rms, '%6.2f');
    print_vector('MAV crudo  ', f.mav_raw, '%6.2f');
    print_vector('MAV [0,1]  ', f.mav, '%6.2f');
    for g = 1:numel(cfg.gestures)                           % parecido con cada gesto
        log_msg('SEÑAL', 'Similitud con %s (%s): %.2f', cfg.gestures(g).command, ...
            cfg.gestures(g).name, f.similarity(g));
    end
    log_msg('SEÑAL', 'Estado: %s %s', f.state, f.noise);

    % 3. Entrada del LLM: texto + imagen
    payload = build_payload(f, prev, t_ms, cfg);            % texto de una línea
    image_file = generate_image(f, t_ms, cfg);              % gráfico de barras en PNG

    % 4. LLM
    reply = send_input_llm(cfg.llm, system_prompt, payload, image_file);
    stats.llm_ms = stats.llm_ms + reply.latency_ms;         % acumula la latencia
    if reply.ok
        [cmd, valid, reason] = parse_llm_response(reply.content, cfg); % extrae y valida el JSON
    else
        [cmd, valid, reason] = deal([], false, reply.error); % no hubo respuesta
    end

    % 5. Respaldo si el LLM falla
    if valid
        stats.llm_ok = stats.llm_ok + 1;                    % comando del LLM aceptado
        log_msg('LLM', 'Comando válido');
    else
        stats.fallback = stats.fallback + 1;                % se usa el respaldo
        log_msg('LLM', 'Respuesta descartada: %s', reason);
        cmd = fallback_command(f, prev, cfg);               % reglas locales
    end
    print_command('Decidido ', cmd);

    % 6. Suavizado y envío
    [cmd, smoothing] = smooth_command(cmd, smoothing, cfg);
    print_command('A enviar ', cmd);
    log_msg('SUAVE', '%s', cmd.smoothing);
    if send_prosthesis_command(cfg.prosthesis, cmd.command)
        stats.prosthesis_ok = stats.prosthesis_ok + 1;      % la prótesis lo aceptó
    end
    prev = cmd;                                             % será el PREV del siguiente ciclo

    elapsed = toc(cycle_timer);                             % duración del ciclo
    log_msg('MAIN', 'Ciclo %d terminado en %.0f ms', stats.cycles, 1000 * elapsed);
    pause(max(0, cfg.period_s - elapsed));                  % espera hasta completar el periodo
end

print_title('RESUMEN');
summary = stats;                                            % estadísticas de la sesión
summary.duration_s = toc(session);                          % duración total
summary.llm_mean_ms = stats.llm_ms / max(stats.cycles, 1);  % latencia media del LLM
fprintf('Ciclos                 : %d\n', summary.cycles);
fprintf('Comandos del LLM       : %d\n', summary.llm_ok);
fprintf('Comandos de respaldo   : %d\n', summary.fallback);
fprintf('Aceptados por prótesis : %d\n', summary.prosthesis_ok);
fprintf('Latencia media del LLM : %.0f ms\n', summary.llm_mean_ms);
fprintf('Duración               : %.1f s\n', summary.duration_s);
end

function finish(device, cfg)
% Al terminar (normal, error o Ctrl+C): prótesis en reposo, Myo liberado, registro cerrado.
log_msg('MAIN', 'Fin: se envía el comando de reposo %s', cfg.prosthesis.safe_command);
send_prosthesis_command(cfg.prosthesis, cfg.prosthesis.safe_command); % deja la mano en reposo
device.close();                                             % libera el Bluetooth
diary('off');                                               % cierra el archivo de registro
end

function print_title(text)
% Línea separadora con un título.
fprintf('\n==================== %s ====================\n', text);
end

function print_config(cfg)
% Imprime la configuración principal.
log_msg('CONFIG', 'Fuente: %s | ventana %d ms a %d Hz | periodo %.2f s', cfg.source, ...
    cfg.window_ms, cfg.fs, cfg.period_s);
log_msg('CONFIG', 'LLM: http://%s:[%s]%s | modelo %s | timeout %.2f s', cfg.llm.ip, ...
    num2str(cfg.llm.ports), cfg.llm.endpoint, cfg.llm.model, cfg.llm.timeout);
log_msg('CONFIG', 'Prótesis: http://%s:%d%s', cfg.prosthesis.host, cfg.prosthesis.port, ...
    cfg.prosthesis.endpoint);
log_msg('CONFIG', 'Filtro %d-%d Hz, notch %d Hz | umbrales REST %.2f, ACTIVE %.2f', ...
    cfg.signal.band_hz, cfg.signal.powerline_hz, cfg.signal.rest_threshold, ...
    cfg.signal.active_threshold);
print_vector('RMS reposo ', cfg.signal.rest_rms, '%6.1f');
print_vector('RMS máximo ', cfg.signal.max_rms, '%6.1f');
log_msg('CONFIG', 'Comandos: %s = reposo', cfg.rest_command);
for g = 1:numel(cfg.gestures)
    log_msg('CONFIG', 'Comandos: %s = %s (%s)', cfg.gestures(g).command, ...
        cfg.gestures(g).name, cfg.gestures(g).hint);
end
end

function text = gesture_lines(cfg)
% Una línea del prompt por gesto: comando, nombre, canales clave y perfil RMS.
text = '';
for g = 1:numel(cfg.gestures)
    gesture = cfg.gestures(g);                              % gesto actual
    profile = sprintf('%.2f,', gesture.profile);            % perfil con 2 decimales
    text = [text, sprintf('- %s = %s. Canales clave: %s. Perfil RMS medio CH1..CH8: [%s]\n', ...
        gesture.command, gesture.name, gesture.hint, profile(1:end - 1))]; %#ok<AGROW>
end
text = strtrim(text);                                       % quita el último salto de línea
end

function print_matrix(name, data, fmt)
% Imprime una ventana N x 8 con una fila por muestra.
fprintf('%s (%d muestras x 8 canales):\n', name, size(data, 1));
fprintf('     #    CH1   CH2   CH3   CH4   CH5   CH6   CH7   CH8\n');
for k = 1:size(data, 1)
    fprintf('%6d', k);                                      % número de muestra
    fprintf([' ' fmt], data(k, :));                         % sus 8 valores
    fprintf('\n');
end
end

function print_vector(name, values, fmt)
% Imprime un valor por canal en una sola línea.
fprintf('%s CH1..CH8:', name);
fprintf([' ' fmt], values);
fprintf('\n');
end

function print_command(name, cmd)
% Imprime un comando en una línea.
log_msg('CMD', '%s %s | confianza %.2f | origen %s', name, cmd.command, cmd.confidence, cmd.source);
end
