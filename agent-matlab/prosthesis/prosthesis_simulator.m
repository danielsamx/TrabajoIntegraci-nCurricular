function out = prosthesis_simulator(action, varargin)
    % PROSTHESIS_SIMULATOR Simulador local de la prótesis de mano (6 GDL: 5 dedos + muñeca).
    %
    % PROSTHESIS_SIMULATOR Local hand prosthesis simulator (6 DOF: 5 fingers + wrist).
    %
    % Uso / Usage:
    %   prosthesis_simulator('reset');                    % postura neutra / neutral pose
    %   reply = prosthesis_simulator('command', body);    % aplica un comando / apply command
    %   s     = prosthesis_simulator('state');            % ángulos actuales / current angles
    %   prosthesis_simulator('plot');                     % visualiza / visualize
    %   prosthesis_simulator('start_server', 8080);       % servidor HTTP (otra sesión MATLAB)
    %   prosthesis_simulator('stop_server');
    %
    % Servidor HTTP / HTTP server:
    %   POST /api/command  -> aplica el comando y responde {"status":"ok","angles":[...]}
    %   GET  /api/status   -> {"status":"ok","angles":[...],"commands":N}
    %
    % DECISIÓN: dos modos (en proceso 'SIM' y servidor HTTP con tcpserver) | RAZÓN: MATLAB
    %   ejecuta los callbacks en el mismo hilo; si main.m está bloqueado en webwrite, el
    %   servidor de la MISMA sesión no puede responder. El modo en proceso sirve para una
    %   sola sesión; el servidor HTTP debe correr en otra sesión de MATLAB |
    %   ALTERNATIVA DESCARTADA: servidor HTTP en la misma sesión (bloqueo mutuo)
    % DECISION: two modes (in-process 'SIM' and HTTP server with tcpserver) | REASON:
    %   MATLAB runs callbacks on the same thread; if main.m is blocked in webwrite, a server
    %   in the SAME session cannot answer. In-process mode serves a single session; the HTTP
    %   server must run in another MATLAB session |
    %   DISCARDED ALTERNATIVE: HTTP server in the same session (deadlock)
    %
    % DECISIÓN: HTTP mínimo sobre tcpserver (MATLAB base) | RAZÓN: no hay servidor HTTP en
    %   MATLAB base sin toolboxes adicionales | ALTERNATIVA DESCARTADA: MATLAB Production
    %   Server / Java HttpServer (licencia extra / dependencia oculta)
    % DECISION: minimal HTTP on top of tcpserver (base MATLAB) | REASON: base MATLAB has no
    %   HTTP server without extra toolboxes | DISCARDED ALTERNATIVE: MATLAB Production
    %   Server / Java HttpServer (extra license / hidden dependency)
    %
    % DECISIÓN: ángulo de gesto = preset * (0.4 + 0.6 * value/100) | RAZÓN: el gesto sigue
    %   siendo reconocible incluso con poca fuerza | ALTERNATIVA DESCARTADA: preset * value
    %   (con fuerza 0 un puño sería una mano abierta)
    % DECISION: gesture angle = preset * (0.4 + 0.6 * value/100) | REASON: the gesture stays
    %   recognizable even with low strength | DISCARDED ALTERNATIVE: preset * value
    %   (with strength 0 a fist would become an open hand)
    %
    % Entradas / Inputs:
    %   action   : 'reset'|'command'|'state'|'plot'|'start_server'|'stop_server'
    %   varargin : body (struct o JSON) para 'command'; puerto para 'start_server'
    %              body (struct or JSON) for 'command'; port for 'start_server'
    %
    % Salidas / Outputs:
    %   out : struct con status, angles [A B C D E F], command, commands (contador)
    %         struct with status, angles [A B C D E F], command, commands (counter)

    persistent angles command_count last_command server fig

    NEUTRAL = [20, 20, 20, 20, 20, 90];
    if isempty(angles)
        angles = NEUTRAL;
        command_count = 0;
        last_command = 'NONE';
    end

    out = [];
    switch lower(action)
        case 'reset'
            angles = NEUTRAL;
            command_count = 0;
            last_command = 'NONE';
            out = make_state(angles, last_command, command_count);

        case 'command'
            body = varargin{1};
            if ischar(body) || isstring(body)
                body = jsondecode(char(body));
            end
            angles = apply_command(angles, body, NEUTRAL);
            command_count = command_count + 1;
            last_command = char(body.command);
            out = make_state(angles, last_command, command_count);
            if ~isempty(fig) && isgraphics(fig)
                draw_hand(fig, angles, last_command);
            end

        case 'state'
            out = make_state(angles, last_command, command_count);

        case 'plot'
            if isempty(fig) || ~isgraphics(fig)
                fig = figure('Name', 'Prosthesis simulator / Simulador de protesis', ...
                    'NumberTitle', 'off');
            end
            draw_hand(fig, angles, last_command);
            out = make_state(angles, last_command, command_count);

        case 'start_server'
            port = 8080;
            if ~isempty(varargin)
                port = varargin{1};
            end
            if ~isempty(server)
                server = [];
            end
            server = tcpserver('0.0.0.0', port, 'Timeout', 1);
            configureTerminator(server, 'CR/LF');
            configureCallback(server, 'terminator', @on_http_request);
            logger('INFO', 'prosthesis_simulator', ...
                'Servidor HTTP en puerto / HTTP server on port %d', port);
            out = make_state(angles, last_command, command_count);

        case 'stop_server'
            server = [];
            logger('INFO', 'prosthesis_simulator', 'Servidor detenido / Server stopped');

        otherwise
            error('prosthesis_simulator:action', ...
                'Acción desconocida / Unknown action: %s', action);
    end
end

