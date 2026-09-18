function info = label_to_finger(label)
    % LABEL_TO_FINGER Mapea una etiqueta (letra de comando, clase LDA o código de dedo)
    %   a la información completa del dedo o gesto.
    %
    % LABEL_TO_FINGER Maps a label (command letter, LDA class or finger code) to the
    %   full finger or gesture information.
    %
    % DECISIÓN: tabla única y centralizada de dedos/gestos | RAZÓN: el validador, el LDA,
    %   el mapeo RMS->valor y la prótesis usan el mismo mapa y no pueden divergir |
    %   ALTERNATIVA DESCARTADA: tablas duplicadas en cada módulo (riesgo de inconsistencia)
    % DECISION: single centralized finger/gesture table | REASON: validator, LDA,
    %   RMS->value mapping and prosthesis share the same map and cannot diverge |
    %   DISCARDED ALTERNATIVE: duplicated tables per module (inconsistency risk)
    %
    % DECISIÓN: gestos con prefijo '#' ('#C') y dedos con letra sola ('C') |
    %   RAZÓN: la letra C existe como dedo medio y como gesto "cerrar"; el prefijo elimina
    %   la ambigüedad | ALTERNATIVA DESCARTADA: campo extra para desambiguar (frágil)
    % DECISION: gestures use a '#' prefix ('#C') and fingers a bare letter ('C') |
    %   REASON: letter C is both the middle finger and the "close" gesture; the prefix
    %   removes ambiguity | DISCARDED ALTERNATIVE: extra field to disambiguate (fragile)
    %
    % Entradas / Inputs:
    %   label : 'A'..'F', '#O','#C','#P','#R','#W','#Y','#L','#M','#H','#U','#G',
    %           'pulgar','D2'..'D5', 'D1', 'WRIST', 'thumb', ...
    %           o 'list' para obtener la tabla completa / or 'list' for the full table
    %
    % Salidas / Outputs:
    %   info : struct con campos / struct with fields:
    %          command, finger, name_es, name_en, range [lo hi], is_gesture, is_rest,
    %          primary_channels, lda_class, aliases, allowed_actions
    %          (vacío [] si la etiqueta no existe / empty [] if the label is unknown)
    %
    % Ejemplo / Example:
    %   info = label_to_finger('pulgar');   % info.command = 'A', info.range = [0 90]
    %   tbl  = label_to_finger('list');

    persistent table_cache
    if isempty(table_cache)
        table_cache = build_table();
    end

    if nargin < 1 || isempty(label)
        error('label_to_finger:noInput', ...
            'Se requiere una etiqueta / A label is required');
    end

    label = strtrim(char(label));
    if strcmpi(label, 'list')
        info = table_cache;
        return;
    end

    % 1) Coincidencia exacta con el comando / exact match with the command
    idx = find(strcmp({table_cache.command}, upper(label)), 1);

    % 2) Coincidencia con alias (sin distinguir mayúsculas) / alias match (case-insensitive)
    if isempty(idx)
        for k = 1:numel(table_cache)
            if any(strcmpi(label, table_cache(k).aliases))
                idx = k;
                break;
            end
        end
    end

    if isempty(idx)
        info = [];
    else
        info = table_cache(idx);
    end
end

