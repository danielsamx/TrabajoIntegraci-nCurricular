function passed = test_payload()
    % TEST_PAYLOAD Prueba build_payload y la coherencia entre el prompt y el código.
    %
    % TEST_PAYLOAD Tests build_payload and the consistency between prompt and code.
    %
    % Comprueba / Checks:
    %   1. Formato exacto del payload (regex) / exact payload format (regex)
    %   2. Recorte de NaN, negativos y >1 / clipping of NaN, negatives and >1
    %   3. Formatos de PREV y CALIB / PREV and CALIB formats
    %   4. Solo ASCII y longitud acotada / ASCII only and bounded length
    %   5. Las salidas few-shot son válidas para is_valid_response
    %      Few-shot outputs are valid for is_valid_response
    %   6. rms_to_value e is_composite_gesture reproducen los ejemplos del prompt
    %      rms_to_value and is_composite_gesture reproduce the prompt examples
    %   7. parse_llm_response repara la llave final cortada por el stop token
    %      parse_llm_response repairs the final brace cut by the stop token
    %
    % DECISIÓN: verificar los ejemplos del prompt contra el código | RAZÓN: si alguien
    %   cambia una regla en el prompt o en el código, el test detecta la divergencia |
    %   ALTERNATIVA DESCARTADA: probar solo el formato (no detecta incoherencias)
    % DECISION: check prompt examples against the code | REASON: if someone changes a rule
    %   in the prompt or in the code, the test catches the divergence |
    %   DISCARDED ALTERNATIVE: testing only the format (misses inconsistencies)
    %
    % Salidas / Outputs:
    %   passed : true si todas las comprobaciones pasan / true if all checks pass
    %
    % Ejemplo / Example:
    %   ok = test_payload();

    root = add_project_paths();
    fprintf('\n--- test_payload ---\n');
    results = true(0);

    calib = struct('class_names', {{'pulgar', 'D2', 'D3', 'D4', 'D5'}}, ...
        'top_channels', [5 6; 4 7; 3 7; 2 8; 1 8], 'is_default', false);
    rms_values = [0.06, 0.08, 0.21, 0.82, 0.19, 0.05, 0.44, 0.07];
    mav_values = [0.05, 0.07, 0.18, 0.79, 0.17, 0.04, 0.41, 0.06];
    prev = struct('command', '#R', 'value', 0);

    % 1) Formato / format
    payload = build_payload(rms_values, mav_values, 'ACTIVE', calib, prev, 10240);
    expected = ['RMS:[0.06,0.08,0.21,0.82,0.19,0.05,0.44,0.07]|', ...
        'MAV:[0.05,0.07,0.18,0.79,0.17,0.04,0.41,0.06]|STATE:ACTIVE|', ...
        'CALIB:[D1=5+6,D2=4+7,D3=3+7,D4=2+8,D5=1+8]|PREV:#R:000|T:10240'];
    results(end + 1) = check('payload exacto / exact payload', strcmp(payload, expected));
    pattern = ['^RMS:\[(\d\.\d{2},){7}\d\.\d{2}\]\|MAV:\[(\d\.\d{2},){7}\d\.\d{2}\]\|', ...
        'STATE:[A-Z_]+\|CALIB:\[[^\]]*\]\|PREV:[^|]+\|T:\d+$'];
    results(end + 1) = check('regex de formato / format regex', ...
        ~isempty(regexp(payload, pattern, 'once')));

    % 2) Recorte / clipping
    dirty = [NaN, -0.2, 1.7, 0.5, Inf, 0.123, 0.999, 0];
    payload = build_payload(dirty, dirty, 'active', [], [], 1);
    results(end + 1) = check('recorte / clipping', contains(payload, ...
        'RMS:[0.00,0.00,1.00,0.50,0.00,0.12,1.00,0.00]'));
    results(end + 1) = check('estado en mayúsculas / upper-case state', ...
        contains(payload, '|STATE:ACTIVE|'));

    % 3) PREV y CALIB / PREV and CALIB
    results(end + 1) = check('PREV vacío -> NONE / empty PREV', contains(payload, 'PREV:NONE'));
    results(end + 1) = check('CALIB vacío -> NONE / empty CALIB', ...
        contains(payload, 'CALIB:[NONE]'));
    payload = build_payload(rms_values, mav_values, 'TRANSITION', calib, ...
        struct('command', 'B', 'value', 95.4), 5);
    results(end + 1) = check('PREV struct -> B:095', contains(payload, 'PREV:B:095'));
    calib.is_default = true;
    payload = build_payload(rms_values, mav_values, 'REST', calib, 'C:060', 5);
    results(end + 1) = check('CALIB DEFAULT', contains(payload, 'D5=1+8,DEFAULT]'));
    results(end + 1) = check('PREV texto / text', contains(payload, 'PREV:C:060'));

    % 4) ASCII y longitud / ASCII and length
    results(end + 1) = check('solo ASCII / ASCII only', all(double(payload) < 128));
    results(end + 1) = check('longitud < 300 / length < 300', numel(payload) < 300);

    % 5-6) Ejemplos few-shot / few-shot examples
    examples = read_examples(fullfile(root, 'prompts', 'few_shot_examples.jsonl'));
    all_valid = true;
    values_match = true;
    gestures_match = true;
    for k = 1:numel(examples)
        ex = examples{k};
        [cmd, ok] = parse_llm_response(jsonencode(ex.output));
        [valid, why] = is_valid_response(cmd);
        if ~(ok && valid)
            fprintf('      ejemplo %d no válido / invalid: %s\n', ex.id, why);
            all_valid = false;
            continue;
        end
        tok = regexp(ex.input, 'RMS:\[([^\]]*)\]', 'tokens', 'once');
        r = str2double(strsplit(tok{1}, ','));
        if any(strcmp(cmd.action, {'flex', 'extend', 'gesture', 'rotate'}))
            computed = rms_to_value(r, cmd.command, cmd.action, [], cmd.trigger_channels);
            if computed ~= cmd.value
                fprintf('      ejemplo %d: value %d != calculado / computed %d\n', ...
                    ex.id, cmd.value, computed);
                values_match = false;
            end
        end
        if strcmp(cmd.action, 'gesture')
            [~, gesture, channels] = is_composite_gesture(r);
            if ~strcmp(gesture, cmd.command) || ~isequal(channels, cmd.trigger_channels)
                fprintf('      ejemplo %d: gesto %s != %s\n', ex.id, gesture, cmd.command);
                gestures_match = false;
            end
        end
    end
    results(end + 1) = check(sprintf('%d ejemplos válidos / valid examples', ...
        numel(examples)), all_valid && numel(examples) >= 5);
    results(end + 1) = check('value = rms_to_value en ejemplos / in examples', values_match);
    results(end + 1) = check('gestos = is_composite_gesture / gestures', gestures_match);

    % 7) Reparación del stop token / stop-token repair
    truncated = ['{"command":"B","finger":"D2","action":"flex","confidence":0.92,', ...
        '"trigger_channels":[4,7],"value":95'];
    [cmd, ok] = parse_llm_response(truncated);
    results(end + 1) = check('reparación de "}" / brace repair', ok && is_valid_response(cmd));
    [cmd, ok] = parse_llm_response(['```json', newline, expected_json(), newline, '```']);
    results(end + 1) = check('cercas markdown / markdown fences', ok && is_valid_response(cmd));
    [~, ok] = parse_llm_response('No puedo ayudar con eso.');
    results(end + 1) = check('texto sin JSON rechazado / non-JSON rejected', ~ok);
    bad = jsondecode(['{"command":"C","finger":"MULTI","action":"flex","confidence":0.9,', ...
        '"trigger_channels":[3],"value":50}']);
    results(end + 1) = check('C con finger MULTI rechazado / rejected', ...
        ~is_valid_response(bad));

    passed = all(results);
    fprintf('--- test_payload: %s (%d/%d) ---\n', pass_text(passed), sum(results), ...
        numel(results));
end

% -------------------------------------------------------------------------------------------
function text = expected_json()
    % EXPECTED_JSON Respuesta de ejemplo válida. / Valid sample answer.
    text = ['{"command":"#C","finger":"MULTI","action":"gesture","confidence":0.93,', ...
        '"trigger_channels":[4,2,1,3,5],"value":77}'];
end

% -------------------------------------------------------------------------------------------
function examples = read_examples(file_path)
    % READ_EXAMPLES Lee el JSONL de ejemplos. / Reads the examples JSONL.
    fid = fopen(file_path, 'r', 'n', 'UTF-8');
    cleaner = onCleanup(@() fclose(fid));
    examples = {};
    while true
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end
        if ~isempty(strtrim(line))
            examples{end + 1} = jsondecode(line); %#ok<AGROW>
        end
    end
end

% -------------------------------------------------------------------------------------------
function ok = check(name, condition)
    % CHECK Imprime el resultado de una comprobación. / Prints a check result.
    ok = logical(condition);
    fprintf('  [%s] %s\n', pass_text(ok), name);
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
