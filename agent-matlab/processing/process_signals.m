function f = process_signals(emg, cfg)
% PROCESS_SIGNALS Cadena de procesamiento de una ventana de EMG (N x 8), paso a paso:
%   1. quita la continua   2. pasa-banda   3. notch de la red   4. rectificación de onda completa
%   5. RMS y MAV por canal   6. normalización a [0,1]   7. comparación con los perfiles de cada gesto
%   8. activación de cada gesto, cierre de la mano y postura de los 6 dedos
%
%   f.filtered, f.rectified : ventana filtrada y rectificada (N x 8)
%   f.rms_raw, f.mav_raw    : RMS y MAV por canal sin normalizar
%   f.rms, f.mav            : RMS y MAV normalizados a [0,1]
%   f.wl, f.zc, f.ssc       : longitud de onda, cruces por cero y cambios de pendiente por canal
%   f.similarity            : parecido de forma (coseno, 0-1) con cada gesto
%   f.distance              : distancia a cada gesto; f.rest_distance: distancia al reposo
%   f.activation            : cuánto de cada gesto contiene la ventana (1 = como su perfil)
%   f.closure               : cierre de la mano de 0 (abierta) a 1 (cerrada)
%   f.posture               : posición de los 6 dedos para ese cierre, p. ej. 'A180B180C220D180E60F50'
%   f.reference             : comando que darían las reglas (solo se imprime, no se envía)

s = cfg.signal;                                             % atajo a la configuración de la señal
x = double(emg);                                            % muestras como números reales
x = x - mean(x, 1);                                         % 1. quita la componente continua de cada canal

sos = bandpass_sos(s.band_hz, cfg.fs);                      % 2. Butterworth pasa-banda de orden 4
y = zero_phase(sos, x);                                     %    filtrado sin desfase

w0 = 2 * pi * s.powerline_hz / cfg.fs;                      % 3. frecuencia de la red en rad/muestra
b = [1, -2 * cos(w0), 1];                                   %    ceros del notch sobre la red
a = [1, -2 * 0.95 * cos(w0), 0.95 ^ 2];                     %    polos cerca de los ceros (muesca estrecha)
b = b * sum(a) / sum(b);                                    %    ganancia 1 fuera de la muesca
y = zero_phase([b a], y);                                   %    elimina la interferencia de la red
f.filtered = y;                                             % ventana filtrada

r = abs(y);                                                 % 4. rectificación de onda completa
f.rectified = r;
f.rms_raw = sqrt(mean(r .^ 2, 1));                          % 5. RMS de cada canal
f.mav_raw = mean(r, 1);                                     %    MAV de cada canal
f.wl = sum(abs(diff(y)), 1);                                %    WL: longitud de onda
f.zc = sum(y(1:end - 1, :) .* y(2:end, :) < 0, 1);          %    ZC: cruces por cero
slope = diff(y);                                            %    pendiente entre muestras
f.ssc = sum(slope(1:end - 1, :) .* slope(2:end, :) < 0, 1); %    SSC: cambios de pendiente

f.rms = scale01(f.rms_raw, s.rest_rms, s.max_rms);          % 6. RMS normalizado: 0 reposo, 1 máximo
f.mav = scale01(f.mav_raw, s.rest_mav, s.max_mav);          %    MAV normalizado

n = numel(cfg.gestures);                                    % 7. comparación con cada gesto
profiles = vertcat(cfg.gestures.profile);                   %    un perfil RMS por fila
f.similarity = zeros(1, n);
f.distance = zeros(1, n);
for g = 1:n
    ref = profiles(g, :);                                   %    perfil RMS de referencia
    f.similarity(g) = dot(f.rms, ref) / max(norm(f.rms) * norm(ref), eps); % 1 = misma forma
    f.distance(g) = norm(f.rms - ref);                      %    0 = idéntico al perfil
end
f.rest_distance = norm(f.rms);                              %    distancia al reposo (todo en 0)

f.activation = lsqnonneg(profiles', f.rms')';               % 8. RMS = suma de perfiles x activación (>= 0)
total = sum(f.activation);                                  %    activación total
if total > 0
    shape = dot(f.activation, [cfg.gestures.closure]) / total; % qué tan "de cierre" es el patrón
    f.closure = shape * min(1, total);                      %    y con qué fuerza (1 = como el perfil)
else
    f.closure = 0;                                          %    sin activación
end
f.posture = posture_string(f.closure, cfg);                 %    posición de los 6 dedos

[~, best] = max(f.similarity);                              % referencia por reglas (no se envía)
if f.rest_distance < f.distance(best)                       %    más cerca del reposo que del gesto
    f.reference = cfg.rest_command;
elseif round(100 * f.closure) == 100                        %    CIERRE 1.00: cerrada del todo
    f.reference = cfg.gestures([cfg.gestures.closure] == 1).command; % C
elseif round(100 * f.closure) == 0                          %    CIERRE 0.00: abierta del todo
    f.reference = cfg.gestures([cfg.gestures.closure] == 0).command; % O
else
    f.reference = f.posture;                                %    cierre parcial: posición de cada dedo
end
end

function v = scale01(value, rest, top)
% Lleva cada canal de [reposo, máximo] a [0, 1].
v = (value - rest) ./ max(top - rest, eps);                 % 0 en reposo, 1 en el máximo
v = min(max(v, 0), 1);                                      % recorta a [0, 1]
end
