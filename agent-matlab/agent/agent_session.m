classdef agent_session < handle
    % AGENT_SESSION Una sesión del agente: EMG -> LLM -> prótesis, impresa en consola.
    %   s = agent_session(cfg)            prepara registro y prompt, comprueba el LLM y conecta el Myo
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
        context             % último segundo de señal filtrada (para ondas, envolvente y mapa)
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

            try
                obj.check_llm();                                    % sin servidor LLM no se arranca
                if ~strcmp(cfg.prosthesis.mode, 'http')             % serie o Bluetooth: conectar ya
                    send_prosthesis_command(cfg.prosthesis, 'open'); % falla con el motivo si no conecta
                end
                obj.device = myo_interface(cfg);                    % conecta el Myo
            catch err
                send_prosthesis_command('close');                   % libera la prótesis si llegó a abrirse
                diary('off');                                       % cierra el registro antes de avisar
                rethrow(err);                                       % la UI o la consola muestran el motivo
            end
            obj.n = round(cfg.window_ms / 1000 * cfg.fs);           % muestras por ventana (40)
            obj.prev = struct('command', cfg.rest_command);         % al inicio, reposo
            obj.context = zeros(round(cfg.image.context_s * cfg.fs), 8); % contexto vacío
            obj.stats = struct('cycles', 0, 'llm_ok', 0, 'llm_failed', 0, 'prosthesis_ok', 0, 'llm_ms', 0);
            obj.clock = tic;                                        % arranca el reloj
        end

        function r = step(obj)
            % Un ciclo completo. r guarda todo lo calculado para mostrarlo en la UI.
            cfg = obj.cfg;                                          % atajo a la configuración
            timer = tic;                                            % reloj del ciclo
            r.t_ms = round(1000 * toc(obj.clock));                  % tiempo desde el inicio

            % 1. Adquisición
            [r.emg, r.origin] = obj.device.read_window(obj.n);      % siguiente ventana del Myo (40 x 8)
            r.done = isempty(r.emg);                                % sin datos (no debería ocurrir)
            if r.done
                return;
            end
            obj.stats.cycles = obj.stats.cycles + 1;                % cuenta el ciclo
            r.cycle = obj.stats.cycles;                             % número de ciclo
            print_title(sprintf('CICLO %d | T = %d ms | %s', r.cycle, r.t_ms, r.origin));
            if cfg.console.raw_window
                print_matrix('Señal cruda', r.emg, '%6d');          % las 40 x 8 muestras
            end

            % 2. Procesamiento
            r.f = process_signals(r.emg, cfg);                      % filtro, RMS, MAV, similitud y distancias
            if cfg.console.filtered_window
                print_matrix('Señal filtrada (20-95 Hz + notch)', r.f.filtered, '%6.1f');
            end
            print_vector('RMS crudo  ', r.f.rms_raw, '%6.2f');
            print_vector('RMS [0,1]  ', r.f.rms, '%6.2f');
            print_vector('MAV crudo  ', r.f.mav_raw, '%6.2f');
            print_vector('MAV [0,1]  ', r.f.mav, '%6.2f');
            for g = 1:numel(cfg.gestures)                           % parecido y distancia a cada gesto
                log_msg('SEÑAL', '%s (%s): similitud %.2f | distancia %.2f', cfg.gestures(g).command, ...
                    cfg.gestures(g).name, r.f.similarity(g), r.f.distance(g));
            end
            log_msg('SEÑAL', '%s (reposo): distancia %.2f', cfg.rest_command, r.f.rest_distance);
            print_vector('WL         ', r.f.wl, '%6.0f');
            print_vector('ZC         ', r.f.zc, '%6d');
            print_vector('SSC        ', r.f.ssc, '%6d');

            % 3. Entrada del LLM: texto + imágenes marcadas
            n = size(r.f.filtered, 1);                              % muestras nuevas
            obj.context = [obj.context(n + 1:end, :); r.f.filtered]; % desplaza y añade la ventana
            r.vis = visual_data(r.f, obj.context, cfg);             % datos de las 4 imágenes
            r.payload = build_payload(r.f, obj.prev, r.t_ms, cfg);  % texto de una línea
            r.image_files = generate_images(r.vis, r.f, cfg);       % PNG de las imágenes marcadas

            % 4. LLM
            r.reply = send_input_llm(cfg.llm, obj.system_prompt, r.payload, r.image_files);
            obj.stats.llm_ms = obj.stats.llm_ms + r.reply.latency_ms; % acumula la latencia
            if r.reply.ok
                [cmd, r.valid, r.reason] = parse_llm_response(r.reply.content, cfg); % extrae y valida
            else
                [cmd, r.valid, r.reason] = deal([], false, r.reply.error); % no hubo respuesta
            end

            % 5. Sin comando válido del LLM no se envía nada
            [r.decided, r.sent, r.prosthesis_ok] = deal([], [], false); % por defecto, nada decidido
            if ~r.valid
                obj.stats.llm_failed = obj.stats.llm_failed + 1;    % ciclo sin comando
                log_msg('LLM', 'Sin comando: %s', r.reason);
                log_msg('PROT', 'No se envía nada; la prótesis mantiene %s', obj.prev.command);
                r.cycle_ms = 1000 * toc(timer);                     % duración del ciclo
                log_msg('MAIN', 'Ciclo %d terminado en %.0f ms', r.cycle, r.cycle_ms);
                return;
            end
            obj.stats.llm_ok = obj.stats.llm_ok + 1;                % comando del LLM aceptado
            log_msg('LLM', 'Comando válido');
            r.decided = cmd;                                        % comando antes del suavizado
            print_command('Decidido ', cmd);

            % 6. Suavizado y envío
            [r.sent, obj.smoothing] = smooth_command(cmd, obj.smoothing, cfg); % evita parpadeos
            print_command('A enviar ', r.sent);
            log_msg('SUAVE', '%s', r.sent.smoothing);
            r.prosthesis_ok = send_prosthesis_command(cfg.prosthesis, r.sent.command); % HTTP o serie
            obj.stats.prosthesis_ok = obj.stats.prosthesis_ok + r.prosthesis_ok; % cuenta aceptados
            obj.prev = r.sent;                                      % PREV del siguiente ciclo

            r.cycle_ms = 1000 * toc(timer);                         % duración del ciclo
            log_msg('MAIN', 'Ciclo %d terminado en %.0f ms', r.cycle, r.cycle_ms);
        end

        function check_llm(obj)
            % Comprueba que el servidor LLM responde y que tiene el modelo configurado.
            llm = obj.cfg.llm;
            log_msg('LLM', 'Comprobando el servidor: http://%s:[%s]/v1/models', llm.ip, num2str(llm.ports));
            [models, report] = list_llm_models(llm);                % GET /v1/models
            for k = 1:numel(report)
                log_msg('LLM', '  %s', report{k});                  % resultado de cada puerto
            end
            if isempty(models)                                      % ningún puerto respondió
                error('agent:llm', ['El servidor LLM no responde en %s (puertos %s). ' ...
                    'Inicia el servidor en LM Studio y vuelve a pulsar Iniciar.\n%s'], ...
                    llm.ip, num2str(llm.ports), strjoin(report, newline));
            end
            log_msg('LLM', 'Modelos disponibles: %s', strjoin(models, ', '));
            if ~any(strcmp(models, llm.model))                      % el modelo elegido no está
                error('agent:model', ['El servidor LLM no tiene el modelo "%s". ' ...
                    'Pulsa Cargar junto a Modelo y elige uno de: %s'], llm.model, strjoin(models, ', '));
            end
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
            fprintf('Ciclos sin comando     : %d\n', summary.llm_failed);
            fprintf('Aceptados por prótesis : %d\n', summary.prosthesis_ok);
            fprintf('Latencia media del LLM : %.0f ms\n', summary.llm_mean_ms);
            fprintf('Duración               : %.1f s\n', summary.duration_s);

            safe = obj.cfg.prosthesis.safe_command;                 % comando de reposo
            log_msg('MAIN', 'Fin: se envía el comando de reposo %s', safe);
            send_prosthesis_command(obj.cfg.prosthesis, safe);      % deja la mano en reposo
            send_prosthesis_command('close');                       % libera el puerto serie o Bluetooth
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
log_msg('CONFIG', 'Myo por %s | ventana %d ms a %d Hz | periodo %.2f s', cfg.myo.link, ...
    cfg.window_ms, cfg.fs, cfg.period_s);
