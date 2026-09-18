function server_prosthesis = create_server_prosthesis_config(varargin)
    % CREATE_SERVER_PROSTHESIS_CONFIG Genera config/server-prosthesis.mat.
    %
    % CREATE_SERVER_PROSTHESIS_CONFIG Generates config/server-prosthesis.mat.
    %
    % DECISIÓN: protocolo 'SIM' además de 'HTTP' | RAZÓN: permite ejecutar todo el
    %   pipeline sin hardware con el simulador en proceso | ALTERNATIVA DESCARTADA: exigir
    %   siempre un servidor HTTP (bloquea el desarrollo sin prótesis)
    % DECISION: 'SIM' protocol besides 'HTTP' | REASON: allows running the whole pipeline
    %   without hardware using the in-process simulator | DISCARDED ALTERNATIVE: always
    %   requiring an HTTP server (blocks development without the prosthesis)
    %
    % DECISIÓN: comando seguro '#R' (reposo) | RAZÓN: ante fallos o al cerrar, relajar la
    %   mano es la opción que no aplica fuerza | ALTERNATIVA DESCARTADA: '#O' (abrir con
    %   fuerza puede soltar un objeto bruscamente)
    % DECISION: safe command '#R' (rest) | REASON: on failure or shutdown, relaxing the
    %   hand applies no force | DISCARDED ALTERNATIVE: '#O' (forceful opening may drop an
    %   object abruptly)
    %
    % Ejemplos / Examples:
    %   create_server_prosthesis_config();                          % HTTP 192.168.1.101
    %   create_server_prosthesis_config('ip', '192.168.1.77');
    %   create_server_prosthesis_config('protocol', 'SIM');         % simulador / simulator
    %
    % Salidas / Outputs:
    %   server_prosthesis : struct guardado / saved struct

    root = fileparts(fileparts(mfilename('fullpath')));
    save_path = fullfile(root, 'config', 'server-prosthesis.mat');

    server_prosthesis = struct();
    server_prosthesis.ip = '192.168.1.101';
    server_prosthesis.port = 8080;
    server_prosthesis.endpoint = '/api/command';
    server_prosthesis.timeout = 0.5;
    server_prosthesis.protocol = 'HTTP';                 % 'HTTP' | 'SIM'
    server_prosthesis.max_consecutive_failures = 5;
    server_prosthesis.safe_command = '#R';

    for k = 1:2:numel(varargin) - 1
        name = char(varargin{k});
        value = varargin{k + 1};
        if strcmpi(name, 'save_path')
            save_path = value;
        elseif isfield(server_prosthesis, name)
            server_prosthesis.(name) = value;
        else
            error('create_server_prosthesis_config:field', ...
                'Campo desconocido / Unknown field: %s', name);
        end
    end

    if ~any(strcmpi(server_prosthesis.protocol, {'HTTP', 'SIM'}))
        error('create_server_prosthesis_config:protocol', ...
            'Protocolo no válido / Invalid protocol: %s', server_prosthesis.protocol);
    end
    server_prosthesis.protocol = upper(server_prosthesis.protocol);

    folder = fileparts(save_path);
    if ~isfolder(folder)
        mkdir(folder);
    end
    save(save_path, 'server_prosthesis');
    fprintf('[%s] server-prosthesis.mat -> %s | %s http://%s:%d%s\n', ...
        char(datetime('now', 'Format', 'HH:mm:ss')), save_path, ...
        server_prosthesis.protocol, server_prosthesis.ip, server_prosthesis.port, ...
        server_prosthesis.endpoint);
end
