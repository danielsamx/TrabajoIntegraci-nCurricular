function f = process_signals(emg, cfg)
% PROCESS_SIGNALS Filtra una ventana de EMG (N x 8) y calcula sus características.
%   f.filtered : ventana filtrada (N x 8)
%   f.rms_raw, f.mav_raw : RMS y MAV por canal sin normalizar
%   f.rms, f.mav         : RMS y MAV normalizados a [0,1]
%   f.wl, f.zc, f.ssc    : longitud de onda, cruces por cero y cambios de pendiente por canal
%   f.similarity         : parecido de forma (0-1, coseno) del RMS con cada gesto de cfg.gestures
%   f.distance           : distancia del RMS al perfil de cada gesto (0 = idéntico)
%   f.rest_distance      : distancia del RMS al reposo (todos los canales en 0)

s = cfg.signal;                                             % atajo a la configuración de la señal
x = double(emg);                                            % muestras como números reales
x = x - mean(x, 1);                                         % quita la componente continua de cada canal

sos = bandpass_sos(s.band_hz, cfg.fs);                      % Butterworth pasa-banda de orden 4
y = zero_phase(sos, x);                                     % filtra sin desfase

w0 = 2 * pi * s.powerline_hz / cfg.fs;                      % frecuencia de la red en rad/muestra
b = [1, -2 * cos(w0), 1];                                   % ceros del notch sobre la red
a = [1, -2 * 0.95 * cos(w0), 0.95 ^ 2];                     % polos cerca de los ceros (muesca estrecha)
b = b * sum(a) / sum(b);                                    % ganancia 1 fuera de la muesca
y = zero_phase([b a], y);                                   % elimina la interferencia de la red

f.filtered = y;                                             % ventana filtrada
f.rms_raw = sqrt(mean(y .^ 2, 1));                          % RMS de cada canal
f.mav_raw = mean(abs(y), 1);                                % MAV de cada canal
f.rms = scale01(f.rms_raw, s.rest_rms, s.max_rms);          % RMS normalizado a [0,1]
f.mav = scale01(f.mav_raw, s.rest_mav, s.max_mav);          % MAV normalizado a [0,1]
f.wl = sum(abs(diff(y)), 1);                                % WL: longitud de onda (cuánto "se mueve" la señal)
f.zc = sum(y(1:end - 1, :) .* y(2:end, :) < 0, 1);          % ZC: cruces por cero
slope = diff(y);                                            % pendiente entre muestras
f.ssc = sum(slope(1:end - 1, :) .* slope(2:end, :) < 0, 1); % SSC: cambios de pendiente

f.similarity = zeros(1, numel(cfg.gestures));             % parecido de forma con cada gesto (coseno)
f.distance = zeros(1, numel(cfg.gestures));               % distancia a cada gesto
for g = 1:numel(cfg.gestures)                               % cada gesto configurado
    ref = cfg.gestures(g).profile;                          % su perfil RMS de referencia
    f.similarity(g) = dot(f.rms, ref) / max(norm(f.rms) * norm(ref), eps); % 1 = misma forma
    f.distance(g) = norm(f.rms - ref);                      % 0 = idéntico al perfil
end
f.rest_distance = norm(f.rms);                              % distancia al reposo (todos los canales en 0)
end

function v = scale01(value, rest, top)
% Lleva cada canal de [reposo, máximo] a [0, 1].
v = (value - rest) ./ max(top - rest, eps);                 % 0 en reposo, 1 en el máximo
v = min(max(v, 0), 1);                                      % recorta a [0, 1]
end
