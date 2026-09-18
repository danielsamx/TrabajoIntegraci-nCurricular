function [ok, reply, latency_ms] = send_signals_prosthesis(cfg_prosthesis, command, cycle)
    % SEND_SIGNALS_PROSTHESIS Envía el comando final a la prótesis (HTTP POST JSON) o al
    %   simulador local (protocolo 'SIM').
    %
    % SEND_SIGNALS_PROSTHESIS Sends the final command to the prosthesis (HTTP POST JSON)
    %   or to the local simulator ('SIM' protocol).
    %
    % Cuerpo JSON / JSON body:
    %   {"command":"B","finger":"D2","action":"flex","value":95,"confidence":0.92,
    %    "trigger_channels":[4,7],"source":"llm","cycle":42,
    %    "timestamp":"2026-09-16T11:20:00.123"}
    %
    % DECISIÓN: HTTP POST JSON con webwrite | RAZÓN: requisito del proyecto (100 % MATLAB,
    %   REST) y fácil de implementar en un microcontrolador con WiFi (ESP32) |
    %   ALTERNATIVA DESCARTADA: puerto serie (acopla la prótesis al PC)
    % DECISION: HTTP POST JSON with webwrite | REASON: project requirement (100 % MATLAB,
    %   REST) and easy to implement on a WiFi microcontroller (ESP32) |
    %   DISCARDED ALTERNATIVE: serial port (couples the prosthesis to the PC)
    %
    % DECISIÓN: contador persistente de fallos consecutivos | RAZÓN: un fallo aislado es
    %   tolerable; varios seguidos indican pérdida de enlace y deben notificarse como ERROR
    %   | ALTERNATIVA DESCARTADA: abortar al primer fallo (demasiado frágil en WiFi)
    % DECISION: persistent consecutive-failure counter | REASON: a single failure is
    %   tolerable; several in a row mean the link is lost and must be reported as ERROR |
    %   DISCARDED ALTERNATIVE: aborting on the first failure (too fragile over WiFi)
    %
    % Entradas / Inputs:
    %   cfg_prosthesis : struct de server-prosthesis.mat / struct from server-prosthesis.mat
    %                    (o 'reset' para reiniciar el contador / or 'reset' for the counter)
    %   command        : struct con command, finger, action, value, confidence,
    %                    trigger_channels, source
    %   cycle          : (opcional) número de ciclo / (optional) cycle number
    %
    % Salidas / Outputs:
    %   ok         : true si la prótesis aceptó el comando / true if accepted
    %   reply      : respuesta decodificada o mensaje de error / decoded reply or error
    %   latency_ms : latencia de la llamada / call latency
    %
    % Ejemplo / Example:
    %   [ok, reply] = send_signals_prosthesis(server_prosthesis, cmd, 42);

    persistent consecutive_failures

    if isempty(consecutive_failures)
        consecutive_failures = 0;
    end
    if ischar(cfg_prosthesis) || isstring(cfg_prosthesis)
        if strcmpi(cfg_prosthesis, 'reset')
            consecutive_failures = 0;
            ok = true;
            reply = [];
            latency_ms = 0;
            return;
        end
        error('send_signals_prosthesis:badInput', 'Entrada no válida / Invalid input');
    end
    if nargin < 3 || isempty(cycle)
        cycle = 0;
    end

    t_start = tic;
    ok = false;
    reply = [];

    body = struct();
    body.command = char(command.command);
    body.finger = char(get_field(command, 'finger', ''));
    body.action = char(get_field(command, 'action', ''));
    body.value = round(double(get_field(command, 'value', 0)));
    body.confidence = double(get_field(command, 'confidence', 0));
    body.trigger_channels = num2cell(double(get_field(command, 'trigger_channels', [])));
    body.source = char(get_field(command, 'source', ''));
    body.cycle = cycle;
    body.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS'));

    protocol = upper(char(get_field(cfg_prosthesis, 'protocol', 'HTTP')));
    try
        switch protocol
            case 'SIM'
                reply = prosthesis_simulator('command', body);
            case 'HTTP'
                url = sprintf('http://%s:%d%s', char(cfg_prosthesis.ip), ...
                    cfg_prosthesis.port, char(cfg_prosthesis.endpoint));
                opts = weboptions('MediaType', 'application/json', ...
                    'Timeout', cfg_prosthesis.timeout, 'RequestMethod', 'post');
                reply = webwrite(url, jsonencode(body), opts);
            otherwise
                error('send_signals_prosthesis:protocol', ...
                    'Protocolo desconocido / Unknown protocol: %s', protocol);
        end
        ok = true;
        consecutive_failures = 0;
    catch err
        reply = err.message;
        consecutive_failures = consecutive_failures + 1;
        max_failures = get_field(cfg_prosthesis, 'max_consecutive_failures', 5);
        if consecutive_failures >= max_failures
            logger('ERROR', 'send_signals_prosthesis', ...
                '%d fallos consecutivos / consecutive failures: %s', ...
                consecutive_failures, err.message);
        else
            logger('WARN', 'send_signals_prosthesis', 'Fallo / Failure: %s', err.message);
        end
    end
    latency_ms = 1000 * toc(t_start);
end

% -------------------------------------------------------------------------------------------
function value = get_field(s, name, default_value)
    % GET_FIELD Campo opcional con valor por defecto. / Optional field with default.
    if isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = default_value;
    end
end
