function [is_valid, reason] = is_valid_response(cmd)
    % IS_VALID_RESPONSE Valida la estructura y la coherencia del comando del LLM.
    %
    % IS_VALID_RESPONSE Validates the structure and consistency of the LLM command.
    %
    % Reglas / Rules:
    %   1. Campos obligatorios / required fields:
    %      command, finger, action, confidence, trigger_channels, value
    %   2. command pertenece a la lista cerrada (A-F, #O #C #P #R #W #Y #L #M #H #U #G)
    %      command belongs to the closed list
    %   3. finger coincide con el command (A->D1 ... F->WRIST, gestos->MULTI, #R->NONE)
    %      finger matches the command
    %   4. action permitida para ese command / action allowed for that command
    %   5. confidence numérico en [0,1] / numeric confidence in [0,1]
    %   6. trigger_channels enteros únicos en 1..8 (vacío solo en rest/hold)
    %      trigger_channels unique integers in 1..8 (empty only for rest/hold)
    %   7. value entero dentro del rango del command / integer value within command range
    %
    % DECISIÓN: validación estricta; cualquier fallo activa el fallback LDA | RAZÓN: un
    %   comando incoherente enviado a un actuador físico es un riesgo de seguridad |
    %   ALTERNATIVA DESCARTADA: corregir silenciosamente los campos erróneos (oculta fallos
    %   del modelo y del prompt)
    % DECISION: strict validation; any failure triggers the LDA fallback | REASON: an
    %   inconsistent command sent to a physical actuator is a safety risk |
    %   DISCARDED ALTERNATIVE: silently fixing wrong fields (hides model/prompt failures)
    %
    % Entradas / Inputs:
    %   cmd : struct devuelto por parse_llm_response / struct from parse_llm_response
    %
    % Salidas / Outputs:
    %   is_valid : true si pasa todas las reglas / true if all rules pass
    %   reason   : motivo del primer fallo ('' si es válido) / first failure reason
    %
    % Ejemplo / Example:
    %   [ok, why] = is_valid_response(cmd);

    is_valid = false;
    reason = '';

    if isempty(cmd) || ~isstruct(cmd) || ~isscalar(cmd)
        reason = 'not a struct';
        return;
    end

    required = {'command', 'finger', 'action', 'confidence', 'trigger_channels', 'value'};
    missing = required(~isfield(cmd, required));
    if ~isempty(missing)
        reason = ['missing fields: ', strjoin(missing, ',')];
        return;
    end

    if ~(ischar(cmd.command) || isstring(cmd.command))
        reason = 'command is not text';
        return;
    end
    valid_commands = {'A', 'B', 'C', 'D', 'E', 'F', '#O', '#C', '#P', '#R', '#W', ...
        '#Y', '#L', '#M', '#H', '#U', '#G'};
    command = char(cmd.command);
    if ~any(strcmp(command, valid_commands))
        reason = ['unknown command: ', command];
        return;
    end
    info = label_to_finger(command);

    if ~(ischar(cmd.finger) || isstring(cmd.finger)) || ~strcmp(char(cmd.finger), info.finger)
        reason = sprintf('finger mismatch: expected %s', info.finger);
        return;
    end

    if ~(ischar(cmd.action) || isstring(cmd.action)) || ...
            ~any(strcmp(char(cmd.action), info.allowed_actions))
        reason = sprintf('action not allowed for %s', command);
        return;
    end

    c = cmd.confidence;
    if ~isnumeric(c) || ~isscalar(c) || ~isfinite(c) || c < 0 || c > 1
        reason = 'confidence out of [0,1]';
        return;
    end

    channels = cmd.trigger_channels;
    if ~isnumeric(channels)
        reason = 'trigger_channels is not numeric';
        return;
    end
    channels = channels(:)';
    if any(~isfinite(channels)) || any(channels ~= round(channels)) || ...
            any(channels < 1) || any(channels > 8) || ...
            numel(unique(channels)) ~= numel(channels)
        reason = 'trigger_channels must be unique integers in 1..8';
        return;
    end
    if isempty(channels) && ~any(strcmp(char(cmd.action), {'rest', 'hold'}))
        reason = 'trigger_channels empty for an active command';
        return;
    end

    v = cmd.value;
    if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v) || abs(v - round(v)) > 1e-9
        reason = 'value must be an integer';
        return;
    end
    if v < info.range(1) || v > info.range(2)
        reason = sprintf('value %g outside [%d,%d] for %s', v, info.range(1), ...
            info.range(2), command);
        return;
    end

    is_valid = true;
end
