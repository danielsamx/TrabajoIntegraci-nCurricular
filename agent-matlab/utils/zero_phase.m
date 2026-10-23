function y = zero_phase(sos, x)
% ZERO_PHASE Filtra x (muestras x canales) hacia adelante y hacia atrás: sin desfase.
%   Equivale a filtfilt de Signal Processing Toolbox, usando solo filter() de MATLAB.
%   sos : filas [b0 b1 b2 a0 a1 a2] (secciones de 2º orden en cascada).

pad = min(3 * 2 * size(sos, 1), size(x, 1) - 1);            % muestras de relleno en cada extremo
head = 2 * x(1, :) - x(pad + 1:-1:2, :);                    % reflejo impar del inicio
tail = 2 * x(end, :) - x(end - 1:-1:end - pad, :);          % reflejo impar del final
y = [head; x; tail];                                        % señal extendida (evita transitorios)
for pass = 1:2                                              % adelante y luego atrás
    for k = 1:size(sos, 1)
        y = filter(sos(k, 1:3), sos(k, 4:6), y);            % cada sección de 2º orden
    end
    y = flipud(y);                                          % invierte el tiempo
end
y = y(pad + 1:end - pad, :);                                % quita el relleno
end
