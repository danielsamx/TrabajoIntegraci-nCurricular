function cmd = fallback_command(f, prev, cfg)
% FALLBACK_COMMAND Decide el comando sin el LLM, con las mismas reglas del system prompt.
%   Solo se usa cuando el LLM no responde o su respuesta no es válida.

r = f.rms;                                                  % RMS normalizado de los 8 canales
high = r >= 0.40;                                           % canales con activación alta
low = r < 0.25;                                             % canales con activación baja
moderate = ~high & ~low;                                    % canales con activación moderada

if strcmp(f.state, 'NOISE')                                 % R1: ruido -> mantener el anterior
    cmd = hold_previous(prev, 0.50);
    return;
end
if strcmp(f.state, 'REST') || max(r) < cfg.signal.rest_threshold % R2: reposo
    cmd = make_command('#R', 'rest', 0.90, [], 0);
    return;
end

is_gesture = sum(high(1:5)) >= 2 || all(r(6:8) >= 0.50) || sum(moderate(1:5)) >= 4; % R3: varios dedos
if is_gesture
    gesture = match_gesture(r, high, low, moderate);       % qué gesto encaja
    if isempty(gesture)                                     % ningún gesto encaja
        cmd = hold_previous(prev, 0.45);
        return;
    end
    info = command_info(gesture);                           % datos del gesto
    channels = sort_by_rms(r, info.channels);               % sus canales, de mayor a menor RMS
    value = 100 * scale(mean(r(channels)));                 % fuerza = activación media
    cmd = make_command(gesture, 'gesture', 0.90, channels, value);
    return;
end

flexor = find(high(1:5));                                   % R4: un único flexor alto
if numel(flexor) == 1
    code = {'E', 'D', 'C', 'B', 'A'};                       % CH1->meñique ... CH5->pulgar
    info = command_info(code{flexor});                      % datos del dedo
    channels = sort_by_rms(r, info.channels);               % flexor y su extensor par
    value = info.range(2) * scale(r(channels(1)));          % ángulo proporcional a la activación
    cmd = make_command(info.command, 'flex', 0.70, channels, value);
    return;
end

cmd = hold_previous(prev, 0.60);                            % R7: transición -> mantener el anterior
end

function gesture = match_gesture(r, high, low, moderate)
% Primera regla de gesto que se cumple (orden del system prompt); '' si ninguna.
if all(r(6:8) >= 0.50) && all(low(1:4)),                   gesture = '#O';
elseif high(4) && high(5) && all(low(1:3)),                gesture = '#P';
elseif all(high(1:3)) && low(4) && high(5),                gesture = '#G';
elseif all(high(1:3)) && low(4) && low(5) && high(6),      gesture = '#L';
elseif high(1) && high(2) && low(3) && low(4) && high(5),  gesture = '#U';
elseif high(1) && all(low(2:4)) && high(5) && high(7),     gesture = '#W';
elseif all(high(2:4)) && low(1) && low(5) && high(6),      gesture = '#Y';
elseif sum(high(1:4)) >= 3 && low(5) && high(6),           gesture = '#H';
elseif sum(high(1:4)) >= 3 && high(5),                     gesture = '#C';
elseif all(moderate(1:4)) && r(5) >= 0.25,                 gesture = '#M';
else,                                                      gesture = '';
end
end

function s = scale(a)
% Activación por encima del umbral de reposo, llevada a [0, 1].
s = min(max((a - 0.15) / 0.85, 0), 1);
end

function channels = sort_by_rms(r, channels)
% Ordena los canales de mayor a menor RMS.
[~, order] = sort(r(channels), 'descend');                  % posiciones de mayor a menor
channels = channels(order);                                 % canales reordenados
end

function cmd = hold_previous(prev, confidence)
% Repite el comando anterior; si era reposo, sigue en reposo.
if strcmp(prev.command, '#R')
    cmd = make_command('#R', 'rest', confidence, [], 0);
else
    cmd = make_command(prev.command, 'hold', confidence, [], prev.value);
end
end

function cmd = make_command(code, action, confidence, channels, value)
% Crea el struct de comando con el mismo formato que el del LLM.
info = command_info(code);                                  % datos del comando
cmd.command = code;                                         % código
cmd.finger = info.finger;                                   % dedo
cmd.action = action;                                        % acción
cmd.confidence = confidence;                                % confianza
cmd.trigger_channels = channels;                            % canales disparadores
cmd.value = round(value);                                   % valor entero
cmd.source = 'respaldo';                                    % decidido sin el LLM
end
