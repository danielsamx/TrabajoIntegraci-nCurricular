% SETUP Configuración inicial del proyecto de control de prótesis por sEMG + LLM.
%
% SETUP Initial setup of the sEMG + LLM prosthesis control project.
%
% Pasos / Steps:
%   1. Verifica la versión de MATLAB (R2023b o superior)
%      Checks the MATLAB version (R2023b or newer)
%   2. Verifica los toolboxes (Signal Processing obligatorio, Statistics opcional)
%      Checks toolboxes (Signal Processing required, Statistics optional)
%   3. Crea los directorios necesarios / creates the required folders
%   4. Añade las carpetas del proyecto al path / adds project folders to the path
%   5. Crea los .mat de configuración que falten / creates missing .mat config files
%   6. Ejecuta pruebas sin red y pruebas de conexión básicas
%      Runs offline tests and basic connection tests
%
% DECISIÓN: script (no función) | RAZÓN: el usuario lo ejecuta una vez y ve las variables
%   resultantes en el workspace | ALTERNATIVA DESCARTADA: función (oculta el resultado)
% DECISION: script (not a function) | REASON: the user runs it once and sees the resulting
%   variables in the workspace | DISCARDED ALTERNATIVE: function (hides the result)
%
% DECISIÓN: no llamar a savepath | RAZÓN: modificar el path global de MATLAB sin permiso
%   afecta a otros proyectos | ALTERNATIVA DESCARTADA: savepath automático
% DECISION: do not call savepath | REASON: changing MATLAB's global path without
%   permission affects other projects | DISCARDED ALTERNATIVE: automatic savepath
%
% DECISIÓN: los tests de conexión no abortan el setup | RAZÓN: LM Studio o la prótesis
%   pueden no estar encendidos todavía; el resto de la configuración sigue siendo válida |
%   ALTERNATIVA DESCARTADA: error fatal si no hay conexión
% DECISION: connection tests do not abort the setup | REASON: LM Studio or the prosthesis
%   may not be running yet; the rest of the setup is still valid |
%   DISCARDED ALTERNATIVE: fatal error when there is no connection
%
% Uso / Usage:
%   >> setup

fprintf('\n==============================================================\n');
fprintf(' Proyecto prótesis sEMG + LLM / sEMG + LLM prosthesis project\n');
fprintf('==============================================================\n');

setup_root = fileparts(mfilename('fullpath'));

% 1) Versión de MATLAB / MATLAB version --------------------------------------------------
fprintf('\n[1/6] Versión de MATLAB / MATLAB version: %s\n', version);
if isMATLABReleaseOlderThan('R2023b')
    error('setup:version', 'Se requiere MATLAB R2023b o superior / R2023b or newer required');
end
fprintf('      OK\n');

% 2) Toolboxes ------------------------------------------------------------------------------
fprintf('\n[2/6] Toolboxes\n');
installed = ver;
installed_names = {installed.Name};
has_signal = any(strcmp(installed_names, 'Signal Processing Toolbox'));
has_stats = any(strcmp(installed_names, 'Statistics and Machine Learning Toolbox'));
fprintf('      Signal Processing Toolbox               : %s\n', setup_yes_no(has_signal));
fprintf('      Statistics and Machine Learning Toolbox : %s\n', setup_yes_no(has_stats));
if ~has_signal
    error('setup:toolbox', ['Signal Processing Toolbox es obligatorio (butter, zp2sos, ', ...
        'filtfilt) / is required']);
end
if ~has_stats
    warning('setup:stats', ['Statistics Toolbox no encontrado: el LDA funciona igual, ', ...
        'pero sin verificación con fitcdiscr / LDA still works without fitcdiscr check']);
end

% 3) Directorios / folders -----------------------------------------------------------------
fprintf('\n[3/6] Directorios / folders\n');
setup_folders = {'config', 'prompts', 'acquisition', 'processing', 'llm', 'prosthesis', ...
    'utils', 'tests', 'docs', 'logs'};
