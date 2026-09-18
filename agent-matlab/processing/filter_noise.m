function [state_out, is_clean, reason] = filter_noise(emg_raw, emg_filtered, rms_values, ...
        state_in, opts)
    % FILTER_NOISE Rechaza ventanas con ruido (saturación, canal muerto, artefacto de
    %   movimiento, datos no finitos) y marca el estado como 'NOISE'.
    %
    % FILTER_NOISE Rejects noisy windows (saturation, dead channel, motion artifact,
    %   non-finite data) and flags the state as 'NOISE'.
    %
    % Comprobaciones / Checks:
    %   1. Datos no finitos / non-finite data
    %   2. Saturación: fracción de muestras con |x| >= 127 (int8) > 5 % en algún canal
    %      Saturation: fraction of samples with |x| >= 127 (int8) > 5 % on any channel
    %   3. Canal plano (desconectado o buffer vacío): desviación estándar ~ 0
    %      Flat channel (disconnected or empty buffer): standard deviation ~ 0
    %   4. Artefacto de movimiento: energía filtrada / energía cruda < 0.20 con señal
    %      apreciable (casi toda la energía está por debajo de 20 Hz)
    %      Motion artifact: filtered energy / raw energy < 0.20 with a noticeable signal
    %      (almost all energy lies below 20 Hz)
    %
    % DECISIÓN: la ventana ruidosa NO se descarta, se envía al LLM con STATE:NOISE |
    %   RAZÓN: la invocación al LLM es obligatoria en cada ciclo y el prompt tiene una regla
    %   explícita para NOISE (mantener PREV) | ALTERNATIVA DESCARTADA: saltar el ciclo
    %   (incumple el requisito de invocación obligatoria)
    % DECISION: a noisy window is NOT dropped; it is sent to the LLM with STATE:NOISE |
    %   REASON: the LLM call is mandatory every cycle and the prompt has an explicit NOISE
    %   rule (hold PREV) | DISCARDED ALTERNATIVE: skipping the cycle (breaks the mandatory
    %   call requirement)
    %
    % DECISIÓN: relación de energías en lugar de FFT | RAZÓN: con 40 muestras la
    %   resolución espectral es de 5 Hz y la FFT no aporta más; la relación usa datos ya
    %   calculados | ALTERNATIVA DESCARTADA: periodograma por ventana (más costoso)
    % DECISION: energy ratio instead of FFT | REASON: with 40 samples the spectral
    %   resolution is 5 Hz and an FFT adds nothing; the ratio reuses computed data |
    %   DISCARDED ALTERNATIVE: per-window periodogram (more expensive)
    %
    % Entradas / Inputs:
    %   emg_raw      : matriz Nx8 cruda / raw Nx8 matrix
    %   emg_filtered : matriz Nx8 filtrada (de process_signals) / filtered Nx8 matrix
    %   rms_values   : RMS 1x8 normalizado / normalized 1x8 RMS
    %   state_in     : estado de process_signals / state from process_signals
    %   opts         : (opcional / optional) saturation_level, max_saturation_ratio,
    %                  min_filtered_ratio, min_raw_rms, flat_std
    %
    % Salidas / Outputs:
    %   state_out : state_in o 'NOISE' / state_in or 'NOISE'
    %   is_clean  : true si la ventana es válida / true if the window is valid
    %   reason    : texto con el motivo del rechazo ('' si limpia) / rejection reason
    %
    % Ejemplo / Example:
    %   [state, ok, why] = filter_noise(emg, emg_f, rms_n, state);

    if nargin < 5 || isempty(opts)
        opts = struct();
    end
    saturation_level = get_opt(opts, 'saturation_level', 127);
    max_saturation_ratio = get_opt(opts, 'max_saturation_ratio', 0.05);
    min_filtered_ratio = get_opt(opts, 'min_filtered_ratio', 0.20);
    min_raw_rms = get_opt(opts, 'min_raw_rms', 5);
    flat_std = get_opt(opts, 'flat_std', 1e-6);

    state_out = state_in;
    is_clean = true;
    reason = '';

    x = double(emg_raw);

    if isempty(x) || any(~isfinite(x(:))) || any(~isfinite(rms_values(:)))
        [state_out, is_clean, reason] = reject('non-finite data');
        return;
    end

    saturation_ratio = mean(abs(x) >= saturation_level, 1);
    bad = find(saturation_ratio > max_saturation_ratio);
    if ~isempty(bad)
        [state_out, is_clean, reason] = reject(sprintf('saturation CH%s', ...
            channel_list(bad)));
        return;
    end

    channel_std = std(x, 0, 1);
    bad = find(channel_std < flat_std);
    if ~isempty(bad)
        [state_out, is_clean, reason] = reject(sprintf('flat channel CH%s', ...
            channel_list(bad)));
        return;
    end

    centered = x - mean(x, 1);
    raw_energy = mean(centered .^ 2, 1);
    filtered_energy = mean(double(emg_filtered) .^ 2, 1);
    ratio = filtered_energy ./ max(raw_energy, eps);
    bad = find(sqrt(raw_energy) > min_raw_rms & ratio < min_filtered_ratio);
    if ~isempty(bad)
        [state_out, is_clean, reason] = reject(sprintf('motion artifact CH%s', ...
            channel_list(bad)));
        return;
    end
end

% -------------------------------------------------------------------------------------------
function [state_out, is_clean, reason] = reject(why)
    % REJECT Marca la ventana como ruidosa y lo registra.
    % REJECT Flags the window as noisy and logs it.
    state_out = 'NOISE';
    is_clean = false;
    reason = why;
    logger('DEBUG', 'filter_noise', 'Ventana rechazada / Window rejected: %s', why);
end

% -------------------------------------------------------------------------------------------
function text = channel_list(channels)
    % CHANNEL_LIST Convierte [1 3] en '1,3'. / Converts [1 3] into '1,3'.
    text = strjoin(arrayfun(@num2str, channels, 'UniformOutput', false), ',');
end

% -------------------------------------------------------------------------------------------
function value = get_opt(opts, name, default_value)
    % GET_OPT Lee un campo opcional. / Reads an optional field.
    if isfield(opts, name) && ~isempty(opts.(name))
        value = opts.(name);
    else
        value = default_value;
    end
end
