function v = visual_data(f, context, cfg)
% VISUAL_DATA Datos de las 4 imágenes (dashboard y LLM) a partir de la ventana y su contexto.
%   context : últimos cfg.image.context_s segundos de señal filtrada (muestras x 8)
%   v.features : matriz 8 x 5, una fila por canal (RMS, MAV, WL, ZC, SSC) y v.feature_names
%   v.waves    : contexto dividido por el RMS máximo de cada canal (ondas normalizadas)
%   v.envelope : envolvente general = media de las envolventes RMS de los 8 canales, en [0,1]
%   v.t        : tiempo de cada muestra del contexto (s, 0 = ahora)

s = cfg.signal;                                             % atajo a la configuración de la señal
v.feature_names = {'RMS', 'MAV', 'WL', 'ZC', 'SSC'};        % filas de la matriz
v.features = [f.rms; f.mav; f.wl; f.zc; f.ssc]';            % una fila por canal
v.waves = context ./ s.max_rms;                             % ondas en unidades de "RMS máximo"
k = round(cfg.image.envelope_ms / 1000 * cfg.fs);           % muestras de la ventana móvil
rms_move = sqrt(movmean(context .^ 2, k, 1));               % envolvente RMS móvil
channel_env = min(max((rms_move - s.rest_rms) ./ (s.max_rms - s.rest_rms), 0), 1); % cada canal a [0,1]
v.envelope = mean(channel_env, 2);                          % una sola curva: la media de los 8 canales
v.t = (-(size(context, 1) - 1):0)' / cfg.fs;                % eje de tiempo
end
