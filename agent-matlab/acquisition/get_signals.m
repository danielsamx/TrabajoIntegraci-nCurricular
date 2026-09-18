function [emg_window, fs] = get_signals(window_ms)
    % GET_SIGNALS Adquiere una ventana de señal sEMG del Myo Armband (8 canales).
    %
    % GET_SIGNALS Acquires one sEMG signal window from the Myo Armband (8 channels).
    %
    % La fuente (BLE, UDP o simulada) se configura una sola vez con:
    % The source (BLE, UDP or simulated) is configured once with:
    %   myo_interface.instance('source', 'myo', 'device_name', 'Myo');
    %
    % DECISIÓN: usar buffer circular | RAZÓN: evita perder muestras entre ciclos |
    %   ALTERNATIVA DESCARTADA: leer directamente del Myo (bloqueante)
    % DECISION: use a circular buffer | REASON: avoids losing samples between cycles |
    %   DISCARDED ALTERNATIVE: reading directly from the Myo (blocking)
    %
    % DECISIÓN: ventana de 200 ms (40 muestras) | RAZÓN: compromiso clásico en control
    %   mioeléctrico entre estabilidad de RMS y retardo (<300 ms percibidos) |
    %   ALTERNATIVA DESCARTADA: 500 ms (retardo perceptible por el usuario)
    % DECISION: 200 ms window (40 samples) | REASON: classic myoelectric-control trade-off
    %   between RMS stability and delay (<300 ms perceived) |
    %   DISCARDED ALTERNATIVE: 500 ms (delay noticeable by the user)
    %
    % Entradas / Inputs:
    %   window_ms : duración de la ventana en milisegundos (default 200)
    %               window length in milliseconds (default 200)
    %
    % Salidas / Outputs:
    %   emg_window : matriz 40x8 (40 muestras x 8 canales) para 200 ms
    %                40x8 matrix (40 samples x 8 channels) for 200 ms
    %   fs         : frecuencia de muestreo (200 Hz) / sampling rate (200 Hz)
    %
    % Ejemplo / Example:
    %   myo_interface.instance('source', 'simulated');
    %   [emg, fs] = get_signals(200);   % size(emg) = [40 8]

    if nargin < 1 || isempty(window_ms)
        window_ms = 200;
    end

    myo = myo_interface.instance();
    fs = myo.FS;
    n_samples = max(1, round(window_ms / 1000 * fs));

    [emg_window, is_fresh] = myo.read_window(n_samples);
    if ~is_fresh
        logger('WARN', 'get_signals', ...
            'Sin datos recientes del Myo (fuente=%s) / No recent Myo data (source=%s)', ...
            myo.source, myo.source);
    end
end
