function encoded = base64encode(data)
    % BASE64ENCODE Codifica bytes (o texto) en Base64 (RFC 4648).
    %
    % BASE64ENCODE Encodes bytes (or text) as Base64 (RFC 4648).
    %
    % DECISIÓN: usar matlab.net.base64encode con respaldo en MATLAB puro | RAZÓN: la
    %   función nativa es rápida y forma parte de MATLAB base; el respaldo garantiza que
    %   funcione aunque cambie la API | ALTERNATIVA DESCARTADA: org.apache.commons (Java,
    %   dependencia oculta y desaconsejada)
    % DECISION: use matlab.net.base64encode with a pure-MATLAB fallback | REASON: the
    %   native function is fast and part of base MATLAB; the fallback guarantees it keeps
    %   working if the API changes | DISCARDED ALTERNATIVE: org.apache.commons (Java,
    %   hidden and discouraged dependency)
    %
    % Entradas / Inputs:
    %   data : vector uint8 o texto (char/string, se codifica en UTF-8)
    %          uint8 vector or text (char/string, encoded as UTF-8)
    %
    % Salidas / Outputs:
    %   encoded : char con el texto Base64 / char with the Base64 text
    %
    % Ejemplo / Example:
    %   s = base64encode('Hola');          % 'SG9sYQ=='
    %   s = base64encode(uint8([1 2 3]));  % 'AQID'

    if ischar(data) || isstring(data)
        data = unicode2native(char(data), 'UTF-8');
    end
    data = uint8(data(:)');

    try
        encoded = char(matlab.net.base64encode(data));
    catch
        encoded = local_base64(data);
    end
end

% -------------------------------------------------------------------------------------------
function out = local_base64(bytes)
    % LOCAL_BASE64 Implementación vectorizada en MATLAB puro.
    % LOCAL_BASE64 Vectorized pure-MATLAB implementation.
    alphabet = ['A':'Z', 'a':'z', '0':'9', '+', '/'];
    n = numel(bytes);
    if n == 0
        out = '';
        return;
    end
    pad = mod(3 - mod(n, 3), 3);
    b = [double(bytes), zeros(1, pad)];
    b = reshape(b, 3, []);
    v = b(1, :) * 65536 + b(2, :) * 256 + b(3, :);
    idx = [floor(v / 262144); mod(floor(v / 4096), 64); mod(floor(v / 64), 64); mod(v, 64)];
    out = alphabet(idx(:)' + 1);
    if pad > 0
        out(end - pad + 1:end) = '=';
    end
end