% -------------------------------------------------------------------------------------------
function angles = apply_command(angles, body, neutral)
    % APPLY_COMMAND Actualiza los ángulos según el comando. / Updates angles from command.
    command = upper(char(body.command));
    value = 0;
    if isfield(body, 'value') && ~isempty(body.value)
        value = double(body.value);
    end
    info = label_to_finger(command);
    if isempty(info)
        error('prosthesis_simulator:command', 'Comando desconocido / Unknown: %s', command);
    end
    value = min(max(value, info.range(1)), info.range(2));

    finger_letters = 'ABCDEF';
    if strcmp(command, '#R')
        angles = neutral;
    elseif ~info.is_gesture
        angles(finger_letters == command) = value;
    else
        preset = gesture_preset(command);
        factor = 0.4 + 0.6 * value / 100;
        angles(1:5) = round(preset * factor);
    end
end

% -------------------------------------------------------------------------------------------
function preset = gesture_preset(command)
    % GESTURE_PRESET Ángulos [A B C D E] al 100 % de fuerza. / Angles at 100 % strength.
    switch command
        case '#O'
            preset = [0, 0, 0, 0, 0];
        case '#C'
            preset = [90, 120, 120, 120, 120];
        case '#P'
            preset = [60, 80, 10, 10, 10];
        case '#W'
            preset = [90, 0, 0, 0, 120];
        case '#Y'
            preset = [0, 120, 120, 120, 0];
        case '#L'
            preset = [0, 0, 120, 120, 120];
        case '#M'
            preset = [45, 35, 35, 60, 60];
        case '#H'
            preset = [0, 90, 90, 90, 90];
        case '#U'
            preset = [90, 0, 0, 120, 120];
        case '#G'
            preset = [90, 0, 120, 120, 120];
        otherwise
            preset = [20, 20, 20, 20, 20];
    end
end

% -------------------------------------------------------------------------------------------
function state = make_state(angles, last_command, count)
    % MAKE_STATE Struct de estado para respuestas. / State struct for replies.
    state = struct('status', 'ok', 'angles', angles, 'command', last_command, ...
        'commands', count);
end

% -------------------------------------------------------------------------------------------
function draw_hand(fig, angles, last_command)
    % DRAW_HAND Dibuja los ángulos como barras. / Draws the angles as bars.
    ax = findobj(fig, 'Type', 'axes');
    if isempty(ax)
        ax = axes('Parent', fig);
    end
    ax = ax(1);
    maxima = [90, 120, 120, 120, 120, 180];
    bar(ax, angles ./ maxima, 'FaceColor', [0.2, 0.5, 0.8]);
    ylim(ax, [0, 1]);
    set(ax, 'XTickLabel', {'A pulgar', 'B indice', 'C medio', 'D anular', ...
        'E menique', 'F muneca'});
    ylabel(ax, 'Flexion (fraccion del rango / range fraction)');
    title(ax, sprintf('Ultimo comando / Last command: %s  |  [%s]', last_command, ...
        num2str(angles)), 'Interpreter', 'none');
    drawnow limitrate;
end

% -------------------------------------------------------------------------------------------
function on_http_request(src, ~)
    % ON_HTTP_REQUEST Atiende una petición HTTP/1.1 mínima (callback de tcpserver).
    % ON_HTTP_REQUEST Serves a minimal HTTP/1.1 request (tcpserver callback).
    try
        if src.NumBytesAvailable == 0
            return;
        end
        request_line = strtrim(char(readline(src)));
        parts = strsplit(request_line, ' ');
        if numel(parts) < 2 || ~any(strcmpi(parts{1}, {'GET', 'POST', 'OPTIONS'}))
            return;   % línea de cabecera huérfana / orphan header line
        end
        method = upper(parts{1});
        path = parts{2};

        content_length = 0;
        while true
            line = strtrim(char(readline(src)));
            if isempty(line)
                break;   % fin de cabeceras o timeout / end of headers or timeout
            end
            tok = regexp(line, '^content-length:\s*(\d+)', 'tokens', 'once', 'ignorecase');
            if ~isempty(tok)
                content_length = str2double(tok{1});
            end
        end

        body_text = '';
        if content_length > 0
            body_text = char(read(src, content_length, 'char'));
        end

        [status, reason, reply] = route(method, path, body_text);
        reply_bytes = unicode2native(jsonencode(reply), 'UTF-8');
        header = sprintf(['HTTP/1.1 %d %s\r\nContent-Type: application/json\r\n', ...
            'Content-Length: %d\r\nConnection: close\r\n\r\n'], status, reason, ...
            numel(reply_bytes));
        write(src, [uint8(header), uint8(reply_bytes)], 'uint8');
    catch err
        logger('WARN', 'prosthesis_simulator', 'Petición fallida / Request failed: %s', ...
            err.message);
    end
end

% -------------------------------------------------------------------------------------------
function [status, reason, reply] = route(method, path, body_text)
    % ROUTE Enrutador de la API REST simulada. / Simulated REST API router.
    status = 200;
    reason = 'OK';
    try
        if strcmp(method, 'POST') && startsWith(path, '/api/command')
            reply = prosthesis_simulator('command', body_text);
            logger('INFO', 'prosthesis_simulator', '%s -> [%s]', reply.command, ...
                num2str(reply.angles));
        elseif strcmp(method, 'GET') && startsWith(path, '/api/status')
            reply = prosthesis_simulator('state');
        elseif strcmp(method, 'OPTIONS')
            reply = struct('status', 'ok');
        else
            status = 404;
            reason = 'Not Found';
            reply = struct('status', 'error', 'message', 'not found');
        end
    catch err
        status = 400;
        reason = 'Bad Request';
        reply = struct('status', 'error', 'message', err.message);
    end
end
