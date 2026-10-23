function summary = main()
% MAIN Agente de control de la prótesis sin interfaz: todo se imprime en la consola.
%   Lee el Myo (config/agent_config.m), consulta al LLM y envía el comando a la prótesis.
%   Para la interfaz gráfica use agent_ui. Ctrl+C detiene el agente.

add_project_paths();                                        % carpetas del proyecto al path
cfg = agent_config();                                       % carga toda la configuración
session = agent_session(cfg);                               % registro, prompt y conexión con el Myo
cleanup = onCleanup(@() session.finish());                  % al salir (incluso Ctrl+C): reposo y cierre

while session.stats.cycles < cfg.max_cycles                 % hasta el límite de ciclos
    r = session.step();                                     % un ciclo completo
    if r.done
        break;
    end
    pause(max(0, cfg.period_s - r.cycle_ms / 1000));        % espera hasta completar el periodo
end
summary = session.finish();                                 % resumen y estado seguro
end
