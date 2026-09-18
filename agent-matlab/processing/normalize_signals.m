function values_norm = normalize_signals(values, calib, kind)
    % NORMALIZE_SIGNALS Normaliza RMS o MAV por canal usando la calibración del usuario.
    %
    % NORMALIZE_SIGNALS Normalizes per-channel RMS or MAV using the user's calibration.
    %
    %   values_norm = clamp((values - rest) ./ (mvc - rest), 0, 1)
    %
    % DECISIÓN: normalización reposo-MVC por canal | RAZÓN: elimina diferencias de piel,
    %   grasa y colocación entre usuarios y sesiones; deja todo en [0,1], que es la escala
    %   que usan los umbrales del prompt (0.15 / 0.40) | ALTERNATIVA DESCARTADA: z-score
    %   (no acotado, umbrales dependientes del usuario)
    % DECISION: per-channel rest-MVC normalization | REASON: removes skin, fat and
    %   placement differences between users and sessions; maps everything to [0,1], the
    %   scale used by the prompt thresholds (0.15 / 0.40) | DISCARDED ALTERNATIVE: z-score
    %   (unbounded, user-dependent thresholds)
    %
    % Entradas / Inputs:
    %   values : vector 1x8 de RMS o MAV crudos (filtrados) / raw (filtered) RMS or MAV
    %   calib  : struct de calibración con rest_rms, mvc_rms, rest_mav, mvc_mav
    %            calibration struct with rest_rms, mvc_rms, rest_mav, mvc_mav
    %   kind   : 'rms' (defecto / default) o / or 'mav'
    %
    % Salidas / Outputs:
    %   values_norm : vector 1x8 en [0,1]; si no hay calibración, se devuelven los valores
    %                 sin cambios / 1x8 vector in [0,1]; without calibration, values are
    %                 returned unchanged
    %
    % Ejemplo / Example:
    %   rms_norm = normalize_signals(rms_raw, calib, 'rms');

    if nargin < 3 || isempty(kind)
        kind = 'rms';
    end
    kind = lower(char(kind));

    values = double(values(:)');

    rest_field = ['rest_' kind];
    mvc_field = ['mvc_' kind];
    if isempty(calib) || ~isstruct(calib) || ~isfield(calib, rest_field) || ...
            ~isfield(calib, mvc_field)
        values_norm = values;
        return;
    end

    rest = double(calib.(rest_field)(:)');
    mvc = double(calib.(mvc_field)(:)');
    if numel(rest) ~= numel(values) || numel(mvc) ~= numel(values)
        error('normalize_signals:size', ...
            'Tamaño de calibración incompatible / Incompatible calibration size');
    end

    span = max(mvc - rest, 1e-6);
    values_norm = (values - rest) ./ span;
    values_norm(~isfinite(values_norm)) = 0;
    values_norm = min(max(values_norm, 0), 1);
end
