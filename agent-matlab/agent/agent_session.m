classdef agent_session < handle
    % AGENT_SESSION Una sesión del agente: EMG -> LLM -> prótesis, impresa en consola.
    %   s = agent_session(cfg)            prepara registro, prompt y fuente de señal
    %   s = agent_session(cfg, plantilla) usa ese texto de prompt en lugar del archivo
    %   r = s.step()                      ejecuta un ciclo; r.done = true si no quedan datos
    %   s.finish()                        resumen, reposo a la prótesis, Myo liberado

    properties
        cfg                 % configuración usada (agent_config.m + cambios de la UI)
        system_prompt       % prompt final que recibe el LLM
        device              % fuente de señal (myo_interface)
        n                   % muestras por ventana
        prev                % último comando enviado
        smoothing = []      % memoria del suavizado
        stats               % contadores de la sesión
        clock               % reloj de la sesión (tic)
        log_file            % archivo con la copia de la consola
        finished = false    % true cuando ya se llamó a finish
    end

    methods
        function obj = agent_session(cfg, prompt_template)
            % Prepara todo lo necesario antes del primer ciclo.
            obj.cfg = cfg;                                          % guarda la configuración
            if ~isfolder(cfg.log_folder)
                mkdir(cfg.log_folder);                              % crea la carpeta de registros
            end
            obj.log_file = fullfile(cfg.log_folder, ['sesion_' datestr(now, 'yyyymmdd_HHMMSS') '.txt']);
            diary(obj.log_file);                                    % copia la consola a este archivo

            print_title('INICIO');
            log_msg('MAIN', 'Registro de la consola: %s', obj.log_file);
            print_config(cfg);                                      % configuración usada

            if nargin < 2 || isempty(prompt_template)               % sin texto de la UI
                prompt_template = read_text(cfg.llm.prompt_file);   % se lee el archivo del prompt
            end
            obj.system_prompt = build_system_prompt(prompt_template, cfg); % inserta gestos y reposo
            log_msg('MAIN', 'System prompt: %d caracteres', numel(obj.system_prompt));
            if cfg.console.system_prompt
                fprintf('%s\n', obj.system_prompt);                 % lo imprime completo
            end

            obj.device = myo_interface(cfg);                        % Myo o muestras
            obj.n = round(cfg.window_ms / 1000 * cfg.fs);           % muestras por ventana (40)
            obj.prev = struct('command', cfg.rest_command);         % al inicio, reposo
            obj.stats = struct('cycles', 0, 'llm_ok', 0, 'fallback', 0, 'prosthesis_ok', 0, 'llm_ms', 0);
            obj.clock = tic;                                        % arranca el reloj
        end

        function r = step(obj)
            % Un ciclo completo. r guarda todo lo calculado para mostrarlo en la UI.
            cfg = obj.cfg;                                          % atajo a la configuración
            timer = tic;                                            % reloj del ciclo
            r.t_ms = round(1000 * toc(obj.clock));                  % tiempo desde el inicio

            % 1. Adquisición
            [r.emg, r.origin] = obj.device.read_window(obj.n);      % siguiente ventana (40 x 8)
            r.done = isempty(r.emg);                                % no quedan datos
            if r.done
                return;
            end
            r.source = obj.device.source;                           % 'myo' o 'samples'
            obj.stats.cycles = obj.stats.cycles + 1;                % cuenta el ciclo
            r.cycle = obj.stats.cycles;                             % número de ciclo
            print_title(sprintf('CICLO %d | T = %d ms | %s', r.cycle, r.t_ms, r.origin));
            if cfg.console.raw_window
                print_matrix('Señal cruda', r.emg, '%6d');          % las 40 x 8 muestras
            end

            % 2. Procesamiento
            r.f = process_signals(r.emg, cfg);                      % filtro, RMS, MAV, estado, similitud
            if cfg.console.filtered_window
                print_matrix('Señal filtrada (20-95 Hz + notch)', r.f.filtered, '%6.1f');
            end
            print_vector('RMS crudo  ', r.f.rms_raw, '%6.2f');
            print_vector('RMS [0,1]  ', r.f.rms, '%6.2f');
            print_vector('MAV crudo  ', r.f.mav_raw, '%6.2f');
            print_vector('MAV [0,1]  ', r.f.mav, '%6.2f');
            for g = 1:numel(cfg.gestures)                           % parecido con cada gesto
                log_msg('SEÑAL', 'Similitud con %s (%s): %.2f', cfg.gestures(g).command, ...
                    cfg.gestures(g).name, r.f.similarity(g));
            end
            log_msg('SEÑAL', 'Estado: %s %s', r.f.state, r.f.noise);

            % 3. Entrada del LLM: texto + imagen
            r.payload = build_payload(r.f, obj.prev, r.t_ms, cfg);  % texto de una línea
            r.image_file = generate_image(r.f, r.t_ms, cfg);        % gráfico de barras en PNG

            % 4. LLM
            r.reply = send_input_llm(cfg.llm, obj.system_prompt, r.payload, r.image_file);
            obj.stats.llm_ms = obj.stats.llm_ms + r.reply.latency_ms; % acumula la latencia
            if r.reply.ok
                [cmd, r.valid, r.reason] = parse_llm_response(r.reply.content, cfg); % extrae y valida
            else
                [cmd, r.valid, r.reason] = deal([], false, r.reply.error); % no hubo respuesta
            end

            % 5. Respaldo si el LLM falla
            if r.valid
                obj.stats.llm_ok = obj.stats.llm_ok + 1;            % comando del LLM aceptado
                log_msg('LLM', 'Comando válido');
            else
                obj.stats.fallback = obj.stats.fallback + 1;        % se usa el respaldo
                log_msg('LLM', 'Respuesta descartada: %s', r.reason);
                cmd = fallback_command(r.f, obj.prev, cfg);         % reglas locales
            end
            r.decided = cmd;                                        % comando antes del suavizado
            print_command('Decidido ', cmd);

            % 6. Suavizado y envío
            [r.sent, obj.smoothing] = smooth_command(cmd, obj.smoothing, cfg); % evita parpadeos
            print_command('A enviar ', r.sent);
            log_msg('SUAVE', '%s', r.sent.smoothing);
            r.prosthesis_ok = send_prosthesis_command(cfg.prosthesis, r.sent.command); % POST
            obj.stats.prosthesis_ok = obj.stats.prosthesis_ok + r.prosthesis_ok; % cuenta aceptados
            obj.prev = r.sent;                                      % PREV del siguiente ciclo

            r.cycle_ms = 1000 * toc(timer);                         % duración del ciclo
            log_msg('MAIN', 'Ciclo %d terminado en %.0f ms', r.cycle, r.cycle_ms);
        end

        function summary = finish(obj)
            % Imprime el resumen y deja todo en estado seguro (se puede llamar varias veces).
            summary = obj.stats;                                    % contadores
            summary.duration_s = toc(obj.clock);                    % duración total
            summary.llm_mean_ms = obj.stats.llm_ms / max(obj.stats.cycles, 1); % latencia media
            if obj.finished                                         % ya se cerró antes
                return;
            end
            obj.finished = true;                                    % evita cerrar dos veces

            print_title('RESUMEN');
            fprintf('Ciclos                 : %d\n', summary.cycles);
            fprintf('Comandos del LLM       : %d\n', summary.llm_ok);
            fprintf('Comandos de respaldo   : %d\n', summary.fallback);
            fprintf('Aceptados por prótesis : %d\n', summary.prosthesis_ok);
            fprintf('Latencia media del LLM : %.0f ms\n', summary.llm_mean_ms);
            fprintf('Duración               : %.1f s\n', summary.duration_s);

            safe = obj.cfg.prosthesis.safe_command;                 % comando de reposo
            log_msg('MAIN', 'Fin: se envía el comando de reposo %s', safe);
            send_prosthesis_command(obj.cfg.prosthesis, safe);      % deja la mano en reposo
            obj.device.close();                                     % libera el Bluetooth
            diary('off');                                           % cierra el registro
        end
    end
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
