function f = process_signals(emg, cfg)
% PROCESS_SIGNALS Filtra una ventana de EMG (N x 8) y calcula sus características.
%   f.filtered : ventana filtrada (N x 8)
%   f.rms_raw, f.mav_raw : RMS y MAV por canal sin normalizar
%   f.rms, f.mav         : RMS y MAV normalizados a [0,1]
%   f.state              : 'REST' | 'TRANSITION' | 'ACTIVE' | 'NOISE'
%   f.noise              : motivo del ruido ('' si la ventana está limpia)

s = cfg.signal;                                             % atajo a la configuración de la señal
x = double(emg);                                            % muestras como números reales
x = x - mean(x, 1);                                         % quita la componente continua de cada canal

nyquist = cfg.fs / 2;                                       % frecuencia máxima representable
[z, p, k] = butter(4, s.band_hz / nyquist, 'bandpass');     % Butterworth pasa-banda de orden 4
[sos, gain] = zp2sos(z, p, k);                              % en secciones de 2º orden (estable)
y = filtfilt(sos, gain, x);                                 % filtra sin desfase

w0 = 2 * pi * s.powerline_hz / cfg.fs;                      % frecuencia de la red en rad/muestra
b = [1, -2 * cos(w0), 1];                                   % ceros del notch sobre la red
a = [1, -2 * 0.95 * cos(w0), 0.95 ^ 2];                     % polos cerca de los ceros (muesca estrecha)
b = b * sum(a) / sum(b);                                    % ganancia 1 fuera de la muesca
y = filtfilt(b, a, y);                                      % elimina la interferencia de la red

f.filtered = y;                                             % ventana filtrada
f.rms_raw = sqrt(mean(y .^ 2, 1));                          % RMS de cada canal
f.mav_raw = mean(abs(y), 1);                                % MAV de cada canal
f.rms = scale01(f.rms_raw, s.rest_rms, s.max_rms);          % RMS normalizado a [0,1]
f.mav = scale01(f.mav_raw, s.rest_mav, s.max_mav);          % MAV normalizado a [0,1]

peak = max(f.rms);                                          % canal más activo
if peak >= s.active_threshold                               % contracción clara
    f.state = 'ACTIVE';
elseif peak < s.rest_threshold                              % sin actividad
    f.state = 'REST';
else                                                        % entre los dos umbrales
    f.state = 'TRANSITION';
end

f.noise = noise_reason(double(emg), x, y, s);               % comprueba si la ventana es ruido
if ~isempty(f.noise)                                        % hay un problema en la señal
    f.state = 'NOISE';                                      % se marca como ruido
end
end

function v = scale01(value, rest, top)
% Lleva cada canal de [reposo, máximo] a [0, 1].
v = (value - rest) ./ max(top - rest, eps);                 % 0 en reposo, 1 en el máximo
v = min(max(v, 0), 1);                                      % recorta a [0, 1]
end

function reason = noise_reason(raw, centered, filtered, s)
% Devuelve el motivo si la ventana no es utilizable, o '' si está limpia.
reason = '';                                                % por defecto, limpia
saturated = find(mean(abs(raw) >= s.saturation_level, 1) > 0.05); % >5 % de muestras saturadas
flat = find(std(raw, 0, 1) < 1e-6);                         % canal sin variación (electrodo suelto)
raw_rms = sqrt(mean(centered .^ 2, 1));                     % energía antes de filtrar
kept = sqrt(mean(filtered .^ 2, 1)) ./ max(raw_rms, eps);   % fracción que sobrevive al filtro
artifact = find(raw_rms > 5 & kept < sqrt(0.2));            % casi todo por debajo de 20 Hz: movimiento
if ~isempty(saturated)
    reason = ['saturación en CH' sprintf('%d ', saturated)];
elseif ~isempty(flat)
    reason = ['canal plano en CH' sprintf('%d ', flat)];
elseif ~isempty(artifact)
    reason = ['artefacto de movimiento en CH' sprintf('%d ', artifact)];
end
reason = strtrim(reason);                                   % quita el espacio final
end
