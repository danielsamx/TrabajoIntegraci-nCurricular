function summary = main(varargin)
    % MAIN Loop principal del agente de control de prótesis (sEMG -> LLM -> prótesis).
    %
    % MAIN Main loop of the prosthesis control agent (sEMG -> LLM -> prosthesis).
    %
    % Flujo por ciclo / Per-cycle flow:
    %   1. Adquirir ventana del Myo                / acquire Myo window
    %   2. Procesar señal (filtro, RMS, MAV, estado) / process signal
    %   3. Filtrar ruido                           / reject noise
    %   4. Construir payload ASCII + imagen        / build ASCII payload + image
    %   5. Invocar LLM (OBLIGATORIO)               / call the LLM (MANDATORY)
    %   6. Validar respuesta                       / validate the answer
    %   7. Fallback LDA si el LLM falla            / LDA fallback if the LLM fails
    %   8. Suavizar temporalmente                  / temporal smoothing
    %   9. Enviar a prótesis                       / send to the prosthesis
    %  10. Esperar siguiente ciclo                 / wait for the next cycle
    %
    % DECISIÓN: invocación obligatoria al LLM | RAZÓN: requisito del proyecto; el LLM se
    %   llama en TODOS los ciclos, incluso en REST y NOISE | ALTERNATIVA DESCARTADA: LLM
    %   opcional o solo en ACTIVE (no cumple el requisito)
    % DECISION: mandatory LLM call | REASON: project requirement; the LLM is called on EVERY
    %   cycle, even in REST and NOISE | DISCARDED ALTERNATIVE: optional LLM or ACTIVE-only
    %   (does not meet the requirement)
    %
    % DECISIÓN: el LDA solo actúa si el LLM falla (error HTTP, timeout, JSON inválido o
    %   incoherente) | RAZÓN: requisito 3 (fallback de emergencia) | ALTERNATIVA
    %   DESCARTADA: votación LLM+LDA (el LLM dejaría de ser el clasificador principal)
    % DECISION: the LDA only acts if the LLM fails (HTTP error, timeout, invalid or
    %   inconsistent JSON) | REASON: requirement 3 (emergency fallback) |
    %   DISCARDED ALTERNATIVE: LLM+LDA voting (the LLM would stop being the main classifier)
    %
    % DECISIÓN: onCleanup envía '#R' y cierra recursos | RAZÓN: con Ctrl+C o un error la
    %   prótesis queda en una postura segura y el Myo se libera | ALTERNATIVA DESCARTADA:
    %   limpieza solo al final normal del bucle
    % DECISION: onCleanup sends '#R' and closes resources | REASON: on Ctrl+C or an error
    %   the prosthesis ends in a safe pose and the Myo is released |
    %   DISCARDED ALTERNATIVE: cleanup only at the normal end of the loop
    %
    % DECISIÓN: configuraciones inyectables por argumento (solo para pruebas) | RAZÓN: los
    %   tests usan transporte 'mock' y prótesis 'SIM' sin tocar los .mat del usuario |
    %   ALTERNATIVA DESCARTADA: que los tests sobrescriban config/*.mat
    % DECISION: configurations injectable by argument (tests only) | REASON: tests use the
    %   'mock' transport and 'SIM' prosthesis without touching the user's .mat files |
    %   DISCARDED ALTERNATIVE: tests overwriting config/*.mat
    %
    % Entradas (nombre-valor) / Inputs (name-value):
    %   'Source'           : 'myo' (defecto) | 'udp' | 'simulated'
    %   'MyoDevice'        : nombre o dirección BLE / BLE name or address ('Myo')
    %   'UdpPort'          : puerto UDP local / local UDP port (10001)
    %   'Period'           : periodo objetivo del ciclo en s / target cycle period (0.2)
    %   'WindowMs'         : ventana de análisis / analysis window (200)
    %   'Duration'         : duración máxima en s / max duration (Inf)
    %   'MaxCycles'        : número máximo de ciclos / max cycles (Inf)
    %   'OnCycle'          : @(info) -> logical; false detiene el bucle / false stops loop
    %   'Verbose'          : imprimir cada ciclo / print every cycle (true)
    %   'SimLabel'         : gesto simulado o 'auto' / simulated gesture or 'auto'
    %   'SimRealtime'      : simulación en tiempo real / real-time simulation (true)
    %   'LogDir'           : carpeta de logs / log folder (logs/)
    %   'LlmConfig', 'ProsthesisConfig', 'PromptConfig', 'Calibration' :
    %                        structs que sustituyen a los .mat (pruebas)
    %                        structs replacing the .mat files (tests)
    %
    % Salidas / Outputs:
    %   summary : struct con estadísticas de la sesión / session statistics
    %
    % Ejemplo / Example:
    %   main                                           % Myo real, config/*.mat
    %   main('Source', 'simulated', 'Duration', 30)    % sin hardware / no hardware
    %   s = main('Source', 'udp', 'MaxCycles', 100);

    root = fileparts(mfilename('fullpath'));
    add_project_paths(root);

    p = inputParser;
    addParameter(p, 'Source', 'myo');
    addParameter(p, 'MyoDevice', 'Myo');
    addParameter(p, 'UdpPort', 10001);
    addParameter(p, 'Period', 0.2);
    addParameter(p, 'WindowMs', 200);
    addParameter(p, 'Duration', Inf);
    addParameter(p, 'MaxCycles', Inf);
    addParameter(p, 'OnCycle', []);
    addParameter(p, 'Verbose', true);
    addParameter(p, 'SimLabel', 'auto');
    addParameter(p, 'SimRealtime', true);
    addParameter(p, 'LogDir', fullfile(root, 'logs'));
    addParameter(p, 'LlmConfig', []);
    addParameter(p, 'ProsthesisConfig', []);
    addParameter(p, 'PromptConfig', []);
    addParameter(p, 'Calibration', []);
    parse(p, varargin{:});
    opts = p.Results;

    % --- Configuración / configuration ---------------------------------------------------
    config_dir = fullfile(root, 'config');
    cfg_llm = load_config(opts.LlmConfig, fullfile(config_dir, 'server-llm.mat'), ...
        'server_llm');
    cfg_prosthesis = load_config(opts.ProsthesisConfig, ...
        fullfile(config_dir, 'server-prosthesis.mat'), 'server_prosthesis');
    prompt_llm = load_config(opts.PromptConfig, fullfile(config_dir, 'prompt-llm.mat'), ...
        'prompt_llm');
    calib = load_config(opts.Calibration, fullfile(config_dir, 'calibration.mat'), 'calib');

    if ~isfolder(opts.LogDir)
        mkdir(opts.LogDir);
    end
    stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    logger('config', 'file', fullfile(opts.LogDir, ['main_', stamp, '.log']));
    llm_log_path = llm_logger('init', opts.LogDir);

    if isfield(calib, 'is_default') && calib.is_default
        logger('WARN', 'main', ['Calibración GENÉRICA en uso: ejecute calibrate() / ', ...
            'GENERIC calibration in use: run calibrate()']);
    end

    prompt_llm.system_prompt_effective = compose_system_prompt(prompt_llm, calib);
    lda_model = train_lda(calib, 'Verbose', true);

    % --- Estado inicial / initial state ---------------------------------------------------
    send_input_llm('reset');
    smooth_command('reset');
    process_signals('reset');
    send_signals_prosthesis('reset');

    myo_interface.instance('source', opts.Source, 'device_name', opts.MyoDevice, ...
        'udp_port', opts.UdpPort, 'sim_label', opts.SimLabel, ...
        'sim_realtime', opts.SimRealtime);
    cleanup = onCleanup(@() shutdown(cfg_prosthesis)); %#ok<NASGU>

    img_opts = struct('width', prompt_llm.image.width, ...
        'height', prompt_llm.image.height, ...
        'render_mode', prompt_llm.image.render_mode, ...
        'rest_threshold', calib.thresholds.rest, ...
        'active_threshold', calib.thresholds.active);

    logger('INFO', 'main', ['Inicio / Start | fuente=%s | LLM %s puertos=[%s] modo=%s ', ...
        'timeout=%.2fs | prótesis=%s'], opts.Source, cfg_llm.ip, num2str(cfg_llm.ports), ...
        cfg_llm.mode, cfg_llm.timeout, cfg_prosthesis.protocol);

    stats = new_stats();
    prev_command = [];
    t_session = tic;
    cycle = 0;

    % --- Bucle principal / main loop ------------------------------------------------------
    while cycle < opts.MaxCycles && toc(t_session) < opts.Duration
        cycle = cycle + 1;
        t_cycle = tic;
        t_ms = round(1000 * toc(t_session));

        % 1) Adquisición / acquisition
        [emg_window, fs] = get_signals(opts.WindowMs);

        % 2) Procesamiento / processing
        [rms_norm, mav_norm, state, emg_filtered] = process_signals(emg_window, fs, calib);

        % 3) Rechazo de ruido / noise rejection
        [state, ~, noise_reason] = filter_noise(emg_window, emg_filtered, rms_norm, state);

        % 4) Payload ASCII + imagen / ASCII payload + image
        payload = build_payload(rms_norm, mav_norm, state, calib, prev_command, t_ms);
        img_path = generate_heatmap(rms_norm, state, t_ms, img_opts);

        % 5) LLM (OBLIGATORIO en cada ciclo / MANDATORY every cycle)
        [llm_response, port_used] = send_input_llm(cfg_llm, prompt_llm, payload, img_path);
        stats.llm_calls = stats.llm_calls + 1;

        % 6) Validación / validation
        llm_valid = false;
        failure_reason = llm_response.error;
        command = [];
        if llm_response.ok
            [parsed, parsed_ok, parse_error] = parse_llm_response(llm_response.content);
            if parsed_ok
                [llm_valid, failure_reason] = is_valid_response(parsed);
                if llm_valid
                    command = standardize_command(parsed, 'llm');
                end
            else
                failure_reason = parse_error;
            end
        end

        % 7) Fallback LDA de emergencia / emergency LDA fallback
        if ~llm_valid
            command = lda_fallback(lda_model, rms_norm, mav_norm, state, prev_command, calib);
            logger('WARN', 'main', 'Ciclo %d: fallback LDA (%s) / LDA fallback', cycle, ...
                failure_reason);
        end

        % 8) Suavizado temporal / temporal smoothing
        smoothed = smooth_command(command);

        % 9) Envío a la prótesis / send to the prosthesis
        [prosthesis_ok, ~, prosthesis_ms] = send_signals_prosthesis(cfg_prosthesis, ...
            smoothed, cycle);
        prev_command = smoothed;

        % Registro / logging
        cycle_ms = 1000 * toc(t_cycle);
        entry = struct('cycle', cycle, 't_ms', t_ms, 'state', state, ...
            'noise_reason', noise_reason, 'payload', payload, ...
            'llm_ok', llm_response.ok, 'llm_valid', llm_valid, ...
            'llm_error', failure_reason, 'llm_content', llm_response.content, ...
            'llm_latency_ms', llm_response.latency_ms, 'port', port_used, ...
            'attempts', llm_response.attempts, 'source', command.source, ...
            'command', command.command, 'action', command.action, ...
            'value', command.value, 'confidence', command.confidence, ...
            'smoothed_command', smoothed.command, 'smoothed_value', smoothed.value, ...
            'smoothing', smoothed.smoothing, 'prosthesis_ok', prosthesis_ok, ...
            'prosthesis_latency_ms', prosthesis_ms, 'cycle_ms', cycle_ms);
        llm_logger('log', entry);
        stats = update_stats(stats, entry);

        if opts.Verbose
            llm_text = sprintf('LLM %s %5.0f ms', port_text(port_used), ...
                llm_response.latency_ms);
            command_text = sprintf('%-3s %-7s %3d (%.2f) %-3s', command.command, ...
                command.action, round(command.value), command.confidence, ...
                upper(command.source));
            output_text = sprintf('-> %-3s %3d %-4s', smoothed.command, ...
                round(smoothed.value), smoothed.smoothing);
            fprintf('[%s] #%-5d %-10s | %s | %s | %s | prot %s | %4.0f ms\n', ...
                char(datetime('now', 'Format', 'HH:mm:ss.SSS')), cycle, state, ...
                llm_text, command_text, output_text, ok_text(prosthesis_ok), cycle_ms);
        end

        if ~isempty(opts.OnCycle)
            info = entry;
            info.emg_window = emg_window;
            info.emg_filtered = emg_filtered;
            info.rms = rms_norm;
            info.mav = mav_norm;
            info.command_struct = command;
            info.smoothed_struct = smoothed;
            info.img_path = img_path;
            info.fs = fs;
            keep_running = opts.OnCycle(info);
            if ~keep_running
                logger('INFO', 'main', 'Detenido por OnCycle / Stopped by OnCycle');
                break;
            end
        end

        % 10) Espera hasta el siguiente ciclo / wait for the next cycle
        pause(max(0, opts.Period - toc(t_cycle)));
    end

    summary = finalize_stats(stats, toc(t_session), llm_log_path, prev_command);
    logger('INFO', 'main', ['Fin / End | ciclos=%d | LLM válido=%d | fallback=%d | ', ...
        'ciclo medio=%.0f ms'], summary.cycles, summary.llm_valid, ...
        summary.fallback_count, summary.mean_cycle_ms);
end

% ===========================================================================================
function command = lda_fallback(lda_model, rms_norm, mav_norm, state, prev_command, calib)
    % LDA_FALLBACK Comando de emergencia cuando el LLM falla (mismas reglas que el prompt).
    % LDA_FALLBACK Emergency command when the LLM fails (same rules as the prompt).
    %
    % DECISIÓN: reglas de reposo/ruido/gestos antes que el LDA | RAZÓN: el LDA solo conoce
    %   5 dedos; sin estas reglas convertiría el reposo o un puño en un dedo |
    %   ALTERNATIVA DESCARTADA: LDA para todo (movimientos erróneos en reposo)
    % DECISION: rest/noise/gesture rules before the LDA | REASON: the LDA only knows
    %   5 fingers; without these rules it would turn rest or a fist into a finger |
    %   DISCARDED ALTERNATIVE: LDA for everything (wrong moves at rest)
    rest_threshold = calib.thresholds.rest;

    if strcmp(state, 'NOISE')
        command = hold_previous(prev_command, 0.5);
        return;
    end
    if strcmp(state, 'REST') || max(rms_norm) < rest_threshold
        command = make_command('#R', 'rest', 0.9, [], 0);
        return;
    end

    [is_composite, gesture, channels, confidence] = is_composite_gesture(rms_norm);
    if is_composite && ~isempty(gesture)
        value = rms_to_value(rms_norm, gesture, 'gesture', [], channels);
        command = make_command(gesture, 'gesture', confidence, channels, value);
        return;
    end
    if is_composite || strcmp(state, 'TRANSITION')
        command = hold_previous(prev_command, 0.5);
        return;
    end

    [label, confidence] = lda_classify(lda_model, [rms_norm, mav_norm]);
    if isempty(label)
        command = hold_previous(prev_command, 0.4);
        return;
    end
    info = label_to_finger(label);
    class_idx = find(strcmp(calib.class_names, label), 1);
    channels = calib.top_channels(class_idx, :);
    [~, order] = sort(rms_norm(channels), 'descend');
    channels = channels(order);
    value = rms_to_value(rms_norm, info.command, 'flex', [], channels);
    command = make_command(info.command, 'flex', confidence, channels, value);
end

% -------------------------------------------------------------------------------------------
function command = hold_previous(prev_command, confidence)
    % HOLD_PREVIOUS Mantiene el comando previo o pasa a reposo si no existe.
    % HOLD_PREVIOUS Holds the previous command or goes to rest if there is none.
    if isempty(prev_command) || strcmp(prev_command.command, '#R')
        command = make_command('#R', 'rest', confidence, [], 0);
    else
        command = make_command(prev_command.command, 'hold', confidence, [], ...
            prev_command.value);
    end
end

% -------------------------------------------------------------------------------------------
function command = make_command(code, action, confidence, channels, value)
    % MAKE_COMMAND Struct de comando del fallback (source = 'lda').
    % MAKE_COMMAND Fallback command struct (source = 'lda').
    info = label_to_finger(code);
    command = struct('command', code, 'finger', info.finger, 'action', action, ...
        'confidence', double(confidence), 'trigger_channels', double(channels(:)'), ...
        'value', round(double(value)), 'source', 'lda');
end

% -------------------------------------------------------------------------------------------
function command = standardize_command(parsed, source)
    % STANDARDIZE_COMMAND Deja solo los campos del contrato con tipos fijos.
    % STANDARDIZE_COMMAND Keeps only the contract fields with fixed types.
    command = struct('command', char(parsed.command), 'finger', char(parsed.finger), ...
        'action', char(parsed.action), 'confidence', double(parsed.confidence), ...
        'trigger_channels', double(parsed.trigger_channels(:)'), ...
        'value', round(double(parsed.value)), 'source', source);
end

% -------------------------------------------------------------------------------------------
function text = compose_system_prompt(prompt_llm, calib)
    % COMPOSE_SYSTEM_PROMPT System prompt + contexto de calibración del usuario.
    % COMPOSE_SYSTEM_PROMPT System prompt + user calibration context.
    %
    % DECISIÓN: añadir la calibración una vez al arrancar | RAZÓN: el prefijo queda fijo
    %   durante la sesión y LM Studio reutiliza su caché KV | ALTERNATIVA DESCARTADA:
    %   enviarla en cada payload (más tokens por ciclo)
    % DECISION: append the calibration once at startup | REASON: the prefix stays fixed
    %   for the session and LM Studio reuses its KV cache | DISCARDED ALTERNATIVE: sending
    %   it in every payload (more tokens per cycle)
    text = prompt_llm.system_prompt;
    if ~isfield(prompt_llm, 'calibration_template') || isempty(calib) || ...
            ~isfield(calib, 'profiles')
        return;
    end

    is_spanish = strcmpi(prompt_llm.language, 'es');
    if calib.is_default
        default_text = choose(is_spanish, 'sí', 'yes');
    else
        default_text = choose(is_spanish, 'no', 'no');
    end

    tops = cell(1, numel(calib.class_names));
    rows = cell(1, numel(calib.class_names));
    for k = 1:numel(calib.class_names)
        info = label_to_finger(calib.class_names{k});
        tops{k} = sprintf('%s=%d+%d', info.finger, calib.top_channels(k, 1), ...
            calib.top_channels(k, 2));
        rows{k} = sprintf('  %s (%s): %s', info.finger, info.command, ...
            strtrim(sprintf('%.2f ', calib.profiles(k, :))));
    end

    rendered = prompt_llm.calibration_template;
    rendered = strrep(rendered, '{{USER_ID}}', calib.user_id);
    rendered = strrep(rendered, '{{CALIB_DATE}}', calib.created);
    rendered = strrep(rendered, '{{IS_DEFAULT}}', default_text);
    rendered = strrep(rendered, '{{CV_ACCURACY}}', sprintf('%.0f%%', 100 * calib.cv_accuracy));
    rendered = strrep(rendered, '{{TOP_CHANNELS}}', strjoin(tops, ', '));
    rendered = strrep(rendered, '{{PROFILE_TABLE}}', strjoin(rows, newline));

    text = [text, newline, newline, rendered];
end

% -------------------------------------------------------------------------------------------
function value = choose(condition, if_true, if_false)
    % CHOOSE Operador ternario. / Ternary operator.
    if condition
        value = if_true;
    else
        value = if_false;
    end
end

% -------------------------------------------------------------------------------------------
function shutdown(cfg_prosthesis)
    % SHUTDOWN Postura segura, liberación del Myo y cierre de logs.
    % SHUTDOWN Safe pose, Myo release and log closing.
    safe_code = '#R';
    if isfield(cfg_prosthesis, 'safe_command') && ~isempty(cfg_prosthesis.safe_command)
        safe_code = cfg_prosthesis.safe_command;
    end
    try
        safe = make_command(safe_code, 'rest', 1.0, [], 0);
        safe.source = 'safety';
        send_signals_prosthesis(cfg_prosthesis, safe, -1);
    catch err
        fprintf(2, 'No se pudo enviar el comando seguro / Safe command failed: %s\n', ...
            err.message);
    end
    try
        myo_interface.instance('reset');
    catch err
        fprintf(2, 'Error al liberar el Myo / Myo release error: %s\n', err.message);
    end
    generate_heatmap('reset');
    llm_logger('summary');
    llm_logger('close');
    logger('close');
end

% -------------------------------------------------------------------------------------------
function cfg = load_config(override, file_path, variable)
    % LOAD_CONFIG Usa el struct inyectado o carga la variable del .mat.
    % LOAD_CONFIG Uses the injected struct or loads the variable from the .mat.
    if ~isempty(override)
        cfg = override;
        return;
    end
    if ~isfile(file_path)
        error('main:config', ['Falta %s: ejecute setup / Missing %s: run setup'], ...
            file_path, file_path);
    end
    loaded = load(file_path, variable);
    cfg = loaded.(variable);
end

% -------------------------------------------------------------------------------------------
function add_project_paths(root)
    % ADD_PROJECT_PATHS Añade las carpetas de código al path. / Adds code folders to path.
    folders = {'config', 'acquisition', 'processing', 'llm', 'prosthesis', 'utils', 'tests'};
    for k = 1:numel(folders)
        addpath(fullfile(root, folders{k}));
    end
end

% -------------------------------------------------------------------------------------------
function stats = new_stats()
    % NEW_STATS Contadores de la sesión. / Session counters.
    stats = struct('cycles', 0, 'llm_calls', 0, 'llm_http_ok', 0, 'llm_valid', 0, ...
        'fallback_count', 0, 'held_count', 0, 'prosthesis_ok', 0, ...
        'cycle_ms_sum', 0, 'cycle_ms_max', 0, 'llm_ms_sum', 0, ...
        'ports', [], 'port_counts', []);
end

% -------------------------------------------------------------------------------------------
function stats = update_stats(stats, entry)
    % UPDATE_STATS Acumula un ciclo. / Accumulates one cycle.
    stats.cycles = stats.cycles + 1;
    stats.llm_http_ok = stats.llm_http_ok + double(entry.llm_ok);
    stats.llm_valid = stats.llm_valid + double(entry.llm_valid);
    stats.fallback_count = stats.fallback_count + double(strcmp(entry.source, 'lda'));
    stats.held_count = stats.held_count + double(strcmp(entry.smoothing, 'held'));
    stats.prosthesis_ok = stats.prosthesis_ok + double(entry.prosthesis_ok);
    stats.cycle_ms_sum = stats.cycle_ms_sum + entry.cycle_ms;
    stats.cycle_ms_max = max(stats.cycle_ms_max, entry.cycle_ms);
    if isfinite(entry.llm_latency_ms)
        stats.llm_ms_sum = stats.llm_ms_sum + entry.llm_latency_ms;
    end
    if isfinite(entry.port)
        idx = find(stats.ports == entry.port, 1);
        if isempty(idx)
            stats.ports(end + 1) = entry.port;
            stats.port_counts(end + 1) = 0;
            idx = numel(stats.ports);
        end
        stats.port_counts(idx) = stats.port_counts(idx) + 1;
    end
end

% -------------------------------------------------------------------------------------------
function summary = finalize_stats(stats, duration_s, log_path, last_command)
    % FINALIZE_STATS Resumen final de la sesión. / Final session summary.
    n = max(stats.cycles, 1);
    summary = struct('cycles', stats.cycles, 'llm_calls', stats.llm_calls, ...
        'llm_http_ok', stats.llm_http_ok, 'llm_valid', stats.llm_valid, ...
        'fallback_count', stats.fallback_count, 'held_count', stats.held_count, ...
        'prosthesis_ok', stats.prosthesis_ok, ...
        'mean_cycle_ms', stats.cycle_ms_sum / n, 'max_cycle_ms', stats.cycle_ms_max, ...
        'mean_llm_ms', stats.llm_ms_sum / n, 'ports', stats.ports, ...
        'port_counts', stats.port_counts, 'duration_s', duration_s, ...
        'llm_log', log_path, 'last_command', last_command);
end

% -------------------------------------------------------------------------------------------
function text = port_text(port)
    % PORT_TEXT Puerto como texto de ancho fijo. / Port as fixed-width text.
    if isfinite(port)
        text = sprintf('%5d', port);
    else
        text = ' ----';
    end
end

% -------------------------------------------------------------------------------------------
function text = ok_text(flag)
    % OK_TEXT 'OK' o 'FAIL'.
    if flag
        text = 'OK  ';
    else
        text = 'FAIL';
    end
end