for setup_k = 1:numel(setup_folders)
    setup_folder = fullfile(setup_root, setup_folders{setup_k});
    if ~isfolder(setup_folder)
        mkdir(setup_folder);
        fprintf('      creado / created: %s\n', setup_folders{setup_k});
    end
end
fprintf('      OK\n');

% 4) Path -----------------------------------------------------------------------------------
fprintf('\n[4/6] Path de MATLAB / MATLAB path\n');
addpath(setup_root);
for setup_k = 1:numel(setup_folders)
    if ~any(strcmp(setup_folders{setup_k}, {'prompts', 'docs', 'logs'}))
        addpath(fullfile(setup_root, setup_folders{setup_k}));
    end
end
fprintf('      OK (use savepath si quiere hacerlo permanente / to make it permanent)\n');

% 5) Configuración / configuration ---------------------------------------------------------
fprintf('\n[5/6] Archivos de configuración / configuration files\n');
setup_config = fullfile(setup_root, 'config');
if ~isfile(fullfile(setup_config, 'server-llm.mat'))
    create_server_llm_config();
else
    fprintf('      server-llm.mat ya existe / already exists\n');
end
if ~isfile(fullfile(setup_config, 'server-prosthesis.mat'))
    create_server_prosthesis_config();
else
    fprintf('      server-prosthesis.mat ya existe / already exists\n');
end
if ~isfile(fullfile(setup_config, 'prompt-llm.mat'))
    create_prompt_llm_config();
else
    fprintf('      prompt-llm.mat ya existe / already exists\n');
end
if ~isfile(fullfile(setup_config, 'calibration.mat'))
    create_calibration_config();
else
    fprintf('      calibration.mat ya existe / already exists\n');
end

% 6) Pruebas / tests ------------------------------------------------------------------------
fprintf('\n[6/6] Pruebas / tests\n');
setup_results = struct();
setup_results.payload = setup_run_test(@test_payload);
setup_results.parallel_ports = setup_run_test(@test_parallel_ports);
setup_results.llm_connection = setup_run_test(@test_llm_connection);
setup_results.prosthesis_connection = setup_run_test(@test_prosthesis_connection);

fprintf('\n==============================================================\n');
fprintf(' Resumen / Summary\n');
setup_names = fieldnames(setup_results);
for setup_k = 1:numel(setup_names)
    fprintf('   %-24s : %s\n', setup_names{setup_k}, ...
        setup_pass_fail(setup_results.(setup_names{setup_k})));
end
fprintf('\nSiguientes pasos / Next steps:\n');
fprintf('   1. create_server_llm_config(''ip'', ''<IP LM Studio>'')\n');
fprintf('   2. create_server_prosthesis_config(''ip'', ''<IP prótesis>'')\n');
fprintf('   3. calibrate(''Source'', ''myo'', ''UserId'', ''<nombre>'')\n');
fprintf('   4. main   (o / or  main_debug)\n');
fprintf('==============================================================\n');

% -------------------------------------------------------------------------------------------
function passed = setup_run_test(test_handle)
    % SETUP_RUN_TEST Ejecuta un test sin abortar el setup. / Runs a test without aborting.
    try
        passed = logical(test_handle());
    catch err
        fprintf(2, '      %s falló con error / failed with error: %s\n', ...
            func2str(test_handle), err.message);
        passed = false;
    end
end

% -------------------------------------------------------------------------------------------
function text = setup_yes_no(flag)
    % SETUP_YES_NO 'sí / yes' o 'NO'.
    if flag
        text = 'sí / yes';
    else
        text = 'NO';
    end
end

% -------------------------------------------------------------------------------------------
function text = setup_pass_fail(flag)
    % SETUP_PASS_FAIL 'OK' o 'FALLO / FAIL'.
    if flag
        text = 'OK';
    else
        text = 'FALLO / FAIL';
    end
end
