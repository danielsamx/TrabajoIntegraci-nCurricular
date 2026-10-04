function summary = main(source)
% MAIN Agente de control de la prótesis sin interfaz: todo se imprime en la consola.
%   main            usa la fuente de agent_config.m (Myo; si no está activo, las muestras)
%   main('samples') reproduce directamente samples/muestra_1..15.csv
%   Para la interfaz gráfica use agent_ui. Ctrl+C detiene el agente.

add_project_paths();                                        % carpetas del proyecto al path
cfg = agent_config();                                       % carga toda la configuración
if nargin >= 1
    cfg.source = source;                                    % la fuente pedida al llamar
end

session = agent_session(cfg);                               % registro, prompt y fuente de señal
cleanup = onCleanup(@() session.finish());                  % al salir (incluso Ctrl+C): reposo y cierre

while session.stats.cycles < cfg.max_cycles                 % hasta el límite de ciclos
    r = session.step();                                     % un ciclo completo
    if r.done                                               % no quedan datos
        break;
    end
    pause(max(0, cfg.period_s - r.cycle_ms / 1000));        % espera hasta completar el periodo
end
summary = session.finish();                                 % resumen y estado seguro
end
