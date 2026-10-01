function payload = build_payload(f, prev, t_ms)
% BUILD_PAYLOAD Texto de una línea que recibe el LLM:
%   RMS:[r1..r8]|MAV:[m1..m8]|STATE:<estado>|PREV:<comando>:<valor>|T:<ms>

rms_text = sprintf('%.2f,', f.rms);                         % RMS con 2 decimales separados por comas
mav_text = sprintf('%.2f,', f.mav);                         % MAV con 2 decimales separados por comas
prev_text = sprintf('%s:%03d', prev.command, round(prev.value)); % comando anterior, p. ej. B:095

payload = sprintf('RMS:[%s]|MAV:[%s]|STATE:%s|PREV:%s|T:%d', ...
    rms_text(1:end - 1), mav_text(1:end - 1), f.state, prev_text, round(t_ms)); % une todo sin la última coma
end
