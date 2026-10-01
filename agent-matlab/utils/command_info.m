function info = command_info(code)
% COMMAND_INFO Datos de un comando de la prótesis ('A'..'F' o '#X'); [] si no existe.
%   info.finger   : dedo que mueve (D1..D5, WRIST, MULTI, NONE)
%   info.name     : nombre legible
%   info.range    : [mínimo máximo] de value (grados en dedos, % de fuerza en gestos)
%   info.actions  : acciones permitidas
%   info.channels : canales principales (mapa anatómico del system prompt)

f = {'flex', 'extend', 'hold'};                             % acciones de un dedo
g = {'gesture', 'hold'};                                    % acciones de un gesto

table = {                                                   % comando, dedo, nombre, rango, acciones, canales
    'A',  'D1',    'pulgar',             [0 90],  f,                   [5 6]
    'B',  'D2',    'índice',             [0 120], f,                   [4 7]
    'C',  'D3',    'medio',              [0 120], f,                   [3 7]
    'D',  'D4',    'anular',             [0 120], f,                   [2 8]
    'E',  'D5',    'meñique',            [0 120], f,                   [1 8]
    'F',  'WRIST', 'rotación de muñeca', [0 180], {'rotate', 'hold'},  [5 6 7]
    '#O', 'MULTI', 'mano abierta',       [0 100], g,                   [6 7 8]
    '#C', 'MULTI', 'puño',               [0 100], g,                   [1 2 3 4 5]
    '#P', 'MULTI', 'pinza fina',         [0 100], g,                   [4 5]
    '#R', 'NONE',  'reposo',             [0 0],   {'rest', 'hold'},    []
    '#W', 'MULTI', 'tres dedos',         [0 100], g,                   [1 5 7]
    '#Y', 'MULTI', 'shaka',              [0 100], g,                   [2 3 4 6]
    '#L', 'MULTI', 'forma de L',         [0 100], g,                   [1 2 3 6]
    '#M', 'MULTI', 'agarre de ratón',    [0 100], g,                   [1 2 3 4 5]
    '#H', 'MULTI', 'gancho',             [0 100], g,                   [1 2 3 4 6]
    '#U', 'MULTI', 'índice y medio',     [0 100], g,                   [1 2 5]
    '#G', 'MULTI', 'señalar',            [0 100], g,                   [1 2 3 5]
    };

row = find(strcmp(table(:, 1), upper(strtrim(char(code)))), 1); % fila del comando pedido
if isempty(row)                                             % comando desconocido
    info = [];                                              % se devuelve vacío
    return;
end

info.command = table{row, 1};                               % código del comando
info.finger = table{row, 2};                                % dedo asociado
info.name = table{row, 3};                                  % nombre legible
info.range = table{row, 4};                                 % rango de value
info.actions = table{row, 5};                               % acciones permitidas
info.channels = table{row, 6};                              % canales principales
end
