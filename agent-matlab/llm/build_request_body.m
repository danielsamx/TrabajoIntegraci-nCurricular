function body_json = build_request_body(cfg_llm, prompt, payload, img_b64, model)
    % BUILD_REQUEST_BODY Construye el JSON de la petición /v1/chat/completions
    %   (formato OpenAI compatible con LM Studio) con TEXTO + IMAGEN.
    %
    % BUILD_REQUEST_BODY Builds the /v1/chat/completions request JSON
    %   (OpenAI-compatible format used by LM Studio) with TEXT + IMAGE.
    %
    % Estructura / Structure:
    %   {"model": ..., "messages": [
    %       {"role":"system","content":"<system prompt>"},
    %       [few-shot user/assistant opcionales / optional],
    %       {"role":"user","content":[
    %           {"type":"text","text":"<payload ASCII>"},
    %           {"type":"image_url","image_url":{"url":"data:image/png;base64,..."}}]}],
    %    "temperature":0, "top_p":1, "max_tokens":200, "stop":[...], "stream":false}
    %
    % DECISIÓN: serializar con jsonencode y enviar el texto tal cual | RAZÓN: control
    %   exacto sobre arrays (content, stop) que webwrite podría aplanar al codificar un
    %   struct | ALTERNATIVA DESCARTADA: pasar el struct directamente a webwrite
    % DECISION: serialize with jsonencode and send the text as-is | REASON: exact control
    %   over arrays (content, stop) that webwrite could flatten when encoding a struct |
    %   DISCARDED ALTERNATIVE: passing the struct directly to webwrite
    %
    % DECISIÓN: el system prompt va igual en cada petición | RAZÓN: LM Studio reutiliza la
    %   caché KV del prefijo idéntico, reduciendo la latencia | ALTERNATIVA DESCARTADA:
    %   insertar datos variables en el system prompt (invalida la caché)
    % DECISION: the system prompt is identical in every request | REASON: LM Studio reuses
    %   the KV cache of the identical prefix, lowering latency | DISCARDED ALTERNATIVE:
    %   inserting variable data in the system prompt (invalidates the cache)
    %
    % DECISIÓN: la imagen es obligatoria (error si falta) | RAZÓN: requisito 2, el LLM
    %   recibe TEXTO + IMAGEN en cada invocación | ALTERNATIVA DESCARTADA: enviar solo texto
    %   si no hay imagen
    % DECISION: the image is mandatory (error if missing) | REASON: requirement 2, the LLM
    %   receives TEXT + IMAGE on every call | DISCARDED ALTERNATIVE: text-only if no image
    %
    % Entradas / Inputs:
    %   cfg_llm : struct de server-llm.mat / struct from server-llm.mat
    %   prompt  : struct de prompt-llm.mat o char con el system prompt
    %             struct from prompt-llm.mat or char with the system prompt
    %   payload : texto ASCII de build_payload / ASCII text from build_payload
    %   img_b64 : imagen PNG en Base64 / Base64 PNG image
    %   model   : identificador del modelo / model identifier
    %
    % Salidas / Outputs:
    %   body_json : char con el JSON / char with the JSON
    %
    % Ejemplo / Example:
    %   body = build_request_body(cfg, prompt_llm, payload, b64, 'qwen2.5-vl-7b-instruct');

    if nargin < 5 || isempty(model)
        model = cfg_llm.models{1};
    end
    if isempty(img_b64)
        error('build_request_body:noImage', ...
            'La imagen es obligatoria / The image is mandatory');
    end

    [system_prompt, few_shot, use_few_shot] = unpack_prompt(prompt);

    messages = {struct('role', 'system', 'content', system_prompt)};

    if use_few_shot
        for k = 1:numel(few_shot)
            messages{end + 1} = struct('role', 'user', 'content', few_shot{k}.input); %#ok<AGROW>
            messages{end + 1} = struct('role', 'assistant', ...
                'content', few_shot{k}.output); %#ok<AGROW>
        end
    end

    user_content = { ...
        struct('type', 'text', 'text', char(payload)), ...
        struct('type', 'image_url', 'image_url', ...
            struct('url', ['data:image/png;base64,', char(img_b64)]))};
    messages{end + 1} = struct('role', 'user', 'content', {user_content});

    body = struct();
    body.model = char(model);
    body.messages = messages;
    body.temperature = cfg_llm.temperature;
    body.top_p = cfg_llm.top_p;
    body.max_tokens = cfg_llm.max_tokens;
    body.stream = false;
    if isfield(cfg_llm, 'stop') && ~isempty(cfg_llm.stop)
        body.stop = cellstr(cfg_llm.stop);
    end
    if isfield(cfg_llm, 'use_json_schema') && cfg_llm.use_json_schema
        body.response_format = struct('type', 'json_schema', ...
            'json_schema', struct('name', 'prosthesis_command', 'strict', true, ...
            'schema', command_schema()));
    end

    body_json = jsonencode(body);
end

% -------------------------------------------------------------------------------------------
function [system_prompt, few_shot, use_few_shot] = unpack_prompt(prompt)
    % UNPACK_PROMPT Extrae el system prompt efectivo y los few-shot del struct.
    % UNPACK_PROMPT Extracts the effective system prompt and the few-shot examples.
    few_shot = {};
    use_few_shot = false;
    if ischar(prompt) || isstring(prompt)
        system_prompt = char(prompt);
        return;
    end
    if isfield(prompt, 'system_prompt_effective') && ~isempty(prompt.system_prompt_effective)
        system_prompt = prompt.system_prompt_effective;
    else
        system_prompt = prompt.system_prompt;
    end
    if isfield(prompt, 'use_few_shot_messages') && prompt.use_few_shot_messages && ...
            isfield(prompt, 'few_shot')
        few_shot = prompt.few_shot;
        if isstruct(few_shot)
            few_shot = num2cell(few_shot);
        end
        use_few_shot = ~isempty(few_shot);
    end
end

% -------------------------------------------------------------------------------------------
function schema = command_schema()
    % COMMAND_SCHEMA JSON Schema de la salida (solo si use_json_schema = true).
    % COMMAND_SCHEMA JSON Schema of the output (only if use_json_schema = true).
    commands = {'A', 'B', 'C', 'D', 'E', 'F', '#O', '#C', '#P', '#R', '#W', '#Y', ...
        '#L', '#M', '#H', '#U', '#G'};
    props = struct();
    props.command = struct('type', 'string', 'enum', {commands});
    props.finger = struct('type', 'string', 'enum', ...
        {{'D1', 'D2', 'D3', 'D4', 'D5', 'WRIST', 'MULTI', 'NONE'}});
    props.action = struct('type', 'string', 'enum', ...
        {{'flex', 'extend', 'hold', 'rest', 'gesture', 'rotate'}});
    props.confidence = struct('type', 'number', 'minimum', 0, 'maximum', 1);
    props.trigger_channels = struct('type', 'array', 'items', ...
        struct('type', 'integer', 'minimum', 1, 'maximum', 8), 'maxItems', 8);
    props.value = struct('type', 'integer', 'minimum', 0, 'maximum', 180);
    schema = struct('type', 'object', 'properties', props, ...
        'required', {{'command', 'finger', 'action', 'confidence', ...
        'trigger_channels', 'value'}}, 'additionalProperties', false);
end
