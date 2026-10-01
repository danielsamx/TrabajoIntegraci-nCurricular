function payload = build_payload(f, prev, t_ms, cfg)
% BUILD_PAYLOAD Texto de una línea que recibe el LLM:
%   RMS:[r1..r8]|SIM:[C=0.97,O=0.55]|STATE:<estado>|PREV:<comando>|T:<ms>

rms_text = sprintf('%.2f,', f.rms);                         % RMS con 2 decimales separados por comas
sim_text = '';                                              % similitud con cada gesto
for g = 1:numel(cfg.gestures)
    sim_text = [sim_text, sprintf('%s=%.2f,', cfg.gestures(g).command, f.similarity(g))]; %#ok<AGROW>
end

payload = sprintf('RMS:[%s]|SIM:[%s]|STATE:%s|PREV:%s|T:%d', ...
    rms_text(1:end - 1), sim_text(1:end - 1), f.state, prev.command, round(t_ms)); % une todo sin la última coma
end
