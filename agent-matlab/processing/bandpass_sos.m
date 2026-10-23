function sos = bandpass_sos(band_hz, fs)
% BANDPASS_SOS Butterworth pasa-banda de orden 4 en 4 secciones de 2º orden, sin toolboxes.
%   sos : 4 x 6, cada fila [b0 b1 b2 a0 a1 a2] con ganancia 1 en el centro de la banda.

n = 4;                                                      % orden del prototipo pasa-bajos
w = 2 * fs * tan(pi * band_hz / fs);                        % frecuencias de corte "pre-deformadas" (rad/s)
w0 = sqrt(w(1) * w(2));                                     % centro de la banda
bw = w(2) - w(1);                                           % ancho de la banda
proto = exp(1i * pi * (2 * (1:n) + n - 1) / (2 * n));       % polos del Butterworth pasa-bajos
s_poles = [proto * bw / 2 + sqrt((proto * bw / 2) .^ 2 - w0 ^ 2), ...
    proto * bw / 2 - sqrt((proto * bw / 2) .^ 2 - w0 ^ 2)]; % pasa-bajos -> pasa-banda (8 polos)
z_poles = (2 * fs + s_poles) ./ (2 * fs - s_poles);         % transformación bilineal (plano z)
z_poles = z_poles(imag(z_poles) > 0);                       % un polo de cada par conjugado (4)

center = exp(1i * 2 * atan(w0 / (2 * fs)));                 % centro de la banda en el círculo unidad
sos = zeros(n, 6);
for k = 1:n
    b = [1 0 -1];                                           % ceros en z = 1 y z = -1
    a = [1, -2 * real(z_poles(k)), abs(z_poles(k)) ^ 2];    % par de polos conjugados
    g = abs(polyval(a, center) / polyval(b, center));       % ganancia para valer 1 en el centro
    sos(k, :) = [g * b, a];
end
end
