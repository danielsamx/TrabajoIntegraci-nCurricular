function ok = send_prosthesis_command(p, command)
% SEND_PROSTHESIS_COMMAND Envía el comando a la prótesis: POST {"command": "B"}.
%   p : cfg.prosthesis (host, port, endpoint, timeout). Devuelve true si se aceptó.

url = sprintf('http://%s:%d%s', p.host, p.port, p.endpoint); % dirección del servidor
body = jsonencode(struct('command', command));              % cuerpo JSON
options = weboptions('MediaType', 'application/json', 'Timeout', p.timeout); % POST JSON con espera máxima

log_msg('PROT', 'POST %s %s', url, body);
timer = tic;                                                % mide la latencia
try
    reply = webwrite(url, body, options);                   % envía el comando
    if ~ischar(reply)                                       % si respondió con JSON
        reply = jsonencode(reply);                          % lo pasa a texto para imprimirlo
    end
    ok = true;
    log_msg('PROT', 'Respuesta (%.0f ms): %s', 1000 * toc(timer), reply);
catch err
    ok = false;
    log_msg('PROT', 'Fallo (%.0f ms): %s', 1000 * toc(timer), err.message);
end
end
