function [rms_values, mav_values, state, emg_filtered, rms_raw, mav_raw] = ...
        process_signals(emg_window, fs, calib)
    % PROCESS_SIGNALS Procesa la ventana de EMG: filtra, calcula RMS/MAV y detecta estado.
    %
    % PROCESS_SIGNALS Processes the EMG window: filters, computes RMS/MAV and detects
    %   the state.
    %
    % Cadena / Chain:
    %   1. Quitar DC / remove DC
    %   2. Pasa-banda Butterworth orden 4, 20-95 Hz (fase cero, filtfilt)
    %      4th-order Butterworth band-pass, 20-95 Hz (zero phase, filtfilt)
    %   3. Notch de red eléctrica (60 Hz en Ecuador, configurable en calib.powerline_hz)
    %      Powerline notch (60 Hz in Ecuador, configurable in calib.powerline_hz)
    %   4. RMS y MAV por canal / per-channel RMS and MAV
    %   5. Normalización con calibración / calibration-based normalization
    %   6. Estado / state: REST (<0.15), TRANSITION, ACTIVE (>=0.40) sobre el máximo
    %
    % DECISIÓN: filtro Butterworth orden 4 | RAZÓN: buen balance entre atenuación y fase,
    %   respuesta plana en banda pasante | ALTERNATIVA DESCARTADA: Chebyshev (ripple en
    %   banda pasante)
    % DECISION: 4th-order Butterworth filter | REASON: good trade-off between attenuation
    %   and phase, flat passband | DISCARDED ALTERNATIVE: Chebyshev (passband ripple)
    %
    % DECISIÓN: 20-95 Hz con fs = 200 Hz | RAZÓN: el Myo muestrea a 200 Hz (Nyquist 100 Hz);
    %   <20 Hz es artefacto de movimiento | ALTERNATIVA DESCARTADA: 20-450 Hz (imposible
    %   con fs = 200 Hz)
    % DECISION: 20-95 Hz with fs = 200 Hz | REASON: the Myo samples at 200 Hz (Nyquist
    %   100 Hz); <20 Hz is motion artifact | DISCARDED ALTERNATIVE: 20-450 Hz (impossible
    %   with fs = 200 Hz)
    %
    % DECISIÓN: filtfilt por ventana (fase cero) | RAZÓN: entre ventanas pasa el tiempo del
    %   LLM, así que no son contiguas y no tiene sentido mantener el estado del filtro |
    %   ALTERNATIVA DESCARTADA: filter() con estado inicial persistente (transitorios
    %   erróneos al saltar muestras)
    % DECISION: per-window filtfilt (zero phase) | REASON: LLM time passes between windows,
    %   so they are not contiguous and keeping filter state makes no sense |
    %   DISCARDED ALTERNATIVE: filter() with persistent initial state (wrong transients
    %   when samples are skipped)
    %
    % DECISIÓN: estado basado en el MÁXIMO canal | RAZÓN: un solo dedo activa pocos canales;
    %   la media lo diluiría | ALTERNATIVA DESCARTADA: media de los 8 canales
    % DECISION: state based on the MAXIMUM channel | REASON: a single finger activates few
    %   channels; the mean would dilute it | DISCARDED ALTERNATIVE: mean of the 8 channels
    %
    % Entradas / Inputs:
    %   emg_window : matriz Nx8 (muestras x canales) / Nx8 matrix (samples x channels)
    %                o 'reset' para vaciar la caché de filtros / or 'reset' to clear cache
    %   fs         : frecuencia de muestreo en Hz (200) / sampling rate in Hz (200)
    %   calib      : struct de calibración ([] = sin normalizar) / calibration struct
    %
    % Salidas / Outputs:
    %   rms_values   : RMS 1x8 (normalizado si hay calibración) / (normalized if calibrated)
    %   mav_values   : MAV 1x8 (normalizado si hay calibración) / (normalized if calibrated)
    %   state        : 'REST' | 'TRANSITION' | 'ACTIVE' | 'UNCALIBRATED'
    %   emg_filtered : matriz Nx8 filtrada / filtered Nx8 matrix
    %   rms_raw      : RMS 1x8 sin normalizar / unnormalized RMS
    %   mav_raw      : MAV 1x8 sin normalizar / unnormalized MAV
    %
    % Ejemplo / Example:
    %   [rms_n, mav_n, state] = process_signals(emg_window, 200, calib);

    persistent filter_cache

    if ischar(emg_window) || isstring(emg_window)
        if strcmpi(emg_window, 'reset')
            filter_cache = [];
            rms_values = [];
            mav_values = [];
            state = '';
            emg_filtered = [];
            rms_raw = [];
            mav_raw = [];
            return;
        end
        error('process_signals:badInput', 'Entrada no válida / Invalid input');
    end

    if nargin < 2 || isempty(fs)
        fs = 200;
    end
    if nargin < 3
        calib = [];
    end

    x = double(emg_window);
    if size(x, 2) ~= 8 && size(x, 1) == 8
        x = x';
    end
    if size(x, 2) ~= 8
        error('process_signals:size', ...
            'Se esperaban 8 canales / 8 channels expected (got %dx%d)', size(x));
    end
    x(~isfinite(x)) = 0;
    x = x - mean(x, 1);

    powerline_hz = 60;
    if isstruct(calib) && isfield(calib, 'powerline_hz') && ~isempty(calib.powerline_hz)
        powerline_hz = calib.powerline_hz;
    end

    % Caché de filtros por (fs, red) / filter cache keyed by (fs, powerline)
    if isempty(filter_cache) || filter_cache.fs ~= fs || ...
            filter_cache.powerline_hz ~= powerline_hz
        filter_cache = design_filters(fs, powerline_hz);
    end
    f = filter_cache;

    y = x;
    if size(y, 1) > f.min_length
        y = filtfilt(f.sos, f.g, y);
        if f.has_notch
            y = filtfilt(f.notch_b, f.notch_a, y);
        end
    else
        logger('WARN', 'process_signals', ...
            'Ventana corta (%d muestras); sin filtrar / Short window; unfiltered', size(y, 1));
    end
    emg_filtered = y;

    rms_raw = sqrt(mean(y .^ 2, 1));
    mav_raw = mean(abs(y), 1);

    has_calibration = isstruct(calib) && isfield(calib, 'rest_rms');
    if ~has_calibration
        rms_values = rms_raw;
        mav_values = mav_raw;
        state = 'UNCALIBRATED';
        return;
    end

    rms_values = normalize_signals(rms_raw, calib, 'rms');
    mav_values = normalize_signals(mav_raw, calib, 'mav');

    rest_threshold = 0.15;
    active_threshold = 0.40;
    if isfield(calib, 'thresholds')
        rest_threshold = calib.thresholds.rest;
        active_threshold = calib.thresholds.active;
    end

    peak = max(rms_values);
    if peak >= active_threshold
        state = 'ACTIVE';
    elseif peak < rest_threshold
        state = 'REST';
    else
        state = 'TRANSITION';
    end
