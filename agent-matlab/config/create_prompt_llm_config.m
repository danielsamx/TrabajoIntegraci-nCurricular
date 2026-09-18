function prompt_llm = create_prompt_llm_config(varargin)
    % CREATE_PROMPT_LLM_CONFIG Genera config/prompt-llm.mat a partir de prompts/*.txt.
    %
    % CREATE_PROMPT_LLM_CONFIG Generates config/prompt-llm.mat from prompts/*.txt.
    %
    % Contenido / Content:
    %   language               : 'es' | 'en'
    %   system_prompt          : texto de prompts/system_<language>.txt
    %   few_shot               : cell de structs (input, output) de few_shot_examples.jsonl
    %   use_few_shot_messages  : enviar los few-shot como mensajes (false por defecto)
    %   calibration_template   : sección del idioma de calibration_template.txt
    %   system_prompt_effective: '' (main.m le añade la calibración al arrancar)
    %   image                  : width, height, render_mode de la imagen del VLM
    %
    % DECISIÓN: los .txt son la fuente y el .mat una copia compilada | RAZÓN: el prompt se
    %   edita y versiona cómodamente en texto, y en ejecución se carga sin leer disco |
    %   ALTERNATIVA DESCARTADA: escribir el prompt dentro de un .m (difícil de mantener)
    % DECISION: .txt files are the source and the .mat a compiled copy | REASON: the prompt
    %   is easy to edit and version as text, and is loaded at runtime without disk reads |
    %   DISCARDED ALTERNATIVE: writing the prompt inside a .m file (hard to maintain)
    %
    % DECISIÓN: few-shot como mensajes desactivado por defecto | RAZÓN: los 10 ejemplos ya
    %   están en el system prompt; repetirlos como mensajes duplica tokens y latencia |
    %   ALTERNATIVA DESCARTADA: activarlo siempre
    % DECISION: few-shot as messages disabled by default | REASON: the 10 examples are
    %   already in the system prompt; repeating them as messages doubles tokens and latency |
    %   DISCARDED ALTERNATIVE: always enabled
    %
    % DECISIÓN: lectura explícita en UTF-8 | RAZÓN: los prompts tienen tildes y MATLAB en
    %   Windows puede usar otra codificación por defecto | ALTERNATIVA DESCARTADA: fileread
    %   sin codificación
    % DECISION: explicit UTF-8 reading | REASON: prompts contain accents and MATLAB on
    %   Windows may default to another encoding | DISCARDED ALTERNATIVE: fileread without
    %   encoding
    %
    % Entradas (nombre-valor) / Inputs (name-value):
    %   'language'              : 'es' (defecto / default) | 'en'
    %   'use_few_shot_messages' : false
    %   'image_width'           : 640
    %   'image_height'          : 480
    %   'render_mode'           : 'figure' | 'raster'
    %   'save_path'             : ruta de salida / output path
    %
    % Ejemplo / Example:
    %   create_prompt_llm_config('language', 'en');
    %   create_prompt_llm_config('render_mode', 'raster', 'image_width', 320, ...
    %                            'image_height', 240);        % menor latencia / lower latency

    root = fileparts(fileparts(mfilename('fullpath')));
    prompts_dir = fullfile(root, 'prompts');

    p = inputParser;
    addParameter(p, 'language', 'es', @(x) any(strcmpi(x, {'es', 'en'})));
    addParameter(p, 'use_few_shot_messages', false);
    addParameter(p, 'image_width', 640);
    addParameter(p, 'image_height', 480);
    addParameter(p, 'render_mode', 'figure', @(x) any(strcmpi(x, {'figure', 'raster'})));
    addParameter(p, 'save_path', fullfile(root, 'config', 'prompt-llm.mat'));
    parse(p, varargin{:});
    opts = p.Results;
    language = lower(char(opts.language));

    system_file = fullfile(prompts_dir, ['system_', language, '.txt']);
    few_shot_file = fullfile(prompts_dir, 'few_shot_examples.jsonl');
    template_file = fullfile(prompts_dir, 'calibration_template.txt');

    prompt_llm = struct();
    prompt_llm.language = language;
    prompt_llm.system_prompt = strtrim(read_utf8(system_file));
    prompt_llm.few_shot = read_few_shot(few_shot_file);
    prompt_llm.use_few_shot_messages = logical(opts.use_few_shot_messages);
    prompt_llm.calibration_template = extract_section(read_utf8(template_file), language);
    prompt_llm.system_prompt_effective = '';
    prompt_llm.image = struct('width', opts.image_width, 'height', opts.image_height, ...
        'render_mode', lower(char(opts.render_mode)));
    prompt_llm.created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    prompt_llm.source_files = {system_file, few_shot_file, template_file};

    folder = fileparts(opts.save_path);
    if ~isfolder(folder)
        mkdir(folder);
    end
    save(opts.save_path, 'prompt_llm');
    fprintf('[%s] prompt-llm.mat -> %s | idioma/language=%s | %d caracteres | %d few-shot\n', ...
        char(datetime('now', 'Format', 'HH:mm:ss')), opts.save_path, language, ...
        numel(prompt_llm.system_prompt), numel(prompt_llm.few_shot));
end

% -------------------------------------------------------------------------------------------
function text = read_utf8(file_path)
    % READ_UTF8 Lee un archivo de texto en UTF-8. / Reads a UTF-8 text file.
    fid = fopen(file_path, 'r', 'n', 'UTF-8');
    if fid < 0
        error('create_prompt_llm_config:file', 'No se encuentra / Not found: %s', file_path);
    end
    cleaner = onCleanup(@() fclose(fid));
    text = fread(fid, [1, Inf], '*char');
    text = strrep(text, char([13, 10]), newline);   % CRLF -> LF
end

% -------------------------------------------------------------------------------------------
function examples = read_few_shot(file_path)
    % READ_FEW_SHOT Lee el JSONL: input (texto) y output (JSON compacto).
    % READ_FEW_SHOT Reads the JSONL: input (text) and output (compact JSON).
    text_lines = splitlines(string(read_utf8(file_path)));
    examples = {};
    for k = 1:numel(text_lines)
        line = strtrim(text_lines(k));
        if strlength(line) == 0
            continue;
        end
        item = jsondecode(char(line));
        output = item.output;
        output.trigger_channels = num2cell(output.trigger_channels(:)');
        examples{end + 1} = struct('input', item.input, ...
            'output', jsonencode(output)); %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------------------------
function section = extract_section(text, language)
    % EXTRACT_SECTION Devuelve el bloque '### ES' o '### EN' de la plantilla.
    % EXTRACT_SECTION Returns the '### ES' or '### EN' block of the template.
    text_lines = splitlines(string(text));
    marker = "### " + upper(string(language));
    start = find(strtrim(text_lines) == marker, 1);
    if isempty(start)
        section = char(strtrim(text));
        return;
    end
    stop = numel(text_lines);
    for k = start + 1:numel(text_lines)
        if startsWith(strtrim(text_lines(k)), "### ")
            stop = k - 1;
            break;
        end
    end
    section = char(strjoin(text_lines(start + 1:stop), newline));
    section = strtrim(section);
end