log_msg('CONFIG', 'LLM: http://%s:[%s]%s | modelo %s | timeout %.2f s', cfg.llm.ip, ...
    num2str(cfg.llm.ports), cfg.llm.endpoint, cfg.llm.model, cfg.llm.timeout);
if strcmp(cfg.prosthesis.mode, 'serial')
    log_msg('CONFIG', 'Prótesis: serie %s a %d baudios (fin de línea %s)', cfg.prosthesis.serial_port, ...
        cfg.prosthesis.baud_rate, cfg.prosthesis.terminator);
elseif strcmp(cfg.prosthesis.mode, 'bluetooth')
    log_msg('CONFIG', 'Prótesis: Bluetooth "%s" canal %d (fin de línea %s)', cfg.prosthesis.bt_name, ...
        cfg.prosthesis.bt_channel, cfg.prosthesis.terminator);
else
    log_msg('CONFIG', 'Prótesis: http://%s:%d%s', cfg.prosthesis.host, cfg.prosthesis.port, ...
        cfg.prosthesis.endpoint);
end
[kinds, titles] = image_kinds();                            % imágenes que se enviarán al LLM
sent = titles(cellfun(@(k) cfg.image.send.(k), kinds));
if isempty(sent)
    sent = {'ninguna'};                                     % solo se enviará el texto
end
log_msg('CONFIG', 'Imágenes al LLM: %s', strjoin(sent, ', '));
log_msg('CONFIG', 'Filtro %d-%d Hz, notch %d Hz', cfg.signal.band_hz, cfg.signal.powerline_hz);
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
