function ok = send_prosthesis_command(p, command)
% SEND_PROSTHESIS_COMMAND Envía el comando a la prótesis por HTTP, puerto serie o Bluetooth.
%   p.mode = 'http'      : POST http://host:port/endpoint con {"command": "C"}
%   p.mode = 'serial'    : escribe "C" + fin de línea en p.serial_port
%   p.mode = 'bluetooth' : escribe "C" + fin de línea por Bluetooth clásico (SPP) a p.bt_name
%   send_prosthesis_command(p, 'open') abre la conexión serie/Bluetooth sin enviar nada.
%   send_prosthesis_command('close')   cierra la conexión abierta.  Devuelve true si funcionó.

persistent link link_key                                    % conexión abierta y su descripción

if ischar(p) && strcmp(p, 'close')                          % cierre pedido al terminar la sesión
    if ~isempty(link)
        log_msg('PROT', 'Cerrando %s', link_key);
    end
    link = [];                                              % al borrar el objeto se libera la conexión
    link_key = '';
    ok = true;
    return;
end

timer = tic;                                                % mide la latencia
try
    if strcmp(p.mode, 'http')
        url = sprintf('http://%s:%d%s', p.host, p.port, p.endpoint); % dirección del servidor
        body = jsonencode(struct('command', command));      % cuerpo JSON
        options = weboptions('MediaType', 'application/json', 'Timeout', p.timeout); % POST JSON
        log_msg('PROT', 'POST %s %s', url, body);
        reply = webwrite(url, body, options);               % envía el comando
        if ~ischar(reply)                                   % si respondió con JSON
            reply = jsonencode(reply);                      % lo pasa a texto para imprimirlo
        end
    else
        key = link_name(p);                                 % p. ej. "COM5 a 115200 baudios"
        if isempty(link) || ~strcmp(link_key, key)          % no está abierta (o cambió)
            link = [];                                      % cierra la anterior, si había
            log_msg('PROT', 'Abriendo %s', key);
            link = open_link(p);                            % puerto serie u objeto bluetooth
            configureTerminator(link, p.terminator);        % fin de línea de cada comando
            link_key = key;
            log_msg('PROT', 'Conectado a %s (%.0f ms)', key, 1000 * toc(timer));
        end
        if strcmp(command, 'open')                          % solo se pedía abrir la conexión
            ok = true;
            return;
        end
        log_msg('PROT', '%s <- "%s" + %s', link_key, command, p.terminator);
        writeline(link, command);                           % envía la letra y el fin de línea
        pause(0.02);                                        % deja llegar una posible respuesta
        reply = '(sin respuesta)';
        if link.NumBytesAvailable > 0                       % la mano respondió algo
            reply = char(read(link, link.NumBytesAvailable, 'char')); % lo lee todo de una vez
        end
        reply = regexprep(reply, '\s+', ' ');               % respuesta en una sola línea
    end
    ok = true;
    log_msg('PROT', 'Respuesta (%.0f ms): %s', 1000 * toc(timer), strtrim(reply));
catch err
    ok = false;
    if ~strcmp(p.mode, 'http')
        link = [];                                          % se reabrirá en el próximo envío
        link_key = '';
    end
    log_msg('PROT', 'Fallo (%.0f ms): %s', 1000 * toc(timer), err.message);
    if strcmp(command, 'open')                              % al abrir, el motivo se muestra al usuario
        error('prosthesis:open', '%s', open_hint(p, err.message));
    end
end
end

function key = link_name(p)
% Descripción legible de la conexión configurada.
if strcmp(p.mode, 'bluetooth')
    key = sprintf('Bluetooth "%s" (canal %d)', p.bt_name, p.bt_channel);
else
    key = sprintf('%s a %d baudios', p.serial_port, p.baud_rate);
end
end

function link = open_link(p)
% Abre el puerto serie o la conexión Bluetooth clásica (SPP).
if strcmp(p.mode, 'bluetooth')
    link = bluetooth(p.bt_name, p.bt_channel, 'Timeout', p.timeout); % MATLAB base, R2020b+
else
    link = serialport(p.serial_port, p.baud_rate, 'Timeout', p.timeout);
end
end

function text = open_hint(p, message)
% Motivo del fallo al abrir y qué hacer.
if strcmp(p.mode, 'bluetooth')
    text = sprintf(['No se pudo conectar por Bluetooth con "%s": %s\n\n' ...
        '1. La prótesis debe estar encendida y no conectada a otro equipo (p. ej. el móvil).\n' ...
        '2. El PC necesita Bluetooth propio o un adaptador USB Bluetooth (el adaptador del Myo, ' ...
        'BLED112, no sirve para esto).\n' ...
        '3. Empareje primero "%s" en Configuración de Windows > Bluetooth.\n' ...
        'Alternativa: tras emparejarla, Windows crea un puerto COM para la prótesis; ' ...
        'puede usarlo con la opción Serial.'], p.bt_name, message, p.bt_name);
else
    text = sprintf('No se pudo abrir %s: %s', link_name(p), message);
end
end
