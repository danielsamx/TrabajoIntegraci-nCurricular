function payload = build_payload(f, prev, t_ms, cfg)
% BUILD_PAYLOAD Texto de una línea que recibe el LLM:
%   RMS:[r1..r8]|SIM:[C=0.97,O=0.55]|DIST:[S=0.95,C=0.20,O=0.70]|PREV:<comando>|T:<ms>
%   SIM  = parecido de forma con cada gesto (1 = igual); DIST = distancia al reposo y a cada gesto (0 = igual)

rms_text = sprintf('%.2f,', f.rms);                         % RMS con 2 decimales separados por comas
sim_text = '';                                              % similitud con cada gesto
dist_text = sprintf('%s=%.2f,', cfg.rest_command, f.rest_distance); % distancia al reposo
for g = 1:numel(cfg.gestures)
    sim_text = [sim_text, sprintf('%s=%.2f,', cfg.gestures(g).command, f.similarity(g))]; %#ok<AGROW>
    dist_text = [dist_text, sprintf('%s=%.2f,', cfg.gestures(g).command, f.distance(g))]; %#ok<AGROW>
end

payload = sprintf('RMS:[%s]|SIM:[%s]|DIST:[%s]|PREV:%s|T:%d', rms_text(1:end - 1), ...
    sim_text(1:end - 1), dist_text(1:end - 1), prev.command, round(t_ms)); % une todo sin la última coma
end
