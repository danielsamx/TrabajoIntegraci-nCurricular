function [ok, reason] = validate_command(cmd)
% VALIDATE_COMMAND Comprueba que un comando es coherente antes de enviarlo a la prótesis.

ok = false;                                                 % se asume inválido
info = command_info(cmd.command);                           % datos del comando
c = cmd.trigger_channels;                                   % canales disparadores
v = cmd.value;                                              % valor pedido

if isempty(info)
    reason = ['comando desconocido: ' cmd.command];
elseif ~strcmp(cmd.finger, info.finger)
    reason = sprintf('finger %s no corresponde a %s (debe ser %s)', cmd.finger, info.command, info.finger);
elseif ~any(strcmp(cmd.action, info.actions))
    reason = sprintf('action %s no permitida para %s', cmd.action, info.command);
elseif ~isscalar(cmd.confidence) || ~(cmd.confidence >= 0 && cmd.confidence <= 1)
    reason = 'confidence fuera de [0,1]';
elseif any(c < 1 | c > 8 | c ~= round(c)) || numel(unique(c)) ~= numel(c)
    reason = 'trigger_channels deben ser enteros distintos entre 1 y 8';
elseif isempty(c) && ~any(strcmp(cmd.action, {'rest', 'hold'}))
    reason = 'trigger_channels vacío en un comando activo';
elseif ~isscalar(v) || v ~= round(v) || v < info.range(1) || v > info.range(2)
    reason = sprintf('value %g fuera de [%d,%d] para %s', v, info.range(1), info.range(2), info.command);
else
    ok = true;                                              % pasó todas las comprobaciones
    reason = '';
end
end