% -------------------------------------------------------------------------------------------
function tbl = build_table()
    % BUILD_TABLE Construye la tabla de dedos y gestos.
    % BUILD_TABLE Builds the finger and gesture table.
    %
    % Canales primarios según el mapa anatómico de referencia (ver prompts/system_es.txt).
    % Primary channels follow the reference anatomical map (see prompts/system_en.txt).
    %
    % DECISIÓN: rango de gestos 0-100 (% de fuerza de agarre) | RAZÓN: un gesto mueve
    %   varios dedos con rangos distintos; el porcentaje es independiente del dedo |
    %   ALTERNATIVA DESCARTADA: ángulo único para todo el gesto
    % DECISION: gesture range 0-100 (% grip strength) | REASON: a gesture moves several
    %   fingers with different ranges; a percentage is finger-independent |
    %   DISCARDED ALTERNATIVE: single angle for the whole gesture

    fa = {'flex', 'extend', 'hold'};     % acciones de dedo / finger actions
    ga = {'gesture', 'hold'};            % acciones de gesto / gesture actions

    tbl = struct('command', {}, 'finger', {}, 'name_es', {}, 'name_en', {}, ...
        'range', {}, 'is_gesture', {}, 'is_rest', {}, 'primary_channels', {}, ...
        'lda_class', {}, 'aliases', {}, 'allowed_actions', {});

    % Dedos individuales / single fingers
    tbl = add_row(tbl, 'A', 'D1', 'pulgar', 'thumb', [0 90], false, [5 6], ...
        'pulgar', {'pulgar', 'thumb', 'D1'}, fa);
    tbl = add_row(tbl, 'B', 'D2', 'indice', 'index', [0 120], false, [4 7], ...
        'D2', {'D2', 'index', 'indice'}, fa);
    tbl = add_row(tbl, 'C', 'D3', 'medio', 'middle', [0 120], false, [3 7], ...
        'D3', {'D3', 'middle', 'medio'}, fa);
    tbl = add_row(tbl, 'D', 'D4', 'anular', 'ring', [0 120], false, [2 8], ...
        'D4', {'D4', 'ring', 'anular'}, fa);
    tbl = add_row(tbl, 'E', 'D5', 'menique', 'little', [0 120], false, [1 8], ...
        'D5', {'D5', 'little', 'pinky', 'menique'}, fa);
    tbl = add_row(tbl, 'F', 'WRIST', 'rotacion de muneca', 'wrist rotation', [0 180], ...
        false, [5 6 7], '', {'WRIST', 'wrist', 'muneca'}, {'rotate', 'hold'});

    % Gestos preestablecidos / preset gestures
    tbl = add_row(tbl, '#O', 'MULTI', 'mano abierta', 'open hand', [0 100], true, ...
        [6 7 8], '', {'open', 'abrir'}, ga);
    tbl = add_row(tbl, '#C', 'MULTI', 'puno / agarre de fuerza', 'fist / power grip', ...
        [0 100], true, [1 2 3 4 5], '', {'close', 'fist', 'cerrar', 'puno'}, ga);
    tbl = add_row(tbl, '#P', 'MULTI', 'pinza fina', 'precision pinch', [0 100], true, ...
        [4 5], '', {'pinch', 'pinza'}, ga);
    tbl = add_row(tbl, '#R', 'NONE', 'reposo', 'rest', [0 0], true, ...
        [], '', {'rest', 'reposo'}, {'rest', 'hold'});
    tbl = add_row(tbl, '#W', 'MULTI', 'tres dedos (W)', 'three fingers (W)', [0 100], ...
        true, [1 5 7], '', {'three'}, ga);
    tbl = add_row(tbl, '#Y', 'MULTI', 'shaka (Y)', 'shaka (Y)', [0 100], true, ...
        [2 3 4 6], '', {'shaka'}, ga);
    tbl = add_row(tbl, '#L', 'MULTI', 'forma de L', 'L shape', [0 100], true, ...
        [1 2 3 6], '', {'lshape'}, ga);
    tbl = add_row(tbl, '#M', 'MULTI', 'agarre de raton', 'mouse grip', [0 100], true, ...
        [1 2 3 4 5], '', {'mouse', 'raton'}, ga);
    tbl = add_row(tbl, '#H', 'MULTI', 'gancho', 'hook grip', [0 100], true, ...
        [1 2 3 4 6], '', {'hook', 'gancho'}, ga);
    tbl = add_row(tbl, '#U', 'MULTI', 'U (indice + medio)', 'U (index + middle)', ...
        [0 100], true, [1 2 5], '', {'ugesture'}, ga);
    tbl = add_row(tbl, '#G', 'MULTI', 'senalar', 'point', [0 100], true, ...
        [1 2 3 5], '', {'point', 'senalar'}, ga);
    tbl = tbl(:);
end

% -------------------------------------------------------------------------------------------
function tbl = add_row(tbl, command, finger, name_es, name_en, range, is_gesture, ...
        channels, lda_class, aliases, actions)
    % ADD_ROW Añade una fila a la tabla. / Appends a row to the table.
    k = numel(tbl) + 1;
    tbl(k).command = command;
    tbl(k).finger = finger;
    tbl(k).name_es = name_es;
    tbl(k).name_en = name_en;
    tbl(k).range = range;
    tbl(k).is_gesture = is_gesture;
    tbl(k).is_rest = strcmp(command, '#R');
    tbl(k).primary_channels = channels;
    tbl(k).lda_class = lda_class;
    tbl(k).aliases = aliases;
    tbl(k).allowed_actions = actions;
end
