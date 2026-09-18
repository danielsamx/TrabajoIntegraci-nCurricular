function [is_composite, gesture, trigger_channels, confidence] = is_composite_gesture(rms_norm)
    % IS_COMPOSITE_GESTURE Detecta si el patrón RMS corresponde a un gesto compuesto
    %   (varios dedos a la vez) y, si es posible, cuál.
    %
    % IS_COMPOSITE_GESTURE Detects whether the RMS pattern is a composite gesture
    %   (several fingers at once) and, when possible, which one.
    %
    % Esta función es el espejo determinista de las "reglas de gestos compuestos" del
    % system prompt. La usan el fallback LDA y el transporte 'mock'.
    % This function is the deterministic mirror of the "composite gesture rules" in the
    % system prompt. It is used by the LDA fallback and by the 'mock' transport.
    %
    % Niveles / Levels:  alto/high >= 0.40 | bajo/low < 0.25 | moderado/moderate [0.25,0.40)
    %
    % Disparo / Trigger (cualquiera / any):
    %   - >= 2 canales de CH1-CH5 altos / >= 2 of CH1-CH5 high
    %   - CH6, CH7 y CH8 >= 0.50 / CH6, CH7 and CH8 >= 0.50
    %   - >= 4 canales de CH1-CH5 moderados / >= 4 of CH1-CH5 moderate
    %
    % Reglas en orden de prioridad / Rules by priority:
    %   #O : CH6..CH8 >= 0.50 y CH1..CH4 bajos
    %   #P : CH4 y CH5 altos, CH1..CH3 bajos
    %   #G : CH1..CH3 altos, CH4 bajo, CH5 alto
    %   #L : CH1..CH3 altos, CH4 bajo, CH5 bajo, CH6 alto
    %   #U : CH1, CH2 altos, CH3, CH4 bajos, CH5 alto
    %   #W : CH1 alto, CH2..CH4 bajos, CH5 alto, CH7 alto
    %   #Y : CH2..CH4 altos, CH1 bajo, CH5 bajo, CH6 alto
    %   #H : >= 3 de CH1..CH4 altos, CH5 bajo, CH6 alto
    %   #C : >= 3 de CH1..CH4 altos, CH5 alto
    %   #M : CH1..CH4 moderados, CH5 >= 0.25
    %
    % DECISIÓN: reglas específicas antes que genéricas (#G antes que #C) | RAZÓN: #C
    %   (>=3 de 4 flexores) también se cumple en #G; evaluar primero el caso particular
    %   evita que el genérico lo absorba | ALTERNATIVA DESCARTADA: distancia a prototipos
    %   (no reproducible por el LLM a partir del prompt)
    % DECISION: specific rules before generic ones (#G before #C) | REASON: #C
    %   (>=3 of 4 flexors) also holds for #G; evaluating the particular case first keeps
    %   the generic one from absorbing it | DISCARDED ALTERNATIVE: prototype distance
    %   (not reproducible by the LLM from the prompt)
    %
    % Entradas / Inputs:
    %   rms_norm : vector 1x8 de RMS normalizado / normalized RMS vector
    %
    % Salidas / Outputs:
    %   is_composite     : true si se dispara la detección / true if detection triggers
    %   gesture          : '#X' o '' si no coincide ninguna regla / '' if no rule matches
    %   trigger_channels : canales del gesto ordenados por activación / sorted channels
    %   confidence       : 0.90 regla clara, 0.50 sin regla / clear rule, no rule
    %
    % Ejemplo / Example:
    %   [tf, g] = is_composite_gesture([0.81 0.84 0.79 0.86 0.72 0.2 0.25 0.22]); % '#C'

    HIGH = 0.40;
    LOW = 0.25;
    OPEN_LEVEL = 0.50;

    r = double(rms_norm(:)');
    r(~isfinite(r)) = 0;
    if numel(r) ~= 8
        error('is_composite_gesture:size', ...
            'Se esperaban 8 canales / 8 channels expected (got %d)', numel(r));
    end

    hi = r >= HIGH;
    lo = r < LOW;
    moderate = r >= LOW & r < HIGH;

    is_composite = sum(hi(1:5)) >= 2 || all(r(6:8) >= OPEN_LEVEL) || ...
        sum(moderate(1:5)) >= 4;

    gesture = '';
    trigger_channels = [];
    confidence = 0;

    if ~is_composite
        return;
    end

    if all(r(6:8) >= OPEN_LEVEL) && all(lo(1:4))
        gesture = '#O';
    elseif hi(4) && hi(5) && all(lo(1:3))
        gesture = '#P';
    elseif all(hi(1:3)) && lo(4) && hi(5)
        gesture = '#G';
    elseif all(hi(1:3)) && lo(4) && lo(5) && hi(6)
        gesture = '#L';
    elseif hi(1) && hi(2) && lo(3) && lo(4) && hi(5)
        gesture = '#U';
    elseif hi(1) && all(lo(2:4)) && hi(5) && hi(7)
        gesture = '#W';
    elseif all(hi(2:4)) && lo(1) && lo(5) && hi(6)
        gesture = '#Y';
    elseif sum(hi(1:4)) >= 3 && lo(5) && hi(6)
        gesture = '#H';
    elseif sum(hi(1:4)) >= 3 && hi(5)
        gesture = '#C';
    elseif all(moderate(1:4)) && r(5) >= LOW
        gesture = '#M';
    end

    if isempty(gesture)
        confidence = 0.50;
        return;
    end

    info = label_to_finger(gesture);
    channels = info.primary_channels;
    [~, order] = sort(r(channels), 'descend');
    trigger_channels = channels(order);
    confidence = 0.90;
end
