function calib = calibrate(varargin)
    % CALIBRATE Calibración por usuario: reposo, contracciones por dedo y MVC.
    %
    % CALIBRATE Per-user calibration: rest, per-finger contractions and MVC.
    %
    % Protocolo / Protocol:
    %   1. Reposo (RestSeconds)                       -> rest_rms, rest_mav
    %   2. Por cada clase {pulgar, D2, D3, D4, D5}, Reps repeticiones de HoldSeconds
    %      For each class, Reps repetitions of HoldSeconds
    %   3. MVC de puño (#C) y de mano abierta (#O)    -> mvc_rms, mvc_mav
    %      Fist (#C) and open-hand (#O) MVC
    %   4. Normalización, perfiles por clase, 2 canales dominantes por dedo
    %      Normalization, class profiles, 2 dominant channels per finger
    %   5. Validación cruzada del LDA y guardado en config/calibration.mat
    %      LDA cross-validation and saving to config/calibration.mat
    %
    % DECISIÓN: MVC = máximo por canal de las medianas de cada tarea | RAZÓN: la mediana
    %   descarta picos transitorios y el máximo entre tareas cubre tanto flexores como
    %   extensores | ALTERNATIVA DESCARTADA: máximo absoluto (sensible a artefactos)
    % DECISION: MVC = per-channel maximum of each task's median | REASON: the median drops
    %   transient spikes and the maximum across tasks covers both flexors and extensors |
    %   DISCARDED ALTERNATIVE: absolute maximum (sensitive to artifacts)
    %
    % DECISIÓN: descartar los primeros 0.5 s de cada contracción | RAZÓN: la transición
    %   reposo->contracción contamina las características | ALTERNATIVA DESCARTADA: usar
    %   toda la ventana (clases menos separables)
    % DECISION: discard the first 0.5 s of each contraction | REASON: the rest->contraction
    %   transition contaminates the features | DISCARDED ALTERNATIVE: using the whole
    %   window (less separable classes)
    %
    % DECISIÓN: la fuente 'simulated' genera los datos sin esperar en tiempo real |
    %   RAZÓN: permite crear una calibración por defecto reproducible en setup.m |
    %   ALTERNATIVA DESCARTADA: calibración por defecto escrita a mano (no coherente con el
    %   procesamiento real)
    % DECISION: the 'simulated' source generates data without real-time waiting |
    %   REASON: allows setup.m to create a reproducible default calibration |
    %   DISCARDED ALTERNATIVE: hand-written default calibration (not consistent with the
    %   real processing chain)
    %
    % Entradas (nombre-valor) / Inputs (name-value):
    %   'Source'       : 'myo' (defecto) | 'udp' | 'simulated'
    %   'UserId'       : identificador del usuario / user identifier ('user01')
    %   'Reps'         : repeticiones por clase / repetitions per class (5)
    %   'HoldSeconds'  : duración de cada contracción / contraction length (3)
    %   'RelaxSeconds' : descanso entre repeticiones / rest between reps (2)
    %   'RestSeconds'  : duración del reposo inicial / initial rest length (5)
    %   'WindowMs'     : ventana de análisis / analysis window (200)
    %   'PowerlineHz'  : frecuencia de red / powerline frequency (60)
    %   'Interactive'  : pedir Enter antes de cada paso / ask Enter before each step (true)
    %   'IsDefault'    : marca la calibración como genérica / flags a generic calibration
    %   'SavePath'     : ruta de salida / output path (config/calibration.mat)
    %   'Seed'         : semilla para la fuente simulada / seed for the simulated source
    %   'MyoDevice'    : nombre BLE del Myo / Myo BLE name ('Myo')
    %   'UdpPort'      : puerto UDP / UDP port (10001)
    %
    % Salidas / Outputs:
    %   calib : struct guardado en config/calibration.mat / struct saved to calibration.mat
    %
    % Ejemplo / Example:
    %   calib = calibrate('Source', 'myo', 'UserId', 'daniel', 'Reps', 5);
    %   calib = calibrate('Source', 'simulated', 'Interactive', false);

    root = fileparts(fileparts(mfilename('fullpath')));

    p = inputParser;
    addParameter(p, 'Source', 'myo');
    addParameter(p, 'UserId', 'user01');
    addParameter(p, 'Reps', 5);
    addParameter(p, 'HoldSeconds', 3);
    addParameter(p, 'RelaxSeconds', 2);
    addParameter(p, 'RestSeconds', 5);
    addParameter(p, 'WindowMs', 200);
    addParameter(p, 'PowerlineHz', 60);
    addParameter(p, 'Interactive', true);
    addParameter(p, 'IsDefault', false);
    addParameter(p, 'SavePath', fullfile(root, 'config', 'calibration.mat'));
    addParameter(p, 'Seed', []);
    addParameter(p, 'MyoDevice', 'Myo');
    addParameter(p, 'UdpPort', 10001);
    parse(p, varargin{:});
    opts = p.Results;
    opts.Source = lower(char(opts.Source));

    fs = myo_interface.FS;
    n_window = round(opts.WindowMs / 1000 * fs);
    discard_s = 0.5;
    class_names = {'pulgar', 'D2', 'D3', 'D4', 'D5'};
    is_simulated = strcmp(opts.Source, 'simulated');
    filter_only = struct('powerline_hz', opts.PowerlineHz);

    if ~isempty(opts.Seed)
        previous_rng = rng;
        rng(opts.Seed);
        restore_rng = onCleanup(@() rng(previous_rng));
    end

    if ~is_simulated
        myo_interface.instance('source', opts.Source, 'device_name', opts.MyoDevice, ...
            'udp_port', opts.UdpPort);
    end

    steps = build_steps(class_names, opts);
    logger('INFO', 'calibrate', 'Calibración de %s (%d pasos) / Calibrating %s (%d steps)', ...
        opts.UserId, numel(steps), opts.UserId, numel(steps));

    rms_list = zeros(0, 8);
    mav_list = zeros(0, 8);
    step_labels = {};
    step_kinds = {};
    for s = 1:numel(steps)
        step = steps(s);
        announce(step, s, numel(steps), opts, is_simulated);

        windows = acquire_windows(step, opts, n_window, discard_s, is_simulated);
        for w = 1:numel(windows)
            [~, ~, ~, ~, rms_raw, mav_raw] = process_signals(windows{w}, fs, filter_only);
            rms_list(end + 1, :) = rms_raw; %#ok<AGROW>
            mav_list(end + 1, :) = mav_raw; %#ok<AGROW>
            step_labels{end + 1, 1} = step.label; %#ok<AGROW>
            step_kinds{end + 1, 1} = step.kind; %#ok<AGROW>
        end

        if ~is_simulated && strcmp(step.kind, 'class') && opts.RelaxSeconds > 0
            fprintf('   Relaje / Relax (%.0f s)\n', opts.RelaxSeconds);
            pause(opts.RelaxSeconds);
        end
    end

    calib = build_calibration(rms_list, mav_list, step_labels, step_kinds, ...
        class_names, opts, fs);

    lda_model = train_lda(calib, 'Verbose', true);
    calib.cv_accuracy = lda_model.cv_accuracy;
    if calib.cv_accuracy < 0.80 && ~opts.IsDefault
        logger('WARN', 'calibrate', ['Precisión CV baja (%.0f%%): repita la calibración / ', ...
            'Low CV accuracy: repeat the calibration'], 100 * calib.cv_accuracy);
    end

    save_folder = fileparts(opts.SavePath);
    if ~isempty(save_folder) && ~isfolder(save_folder)
        mkdir(save_folder);
    end
    save(opts.SavePath, 'calib');
    logger('INFO', 'calibrate', 'Calibración guardada / saved: %s (CV=%.1f%%)', ...
        opts.SavePath, 100 * calib.cv_accuracy);
    print_profile(calib);
end

% -------------------------------------------------------------------------------------------
function steps = build_steps(class_names, opts)
    % BUILD_STEPS Lista ordenada de tareas de calibración. / Ordered calibration tasks.
    names_es = containers.Map({'pulgar', 'D2', 'D3', 'D4', 'D5'}, ...
        {'Flexione el PULGAR', 'Flexione el INDICE', 'Flexione el MEDIO', ...
        'Flexione el ANULAR', 'Flexione el MENIQUE'});
    names_en = containers.Map({'pulgar', 'D2', 'D3', 'D4', 'D5'}, ...
        {'Flex the THUMB', 'Flex the INDEX finger', 'Flex the MIDDLE finger', ...
        'Flex the RING finger', 'Flex the LITTLE finger'});

    steps = struct('label', 'REST', 'kind', 'rest', 'seconds', opts.RestSeconds, ...
        'intensity', 1, 'text_es', 'Mantenga la mano RELAJADA', ...
        'text_en', 'Keep the hand RELAXED');
    for k = 1:numel(class_names)
        for r = 1:opts.Reps
            steps(end + 1) = struct('label', class_names{k}, 'kind', 'class', ...
                'seconds', opts.HoldSeconds, 'intensity', 0.9 + 0.2 * (r - 1) / ...
                max(opts.Reps - 1, 1), 'text_es', sprintf('%s (rep %d/%d)', ...
                names_es(class_names{k}), r, opts.Reps), 'text_en', ...
                sprintf('%s (rep %d/%d)', names_en(class_names{k}), r, opts.Reps)); %#ok<AGROW>
        end
    end
    steps(end + 1) = struct('label', '#C', 'kind', 'mvc', 'seconds', opts.HoldSeconds, ...
        'intensity', 1.2, 'text_es', 'Cierre el PUNO con FUERZA MAXIMA', ...
        'text_en', 'Close the FIST with MAXIMUM force');
    steps(end + 1) = struct('label', '#O', 'kind', 'mvc', 'seconds', opts.HoldSeconds, ...
        'intensity', 1.2, 'text_es', 'ABRA la mano con FUERZA MAXIMA', ...
        'text_en', 'OPEN the hand with MAXIMUM force');
end

% -------------------------------------------------------------------------------------------
function announce(step, index, total, opts, is_simulated)
    % ANNOUNCE Muestra la instrucción bilingüe y espera al usuario si procede.
    % ANNOUNCE Shows the bilingual instruction and waits for the user if needed.
    fprintf('\n[%d/%d] %s / %s  (%.1f s)\n', index, total, step.text_es, step.text_en, ...
        step.seconds);
    if is_simulated
        return;
    end
    if opts.Interactive
        input('   Pulse Enter para empezar / Press Enter to start... ', 's');
    end
    myo = myo_interface.instance();
    myo.vibrate(1);
    for c = 3:-1:1
        fprintf('   %d...\n', c);
        pause(1);
    end
    fprintf('   YA / GO\n');
end

% -------------------------------------------------------------------------------------------
function windows = acquire_windows(step, opts, n_window, discard_s, is_simulated)
    % ACQUIRE_WINDOWS Ventanas no solapadas de la tarea (reales o sintéticas).
    % ACQUIRE_WINDOWS Non-overlapping task windows (real or synthetic).
    window_s = opts.WindowMs / 1000;
    if strcmp(step.kind, 'rest')
        skip_s = 0;
    else
        skip_s = discard_s;
    end
    n_windows = max(1, floor((step.seconds - skip_s) / window_s));
    windows = cell(1, n_windows);

    if is_simulated
        for w = 1:n_windows
            windows{w} = myo_interface.synthetic_window(step.label, n_window, ...
                step.intensity);
        end
        return;
    end

    pause(skip_s);
    for w = 1:n_windows
        pause(window_s);
        windows{w} = get_signals(opts.WindowMs);
    end
end

% -------------------------------------------------------------------------------------------
function calib = build_calibration(rms_list, mav_list, labels, kinds, class_names, opts, fs)
    % BUILD_CALIBRATION Calcula referencias, características, perfiles y canales top.
    % BUILD_CALIBRATION Computes references, features, profiles and top channels.
    rest_mask = strcmp(kinds, 'rest');
    active_mask = ~rest_mask;
    if ~any(rest_mask) || ~any(active_mask)
        error('calibrate:data', 'Faltan datos de reposo o actividad / Missing data');
    end

    rest_rms = median(rms_list(rest_mask, :), 1);
    rest_mav = median(mav_list(rest_mask, :), 1);

    task_labels = unique(labels(active_mask), 'stable');
    task_rms = zeros(numel(task_labels), 8);
    task_mav = zeros(numel(task_labels), 8);
    for k = 1:numel(task_labels)
        mask = strcmp(labels, task_labels{k});
        task_rms(k, :) = median(rms_list(mask, :), 1);
        task_mav(k, :) = median(mav_list(mask, :), 1);
    end
    mvc_rms = max(max(task_rms, [], 1), rest_rms + 1e-3);
    mvc_mav = max(max(task_mav, [], 1), rest_mav + 1e-3);

    calib = struct();
    calib.version = 1;
    calib.user_id = char(opts.UserId);
    calib.created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    calib.source = opts.Source;
    calib.is_default = logical(opts.IsDefault);
    calib.fs = fs;
    calib.window_ms = opts.WindowMs;
    calib.powerline_hz = opts.PowerlineHz;
    calib.thresholds = struct('rest', 0.15, 'active', 0.40);
    calib.rest_rms = rest_rms;
    calib.mvc_rms = mvc_rms;
    calib.rest_mav = rest_mav;
    calib.mvc_mav = mvc_mav;
    calib.class_names = class_names;

    class_mask = ismember(labels, class_names);
    rms_norm = zeros(sum(class_mask), 8);
    mav_norm = zeros(sum(class_mask), 8);
    idx = find(class_mask);
    for k = 1:numel(idx)
        rms_norm(k, :) = normalize_signals(rms_list(idx(k), :), calib, 'rms');
        mav_norm(k, :) = normalize_signals(mav_list(idx(k), :), calib, 'mav');
    end
    calib.features = [rms_norm, mav_norm];
    calib.labels = labels(class_mask);

    calib.profiles = zeros(numel(class_names), 8);
    calib.top_channels = zeros(numel(class_names), 2);
    for k = 1:numel(class_names)
        mask = strcmp(calib.labels, class_names{k});
        calib.profiles(k, :) = mean(rms_norm(mask, :), 1);
        [~, order] = sort(calib.profiles(k, :), 'descend');
        calib.top_channels(k, :) = order(1:2);
    end
    calib.n_windows = size(calib.features, 1);
    calib.cv_accuracy = NaN;
end

% -------------------------------------------------------------------------------------------
function print_profile(calib)
    % PRINT_PROFILE Tabla de perfiles normalizados por clase. / Class profile table.
    fprintf('\nPerfil RMS normalizado / Normalized RMS profile\n');
    fprintf('%-8s %s  | top\n', 'clase', sprintf('  CH%d ', 1:8));
    for k = 1:numel(calib.class_names)
        fprintf('%-8s %s  | %d+%d\n', calib.class_names{k}, ...
            sprintf('%5.2f ', calib.profiles(k, :)), calib.top_channels(k, :));
    end
end
