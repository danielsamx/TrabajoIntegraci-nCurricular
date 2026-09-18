function [cmd, ok, err_msg] = parse_llm_response(raw)
    % PARSE_LLM_RESPONSE Extrae y decodifica el JSON de comando de la respuesta de
    %   LM Studio, reparando los defectos habituales.
    %
    % PARSE_LLM_RESPONSE Extracts and decodes the command JSON from the LM Studio
    %   response, repairing the usual defects.
    %
    % Reparaciones / Repairs:
    %   - Bloques <think>...</think> y cercas ```json eliminados
    %     <think>...</think> blocks and ```json fences removed
    %   - Texto antes/después del objeto JSON ignorado
    %     Text before/after the JSON object ignored
    %   - Llave de cierre faltante añadida (el stop token '}\n' elimina la '}' final)
    %     Missing closing brace added (the '}\n' stop token removes the final '}')
    %
    % DECISIÓN: reparar la llave final en vez de quitar el stop token | RAZÓN: el stop
    %   '}\n' corta la generación en cuanto termina el objeto (menos latencia), pero LM
    %   Studio no devuelve la secuencia de parada | ALTERNATIVA DESCARTADA: depender solo de
    %   max_tokens (el modelo puede seguir escribiendo texto)
    % DECISION: repair the final brace instead of dropping the stop token | REASON: the
    %   '}\n' stop ends generation as soon as the object is complete (lower latency), but LM
    %   Studio does not return the stop sequence | DISCARDED ALTERNATIVE: relying only on
    %   max_tokens (the model may keep writing text)
    %
    % Entradas / Inputs:
    %   raw : respuesta decodificada de webwrite (struct con choices), struct message, o
    %         texto / decoded webwrite response (struct with choices), message struct, or text
    %
    % Salidas / Outputs:
    %   cmd     : struct normalizado (command, finger, action, confidence,
    %             trigger_channels, value, source='llm') o [] si falla
    %             normalized struct or [] on failure
    %   ok      : true si se decodificó un objeto JSON / true if a JSON object was decoded
    %   err_msg : descripción del error ('' si ok) / error description ('' if ok)
    %
    % Ejemplo / Example:
    %   [cmd, ok] = parse_llm_response('{"command":"B","finger":"D2","action":"flex",...');

    cmd = [];
    ok = false;
    err_msg = '';

    try
        text = extract_text(raw);
    catch err
        err_msg = ['cannot extract content: ', err.message];
        return;
    end

    text = regexprep(text, '<think>.*?</think>', '');
    text = regexprep(text, '```(json|JSON)?', '');
    text = strtrim(text);
    if isempty(text)
        err_msg = 'empty content';
        return;
    end

    first_brace = find(text == '{', 1, 'first');
    if isempty(first_brace)
        err_msg = 'no JSON object found';
        return;
    end
    last_brace = find(text == '}', 1, 'last');
    if isempty(last_brace) || last_brace < first_brace
        json_text = strtrim(text(first_brace:end));
    else
        json_text = text(first_brace:last_brace);
    end

    % Reparación de llaves y corchetes / brace and bracket repair
    json_text = regexprep(json_text, ',\s*$', '');
    missing_brackets = sum(json_text == '[') - sum(json_text == ']');
    if missing_brackets > 0
        json_text = [json_text, repmat(']', 1, missing_brackets)];
    end
    missing_braces = sum(json_text == '{') - sum(json_text == '}');
    if missing_braces > 0
        json_text = [json_text, repmat('}', 1, missing_braces)];
    end

    try
        decoded = jsondecode(json_text);
    catch err
        err_msg = ['invalid JSON: ', err.message];
        return;
    end

    if ~isstruct(decoded) || ~isscalar(decoded)
        err_msg = 'JSON is not a single object';
        return;
    end

    cmd = normalize_fields(decoded);
    ok = true;
end

% -------------------------------------------------------------------------------------------
function text = extract_text(raw)
    % EXTRACT_TEXT Obtiene el texto del asistente de cualquier forma de respuesta.
    % EXTRACT_TEXT Gets the assistant text from any response shape.
    if ischar(raw) || isstring(raw)
        text = char(raw);
        return;
    end
    if ~isstruct(raw)
        error('unsupported response type: %s', class(raw));
    end
    if isfield(raw, 'choices')
        choices = raw.choices;
        if iscell(choices)
            first_choice = choices{1};
        else
            first_choice = choices(1);
        end
        message = first_choice.message;
    elseif isfield(raw, 'message')
        message = raw.message;
    elseif isfield(raw, 'content')
        message = raw;
    else
        error('response without choices/message/content');
    end

    content = message.content;
    if ischar(content) || isstring(content)
        text = char(content);
    elseif iscell(content) || isstruct(content)
        % Contenido multiparte / multipart content
        if isstruct(content)
            content = num2cell(content);
        end
        parts = {};
        for k = 1:numel(content)
            part = content{k};
            if ischar(part)
                parts{end + 1} = part; %#ok<AGROW>
            elseif isstruct(part) && isfield(part, 'text')
                parts{end + 1} = char(part.text); %#ok<AGROW>
            end
        end
        text = strjoin(parts, '');
    else
        text = '';
    end
end

% -------------------------------------------------------------------------------------------
function cmd = normalize_fields(decoded)
    % NORMALIZE_FIELDS Normaliza tipos y mayúsculas de los campos conocidos.
    % NORMALIZE_FIELDS Normalizes types and casing of the known fields.
    cmd = decoded;
    if isfield(cmd, 'command') && (ischar(cmd.command) || isstring(cmd.command))
        cmd.command = upper(strtrim(char(cmd.command)));
    end
    if isfield(cmd, 'finger') && (ischar(cmd.finger) || isstring(cmd.finger))
        cmd.finger = upper(strtrim(char(cmd.finger)));
    end
    if isfield(cmd, 'action') && (ischar(cmd.action) || isstring(cmd.action))
        cmd.action = lower(strtrim(char(cmd.action)));
    end
    if isfield(cmd, 'confidence') && ischar(cmd.confidence)
        cmd.confidence = str2double(cmd.confidence);
    end
    if isfield(cmd, 'value') && ischar(cmd.value)
        cmd.value = str2double(cmd.value);
    end
    if isfield(cmd, 'trigger_channels')
        channels = cmd.trigger_channels;
        if iscell(channels)
            numeric = cellfun(@(c) isnumeric(c) && isscalar(c), channels);
            if all(numeric)
                channels = cell2mat(channels);
            end
        end
        if isnumeric(channels)
            channels = double(channels(:)');
        end
        cmd.trigger_channels = channels;
    end
    cmd.source = 'llm';
end
