function passed = test_prosthesis_connection(varargin)
    % TEST_PROSTHESIS_CONNECTION Prueba el envío de comandos a la prótesis.
    %
    % TEST_PROSTHESIS_CONNECTION Tests sending commands to the prosthesis.
    %
    % Envía el comando seguro '#R' (reposo) y, con 'Sweep', true, un barrido suave de
    % cada dedo (A-E a 30 grados y vuelta a reposo).
    % Sends the safe command '#R' (rest) and, with 'Sweep', true, a gentle sweep of
    % each finger (A-E to 30 degrees and back to rest).
    %
    % DECISIÓN: por defecto solo '#R' | RAZÓN: un test no debe mover la prótesis de forma
    %   inesperada | ALTERNATIVA DESCARTADA: barrido completo siempre
    % DECISION: '#R' only by default | REASON: a test must not move the prosthesis
    %   unexpectedly | DISCARDED ALTERNATIVE: always doing a full sweep
    %
    % Entradas (nombre-valor) / Inputs (name-value):
    %   'Config' : struct server_prosthesis (por defecto config/server-prosthesis.mat)
    %   'Sweep'  : mover cada dedo a 30 grados / move each finger to 30 degrees (false)
    %
    % Salidas / Outputs:
    %   passed : true si todos los comandos fueron aceptados / true if all accepted
    %
    % Ejemplo / Example:
    %   ok = test_prosthesis_connection();
    %   ok = test_prosthesis_connection('Sweep', true);

    root = add_project_paths();
    fprintf('\n--- test_prosthesis_connection ---\n');

    p = inputParser;
    addParameter(p, 'Config', []);
    addParameter(p, 'Sweep', false);
    parse(p, varargin{:});

    passed = false;
    cfg = p.Results.Config;
    if isempty(cfg)
        try
            loaded = load(fullfile(root, 'config', 'server-prosthesis.mat'), ...
                'server_prosthesis');
            cfg = loaded.server_prosthesis;
        catch err
            fprintf('  [FAIL] configuración / configuration: %s\n', err.message);
            return;
        end
    end
    fprintf('  Destino / target: %s http://%s:%d%s\n', cfg.protocol, cfg.ip, cfg.port, ...
        cfg.endpoint);

    commands = {make_command('#R', 'NONE', 'rest', 0)};
    if p.Results.Sweep
        letters = {'A', 'B', 'C', 'D', 'E'};
        fingers = {'D1', 'D2', 'D3', 'D4', 'D5'};
        for k = 1:numel(letters)
            commands{end + 1} = make_command(letters{k}, fingers{k}, 'flex', 30); %#ok<AGROW>
            commands{end + 1} = make_command(letters{k}, fingers{k}, 'extend', 0); %#ok<AGROW>
        end
        commands{end + 1} = make_command('#R', 'NONE', 'rest', 0);
    end

    send_signals_prosthesis('reset');
    results = false(1, numel(commands));
    for k = 1:numel(commands)
        [ok, reply, latency_ms] = send_signals_prosthesis(cfg, commands{k}, k);
        results(k) = ok;
        fprintf('  [%s] %-3s %-7s %3d -> %.0f ms | %s\n', pass_text(ok), ...
            commands{k}.command, commands{k}.action, commands{k}.value, latency_ms, ...
            reply_text(reply));
        if p.Results.Sweep
            pause(0.5);
        end
    end

    passed = all(results);
    fprintf('--- test_prosthesis_connection: %s (%d/%d) ---\n', pass_text(passed), ...
        sum(results), numel(results));
end

% -------------------------------------------------------------------------------------------
function command = make_command(code, finger, action, value)
    % MAKE_COMMAND Comando de prueba. / Test command.
    command = struct('command', code, 'finger', finger, 'action', action, ...
        'confidence', 1.0, 'trigger_channels', [], 'value', value, 'source', 'test');
end

% -------------------------------------------------------------------------------------------
function text = reply_text(reply)
    % REPLY_TEXT Respuesta resumida para consola. / Short reply for the console.
    try
        if ischar(reply) || isstring(reply)
            text = char(reply);
        else
            text = jsonencode(reply);
        end
    catch
        text = '<respuesta no textual / non-text reply>';
    end
    if numel(text) > 80
        text = [text(1:80), '...'];
    end
end

% -------------------------------------------------------------------------------------------
function text = pass_text(ok)
    % PASS_TEXT 'PASS' o 'FAIL'.
    if ok
        text = 'PASS';
    else
        text = 'FAIL';
    end
end

% -------------------------------------------------------------------------------------------
function root = add_project_paths()
    % ADD_PROJECT_PATHS Permite ejecutar el test de forma independiente.
    % ADD_PROJECT_PATHS Allows running the test standalone.
    root = fileparts(fileparts(mfilename('fullpath')));
    folders = {'config', 'acquisition', 'processing', 'llm', 'prosthesis', 'utils', 'tests'};
    addpath(root);
    for k = 1:numel(folders)
        addpath(fullfile(root, folders{k}));
    end
end
