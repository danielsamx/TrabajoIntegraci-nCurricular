function out = smooth_command(cmd, opts)
    % SMOOTH_COMMAND Suavizado temporal del comando: voto mayoritario + EMA del valor.
    %
    % SMOOTH_COMMAND Temporal smoothing of the command: majority vote + value EMA.
    %
    % Algoritmo / Algorithm:
    %   1. Se guarda el historial de los últimos K comandos (K = opts.window).
    %      The last K commands are kept (K = opts.window).
    %   2. Mismo comando que el actual -> EMA del valor (alpha = opts.alpha).
    %      Same command as the current one -> value EMA (alpha = opts.alpha).
    %   3. Comando distinto -> se cambia solo si tiene mayoría en el historial, o si su
    %      confianza >= opts.fast_confidence (vía rápida), o si es '#R' con confianza
    %      >= opts.rest_confidence (seguridad). Si no, se mantiene el actual.
    %      Different command -> switch only with a majority in the history, or with
    %      confidence >= opts.fast_confidence (fast path), or if it is '#R' with
    %      confidence >= opts.rest_confidence (safety). Otherwise, keep the current one.
    %
    % DECISIÓN: voto mayoritario (K=3) + vía rápida por confianza | RAZÓN: elimina
    %   parpadeos de una sola ventana sin añadir latencia cuando el LLM está seguro |
    %   ALTERNATIVA DESCARTADA: filtro de mediana de K=5 (añade ~2 ciclos de retardo)
    % DECISION: majority vote (K=3) + confidence fast path | REASON: removes single-window
    %   flicker without adding latency when the LLM is confident |
    %   DISCARDED ALTERNATIVE: K=5 median filter (adds ~2 cycles of delay)
    %
    % DECISIÓN: '#R' (reposo) con umbral de cambio más bajo | RAZÓN: relajar la mano es la
    %   acción segura y debe ocurrir rápido | ALTERNATIVA DESCARTADA: mismo umbral para todo
    % DECISION: '#R' (rest) uses a lower switching threshold | REASON: relaxing the hand is
    %   the safe action and must happen fast | DISCARDED ALTERNATIVE: same threshold for all
    %
    % Entradas / Inputs:
    %   cmd  : struct con command, finger, action, confidence, trigger_channels, value,
    %          source; o 'reset' para reiniciar el estado / or 'reset' to clear the state
    %   opts : (opcional / optional) struct con window, alpha, fast_confidence,
    %          rest_confidence
    %
    % Salidas / Outputs:
    %   out : comando suavizado (mismos campos + 'smoothing' = 'pass'|'ema'|'held')
    %         smoothed command (same fields + 'smoothing' = 'pass'|'ema'|'held')
    %
    % Ejemplo / Example:
    %   smooth_command('reset');
    %   out = smooth_command(struct('command','B','finger','D2','action','flex', ...
    %       'confidence',0.9,'trigger_channels',[4 7],'value',95,'source','llm'));

    persistent history current ema_value

    if ischar(cmd) || isstring(cmd)
        if strcmpi(cmd, 'reset')
            history = {};
            current = [];
            ema_value = [];
            out = [];
            return;
        end
        error('smooth_command:badInput', ...
            'Entrada no válida / Invalid input: %s', char(cmd));
    end

    if nargin < 2 || isempty(opts)
        opts = struct();
    end
    window = get_opt(opts, 'window', 3);
    alpha = get_opt(opts, 'alpha', 0.5);
    fast_confidence = get_opt(opts, 'fast_confidence', 0.85);
    rest_confidence = get_opt(opts, 'rest_confidence', 0.60);

    if isempty(history)
        history = {};
    end

    history{end + 1} = cmd.command;
    if numel(history) > window
        history = history(end - window + 1:end);
    end

    if isempty(current)
        current = cmd;
        ema_value = double(cmd.value);
        out = current;
        out.smoothing = 'pass';
        return;
    end

    if strcmp(cmd.command, current.command)
        if ~strcmpi(cmd.action, 'hold')
            ema_value = alpha * double(cmd.value) + (1 - alpha) * ema_value;
        end
        current = cmd;
        current.value = round(ema_value);
        out = current;
        out.smoothing = 'ema';
        return;
    end

    votes = sum(strcmp(history, cmd.command));
    has_majority = votes >= ceil(window / 2);
    is_fast = cmd.confidence >= fast_confidence;
    is_safe_rest = strcmp(cmd.command, '#R') && cmd.confidence >= rest_confidence;

    if has_majority || is_fast || is_safe_rest
        current = cmd;
        ema_value = double(cmd.value);
        out = current;
        out.smoothing = 'pass';
    else
        % Se mantiene el comando anterior / the previous command is kept
        out = current;
        out.action = 'hold';
        out.source = cmd.source;
        out.smoothing = 'held';
    end
end

% -------------------------------------------------------------------------------------------
function value = get_opt(opts, name, default_value)
    % GET_OPT Lee un campo opcional con valor por defecto.
    % GET_OPT Reads an optional field with a default value.
    if isfield(opts, name) && ~isempty(opts.(name))
        value = opts.(name);
    else
        value = default_value;
    end
end
