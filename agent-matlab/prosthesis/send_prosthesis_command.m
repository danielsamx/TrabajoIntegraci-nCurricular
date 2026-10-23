function ok = send_prosthesis_command(p, command)
% SEND_PROSTHESIS_COMMAND Envía el comando a la prótesis por HTTP o por puerto serie.
%   p.mode = 'http'   : POST http://host:port/endpoint con {"command": "C"}
%   p.mode = 'serial' : escribe "C" + fin de línea en p.serial_port (el puerto queda abierto)
%   send_prosthesis_command('close') cierra el puerto serie.  Devuelve true si se envió.

persistent port port_key                                    % puerto serie abierto y su "nombre@baudios"

if ischar(p) && strcmp(p, 'close')                          % cierre pedido al terminar la sesión
    if ~isempty(port)
        log_msg('PROT', 'Cerrando el puerto serie %s', port_key);
    end
    port = [];                                              % al borrar el objeto se libera el puerto
    port_key = '';
    ok = true;
    return;
end

timer = tic;                                                % mide la latencia
try
    if strcmp(p.mode, 'serial')
        key = sprintf('%s@%d', p.serial_port, p.baud_rate); % identifica el puerto configurado
        if isempty(port) || ~strcmp(port_key, key)          % no está abierto (o cambió)
            port = [];                                      % cierra el anterior, si había
            log_msg('PROT', 'Abriendo %s a %d baudios', p.serial_port, p.baud_rate);
            port = serialport(p.serial_port, p.baud_rate, 'Timeout', p.timeout); % abre el puerto
            configureTerminator(port, p.terminator);        % fin de línea de cada comando
            port_key = key;
        end
        log_msg('PROT', 'Serie %s <- "%s" + %s', port_key, command, p.terminator);
        writeline(port, command);                           % envía la letra y el fin de línea
        pause(0.02);                                        % deja llegar una posible respuesta
        reply = '';
        while port.NumBytesAvailable > 0                    % lee todo lo que respondió
            reply = [reply, char(readline(port)), ' ']; %#ok<AGROW>
        end
    else
        url = sprintf('http://%s:%d%s', p.host, p.port, p.endpoint); % dirección del servidor
        body = jsonencode(struct('command', command));      % cuerpo JSON
        options = weboptions('MediaType', 'application/json', 'Timeout', p.timeout); % POST JSON
        log_msg('PROT', 'POST %s %s', url, body);
        reply = webwrite(url, body, options);               % envía el comando
        if ~ischar(reply)                                   % si respondió con JSON
            reply = jsonencode(reply);                      % lo pasa a texto para imprimirlo
        end
    end
    ok = true;
    log_msg('PROT', 'Respuesta (%.0f ms): %s', 1000 * toc(timer), strtrim(reply));
catch err
    ok = false;
    if strcmp(p.mode, 'serial')
        port = [];                                          % se reabrirá en el próximo envío
    end
    log_msg('PROT', 'Fallo (%.0f ms): %s', 1000 * toc(timer), err.message);
end
end