end

% -------------------------------------------------------------------------------------------
function f = design_filters(fs, powerline_hz)
    % DESIGN_FILTERS Diseña el pasa-banda (SOS) y el notch (biquad) para fs dado.
    % DESIGN_FILTERS Designs the band-pass (SOS) and the notch (biquad) for the given fs.
    %
    % DECISIÓN: notch biquad diseñado a mano | RAZÓN: iirnotch pertenece a DSP System
    %   Toolbox, que no está permitido | ALTERNATIVA DESCARTADA: iirnotch
    % DECISION: hand-designed biquad notch | REASON: iirnotch belongs to DSP System
    %   Toolbox, which is not allowed | DISCARDED ALTERNATIVE: iirnotch
    nyquist = fs / 2;
    low_hz = 20;
    high_hz = min(95, 0.95 * nyquist);

    [z, p, k] = butter(4, [low_hz, high_hz] / nyquist, 'bandpass');
    [sos, g] = zp2sos(z, p, k);

    f = struct();
    f.fs = fs;
    f.powerline_hz = powerline_hz;
    f.sos = sos;
    f.g = g;
    f.min_length = 3 * (2 * size(sos, 1)) + 1;

    f.has_notch = powerline_hz > low_hz && powerline_hz < high_hz;
    w0 = 2 * pi * powerline_hz / fs;
    r = 0.95;                                     % ancho de banda / bandwidth
    b = [1, -2 * cos(w0), 1];
    a = [1, -2 * r * cos(w0), r ^ 2];
    f.notch_b = b * (sum(a) / sum(b));            % ganancia unitaria en DC / unity DC gain
    f.notch_a = a;
end
