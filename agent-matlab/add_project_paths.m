function add_project_paths()
% ADD_PROJECT_PATHS Añade las carpetas de código del proyecto al path de MATLAB.

root = fileparts(mfilename('fullpath'));                    % carpeta raíz del proyecto
folders = {'config', 'acquisition', 'processing', 'llm', 'prosthesis', 'agent', 'utils'};
for k = 1:numel(folders)
    addpath(fullfile(root, folders{k}));                    % añade cada carpeta
end
end
