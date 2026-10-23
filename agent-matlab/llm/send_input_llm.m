function reply = send_input_llm(llm, system_prompt, payload, image_files)
% SEND_INPUT_LLM Envía TEXTO + IMÁGENES (0 a 4 PNG) al LLM y devuelve su respuesta.
%   Prueba los puertos de llm.ports en orden hasta que uno responda.
%   reply.ok, reply.content (texto del modelo), reply.port, reply.latency_ms, reply.error

reply = struct('ok', false, 'content', '', 'port', NaN, 'latency_ms', NaN, 'error', '');
timer = tic;                                                % mide la latencia total

user_content = {struct('type', 'text', 'text', payload)};   % mensaje del usuario: primero el texto
sizes = zeros(1, numel(image_files));                       % bytes de cada PNG (para la consola)
for k = 1:numel(image_files)                                % después, cada imagen marcada
    fid = fopen(image_files{k}, 'r');                       % abre el PNG
    png = fread(fid, Inf, '*uint8');                        % lee sus bytes
    fclose(fid);                                            % cierra el archivo
    sizes(k) = numel(png);
    image_b64 = char(matlab.net.base64encode(png'));        % bytes -> texto Base64
    user_content{end + 1} = struct('type', 'image_url', 'image_url', ...
        struct('url', ['data:image/png;base64,' image_b64])); %#ok<AGROW>
end
body = struct();                                            % cuerpo de la petición
body.model = llm.model;                                     % modelo de LM Studio
body.messages = {struct('role', 'system', 'content', system_prompt), ... % reglas del clasificador
    struct('role', 'user', 'content', {user_content})};     % datos de esta ventana
body.temperature = llm.temperature;                         % salida determinista
body.max_tokens = llm.max_tokens;                           % longitud máxima
body.stop = llm.stop;                                       % cortar al cerrar el JSON
body.stream = false;                                        % respuesta completa de una vez
body_json = jsonencode(body);                               % struct -> texto JSON

log_msg('LLM', 'Petición: modelo=%s | temperature=%g | max_tokens=%d | %d bytes', ...
    llm.model, llm.temperature, llm.max_tokens, numel(body_json));
log_msg('LLM', '  system : (system prompt de %d caracteres)', numel(system_prompt));
log_msg('LLM', '  texto  : %s', payload);
for k = 1:numel(image_files)
    log_msg('LLM', '  imagen %d: %s (%d bytes PNG)', k, image_files{k}, sizes(k));
end
if isempty(image_files)
    log_msg('LLM', '  imágenes: ninguna (solo texto)');
end

options = weboptions('MediaType', 'application/json', ...   % enviamos JSON
    'ContentType', 'json', ...                              % esperamos JSON
    'Timeout', llm.timeout, ...                             % espera máxima por puerto
    'HeaderFields', {'Authorization', ['Bearer ' llm.api_key]}); % clave de la API

for port = llm.ports                                        % cada puerto configurado
    url = sprintf('http://%s:%d%s', llm.ip, port, llm.endpoint); % dirección completa
    log_msg('LLM', 'POST %s', url);
    try
        raw = webwrite(url, body_json, options);            % envía y espera la respuesta
        log_msg('LLM', 'Respuesta HTTP completa: %s', jsonencode(raw)); % todo lo que devolvió
        choice = raw.choices(1);                            % primera opción de la respuesta
        if iscell(choice)                                   % a veces llega como celda
            choice = choice{1};
        end
        reply.content = char(choice.message.content);       % texto generado por el modelo
        reply.ok = true;                                    % hubo respuesta
        reply.port = port;                                  % puerto que respondió
        break;                                              % no hace falta probar más puertos
    catch err
        reply.error = sprintf('puerto %d: %s', port, err.message); % guarda el motivo
        log_msg('LLM', 'Fallo en %s', reply.error);
    end
end

reply.latency_ms = 1000 * toc(timer);                       % tiempo total en ms
log_msg('LLM', 'Texto generado (%.0f ms): %s', reply.latency_ms, reply.content);
end
