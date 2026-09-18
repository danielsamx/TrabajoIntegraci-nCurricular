function payload = build_payload(rms_values, mav_values, state, calib, prev_command, t_ms)
    % BUILD_PAYLOAD Construye el payload ASCII compacto que recibe el LLM.
    %
    % BUILD_PAYLOAD Builds the compact ASCII payload sent to the LLM.
    %
    % Formato / Format:
    %   RMS:[r1,..,r8]|MAV:[m1,..,m8]|STATE:<estado>|CALIB:[D1=a+b,..]|PREV:<cmd>:<val>|T:<ms>
    %
    % Ejemplo / Example:
    %   RMS:[0.06,0.08,0.21,0.82,0.19,0.05,0.44,0.07]|MAV:[...]|STATE:ACTIVE|
    %   CALIB:[D1=5+6,D2=4+7,D3=3+7,D4=2+8,D5=1+8]|PREV:#R:000|T:51234
    %
    % DECISIÓN: incluir PREV | RAZÓN: da contexto temporal al LLM (coherencia entre
    %   ciclos, regla de mantener en TRANSITION/NOISE) | ALTERNATIVA DESCARTADA: solo
    %   ventana actual (sin coherencia)
    % DECISION: include PREV | REASON: gives the LLM temporal context (cycle-to-cycle
    %   coherence, hold rule in TRANSITION/NOISE) | DISCARDED ALTERNATIVE: current window
    %   only (no coherence)
    %
    % DECISIÓN: 2 decimales y separadores de un carácter | RAZÓN: minimiza tokens (menor
    %   latencia) sin perder resolución útil (0.01 << umbrales) | ALTERNATIVA DESCARTADA:
    %   JSON (el doble de tokens por las comillas y claves)
    % DECISION: 2 decimals and single-character separators | REASON: minimizes tokens
    %   (lower latency) without losing useful resolution (0.01 << thresholds) |
    %   DISCARDED ALTERNATIVE: JSON (twice the tokens due to quotes and keys)
    %
    % DECISIÓN: CALIB = 2 canales dominantes por dedo del usuario | RAZÓN: permite al LLM
    %   corregir rotaciones del brazalete respecto al mapa de referencia | ALTERNATIVA
    %   DESCARTADA: enviar los 16 valores de reposo/MVC (el LLM no los necesita, ya están
    %   aplicados en la normalización)
    % DECISION: CALIB = the user's 2 dominant channels per finger | REASON: lets the LLM
    %   correct armband rotations with respect to the reference map | DISCARDED
    %   ALTERNATIVE: sending the 16 rest/MVC values (the LLM does not need them, they are
    %   already applied by normalization)
    %
    % Entradas / Inputs:
    %   rms_values   : RMS 1x8 normalizado / normalized 1x8 RMS
    %   mav_values   : MAV 1x8 normalizado / normalized 1x8 MAV
    %   state        : 'REST'|'TRANSITION'|'ACTIVE'|'NOISE'
    %   calib        : struct de calibración (o []) / calibration struct (or [])
    %   prev_command : struct con command/value, texto, o [] / struct, text or []
    %   t_ms         : (opcional) tiempo en ms; por defecto, ms del día
    %                  (optional) time in ms; default: milliseconds of the day
    %
    % Salidas / Outputs:
    %   payload : char ASCII / ASCII char

    if nargin < 4
        calib = [];
    end
    if nargin < 5
        prev_command = [];
    end
    if nargin < 6 || isempty(t_ms)
        now_time = datetime('now');
        t_ms = round(milliseconds(timeofday(now_time)));
    end

    state_text = regexprep(upper(char(state)), '[^A-Z_]', '');
    if isempty(state_text)
        state_text = 'UNKNOWN';
    end

    payload = sprintf('RMS:[%s]|MAV:[%s]|STATE:%s|CALIB:[%s]|PREV:%s|T:%d', ...
        format_vector(rms_values), format_vector(mav_values), state_text, ...
        format_calibration(calib), format_previous(prev_command), round(t_ms));

    % Garantiza ASCII puro / guarantees pure ASCII
    payload(double(payload) > 127) = '?';
end

% -------------------------------------------------------------------------------------------
function text = format_vector(values)
    % FORMAT_VECTOR Recorta a [0,1] y formatea con 2 decimales.
    % FORMAT_VECTOR Clips to [0,1] and formats with 2 decimals.
    values = double(values(:)');
    values(~isfinite(values)) = 0;
    values = min(max(values, 0), 1);
    text = sprintf('%.2f,', values);
    text = text(1:end - 1);
end

% -------------------------------------------------------------------------------------------
function text = format_calibration(calib)
    % FORMAT_CALIBRATION Canales dominantes por dedo, p. ej. 'D1=5+6,D2=4+7'.
    % FORMAT_CALIBRATION Dominant channels per finger, e.g. 'D1=5+6,D2=4+7'.
    text = 'NONE';
    if isempty(calib) || ~isstruct(calib) || ~isfield(calib, 'top_channels') || ...
            ~isfield(calib, 'class_names') || isempty(calib.top_channels)
        return;
    end
    parts = cell(1, numel(calib.class_names));
    for k = 1:numel(calib.class_names)
        info = label_to_finger(calib.class_names{k});
        channels = calib.top_channels(k, :);
        parts{k} = sprintf('%s=%s', info.finger, ...
            strjoin(arrayfun(@num2str, channels, 'UniformOutput', false), '+'));
    end
    text = strjoin(parts, ',');
    if isfield(calib, 'is_default') && calib.is_default
        text = [text, ',DEFAULT'];
    end
end

% -------------------------------------------------------------------------------------------
function text = format_previous(prev_command)
    % FORMAT_PREVIOUS Formatea el comando previo como '<cmd>:<valor 3 dígitos>'.
    % FORMAT_PREVIOUS Formats the previous command as '<cmd>:<3-digit value>'.
    if isempty(prev_command)
        text = 'NONE';
    elseif ischar(prev_command) || isstring(prev_command)
        text = char(prev_command);
    elseif isstruct(prev_command) && isfield(prev_command, 'command')
        value = 0;
        if isfield(prev_command, 'value') && ~isempty(prev_command.value) && ...
                isfinite(prev_command.value)
            value = round(prev_command.value);
        end
        text = sprintf('%s:%03d', char(prev_command.command), value);
    else
        text = 'NONE';
    end
end
