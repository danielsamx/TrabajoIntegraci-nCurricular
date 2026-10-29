function payload = build_payload(f, prev, feedback, t_ms, cfg)
% BUILD_PAYLOAD Texto de una línea que recibe el LLM:
%   RMS:[..]|SIM:[C=..,O=..]|DIST:[S=..,C=..,O=..]|ACT:[C=..,O=..]|CIERRE:0.57|POS:A200B200...|PREV:S|FB:OK|T:1000
%   SIM = parecido de forma; DIST = distancia al reposo y a cada gesto; ACT = activación de cada gesto;
%   CIERRE = cierre estimado (0 abierta, 1 cerrada); POS = posición de los dedos para ese cierre;
%   FB = resultado del último envío a la prótesis (OK, FALLO o NADA)

rms_text = sprintf('%.2f,', f.rms);                         % RMS con 2 decimales
sim_text = '';                                              % similitud con cada gesto
act_text = '';                                              % activación de cada gesto
dist_text = sprintf('%s=%.2f,', cfg.rest_command, f.rest_distance); % distancia al reposo
for g = 1:numel(cfg.gestures)
    c = cfg.gestures(g).command;                            % letra del gesto
    sim_text = [sim_text, sprintf('%s=%.2f,', c, f.similarity(g))]; %#ok<AGROW>
    dist_text = [dist_text, sprintf('%s=%.2f,', c, f.distance(g))]; %#ok<AGROW>
    act_text = [act_text, sprintf('%s=%.2f,', c, f.activation(g))]; %#ok<AGROW>
end

payload = sprintf('RMS:[%s]|SIM:[%s]|DIST:[%s]|ACT:[%s]|CIERRE:%.2f|POS:%s|PREV:%s|FB:%s|T:%d', ...
    rms_text(1:end - 1), sim_text(1:end - 1), dist_text(1:end - 1), act_text(1:end - 1), ...
    f.closure, f.posture, prev.command, feedback, round(t_ms)); % une todo sin las últimas comas
end
