function calib = create_calibration_config(varargin)
    % CREATE_CALIBRATION_CONFIG Genera una calibración por defecto (sintética) en
    %   config/calibration.mat para poder arrancar antes de calibrar al usuario.
    %
    % CREATE_CALIBRATION_CONFIG Generates a default (synthetic) calibration in
    %   config/calibration.mat so the system can start before the user is calibrated.
    %
    % La calibración queda marcada con is_default = true; el payload lo indica al LLM
    % (CALIB:[...,DEFAULT]) y main.m muestra un aviso. Sustitúyala con calibrate().
    % The calibration is flagged is_default = true; the payload tells the LLM
    % (CALIB:[...,DEFAULT]) and main.m prints a warning. Replace it with calibrate().
    %
    % DECISIÓN: reutilizar calibrate() con la fuente simulada | RAZÓN: una sola
    %   implementación del cálculo de referencias, perfiles y LDA | ALTERNATIVA
    %   DESCARTADA: valores fijos escritos a mano (divergirían del procesamiento real)
    % DECISION: reuse calibrate() with the simulated source | REASON: a single
    %   implementation of references, profiles and LDA | DISCARDED ALTERNATIVE:
    %   hand-written fixed values (would diverge from the real processing)
    %
    % DECISIÓN: no sobrescribir una calibración real salvo con 'Overwrite', true |
    %   RAZÓN: proteger la calibración del usuario | ALTERNATIVA DESCARTADA: sobrescribir
    %   siempre
    % DECISION: never overwrite a real calibration unless 'Overwrite', true |
    %   REASON: protects the user's calibration | DISCARDED ALTERNATIVE: always overwrite
    %
    % Entradas (nombre-valor) / Inputs (name-value):
    %   'Overwrite'   : sobrescribir aunque exista / overwrite even if it exists (false)
    %   'PowerlineHz' : 60 (Ecuador/América) o 50 (Europa) / 60 or 50
    %   'SavePath'    : ruta de salida / output path
    %
    % Ejemplo / Example:
    %   calib = create_calibration_config('Overwrite', true);

    root = fileparts(fileparts(mfilename('fullpath')));

    p = inputParser;
    addParameter(p, 'Overwrite', false);
    addParameter(p, 'PowerlineHz', 60);
    addParameter(p, 'SavePath', fullfile(root, 'config', 'calibration.mat'));
    parse(p, varargin{:});
    opts = p.Results;

    if isfile(opts.SavePath) && ~opts.Overwrite
        loaded = load(opts.SavePath, 'calib');
        if isfield(loaded, 'calib') && ~loaded.calib.is_default
            logger('WARN', 'create_calibration_config', ['Ya existe una calibración ', ...
                'real; no se sobrescribe / A real calibration exists; not overwritten']);
            calib = loaded.calib;
            return;
        end
    end

    calib = calibrate('Source', 'simulated', 'UserId', 'default', 'IsDefault', true, ...
        'Interactive', false, 'Reps', 8, 'Seed', 42, 'PowerlineHz', opts.PowerlineHz, ...
        'SavePath', opts.SavePath);
end
