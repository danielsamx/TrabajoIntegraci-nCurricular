function value = rms_to_value(rms_norm, command, action, prev_value, trigger_channels)
    % RMS_TO_VALUE Convierte la activación RMS normalizada en el valor del comando
    %   (ángulo en grados para dedos, % de fuerza para gestos).
    %
    % RMS_TO_VALUE Converts the normalized RMS activation into the command value
    %   (angle in degrees for fingers, % strength for gestures).
    %
    % Reglas (idénticas a las del system prompt) / Rules (identical to the system prompt):
    %   s = clamp((a - 0.15) / 0.85, 0, 1)
    %   flex    : value = lo + (hi - lo) * s        (a = RMS del 1er canal disparador)
    %   extend  : value = hi - (hi - lo) * s        (a = RMS del 1er canal disparador)
    %   rotate  : value = 90 + 90 * s               (solo F / F only)
    %   gesture : value = 100 * s                   (a = media de canales disparadores)
    %   hold    : value = valor previo / previous value (recortado al rango / clipped)
    %   rest    : value = 0
    %
    % DECISIÓN: mapeo lineal con zona muerta en 0.15 | RAZÓN: 0.15 es el umbral de reposo,
    %   por debajo no hay intención motora; lineal es predecible para el usuario y el LLM
    %   lo puede calcular | ALTERNATIVA DESCARTADA: curva sigmoidal (el LLM no la calcula
    %   con fiabilidad)
    % DECISION: linear mapping with a dead zone at 0.15 | REASON: 0.15 is the rest
    %   threshold, below it there is no motor intent; linear is predictable for the user
    %   and the LLM can compute it | DISCARDED ALTERNATIVE: sigmoid curve (the LLM cannot
    %   compute it reliably)
    %
    % Entradas / Inputs:
    %   rms_norm         : vector 1x8 de RMS normalizado [0,1] / normalized RMS vector
    %   command          : 'A'..'F' o '#X' / 'A'..'F' or '#X'
    %   action           : 'flex','extend','rotate','gesture','hold','rest'
    %   prev_value       : valor previo (para 'hold') / previous value (for 'hold')
    %   trigger_channels : canales disparadores (opcional) / trigger channels (optional)
    %
    % Salidas / Outputs:
    %   value : entero dentro del rango del comando / integer inside the command range
    %
    % Ejemplo / Example:
    %   v = rms_to_value([0 0 0 0.82 0 0 0.44 0], 'B', 'flex', [], [4 7]);   % v = 95

    REST_THRESHOLD = 0.15;

    if nargin < 4
        prev_value = [];
    end
    if nargin < 5
        trigger_channels = [];
    end

    info = label_to_finger(command);
    if isempty(info)
        error('rms_to_value:unknownCommand', ...
            'Comando desconocido / Unknown command: %s', char(command));
    end
    lo = info.range(1);
    hi = info.range(2);

    rms_norm = double(rms_norm(:)');
    rms_norm(~isfinite(rms_norm)) = 0;

    if isempty(trigger_channels)
        trigger_channels = info.primary_channels;
    end
    trigger_channels = trigger_channels(trigger_channels >= 1 & ...
        trigger_channels <= numel(rms_norm));

    switch lower(action)
        case 'rest'
            value = 0;
            return;
        case 'hold'
            if isempty(prev_value) || ~isfinite(prev_value)
                value = lo;
            else
                value = prev_value;
            end
        case 'gesture'
            if isempty(trigger_channels)
                a = 0;
            else
                a = mean(rms_norm(trigger_channels));
            end
            value = 100 * scale(a, REST_THRESHOLD);
        case 'flex'
            a = first_activation(rms_norm, trigger_channels);
            value = lo + (hi - lo) * scale(a, REST_THRESHOLD);
        case 'extend'
            a = first_activation(rms_norm, trigger_channels);
            value = hi - (hi - lo) * scale(a, REST_THRESHOLD);
        case 'rotate'
            a = first_activation(rms_norm, trigger_channels);
            value = 90 + 90 * scale(a, REST_THRESHOLD);
        otherwise
            error('rms_to_value:unknownAction', ...
                'Acción desconocida / Unknown action: %s', char(action));
    end

    value = round(min(max(value, lo), hi));
end

% -------------------------------------------------------------------------------------------
function s = scale(a, rest_threshold)
    % SCALE Normaliza la activación por encima del umbral de reposo a [0,1].
    % SCALE Normalizes the activation above the rest threshold to [0,1].
    s = (a - rest_threshold) / (1 - rest_threshold);
    s = min(max(s, 0), 1);
end

% -------------------------------------------------------------------------------------------
function a = first_activation(rms_norm, channels)
    % FIRST_ACTIVATION RMS del primer canal disparador (0 si no hay).
    % FIRST_ACTIVATION RMS of the first trigger channel (0 if none).
    if isempty(channels)
        a = 0;
    else
        a = rms_norm(channels(1));
    end
end
