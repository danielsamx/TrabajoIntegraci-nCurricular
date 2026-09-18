# prosthesis/

> English: [README.md](README.md)

| Archivo | Función |
|---|---|
| `send_signals_prosthesis.m` | `[ok, reply, ms] = send_signals_prosthesis(cfg, command, cycle)`. Envía `POST /api/command` (`HTTP`) o llama al simulador (`SIM`). Cuenta los fallos consecutivos |
| `prosthesis_simulator.m` | Simulador de 6 GDL (dedos A–E + muñeca F): `reset`, `command`, `state`, `plot`, `start_server`, `stop_server` |

## JSON enviado

```json
{"command":"#C","finger":"MULTI","action":"gesture","value":77,"confidence":0.93,
 "trigger_channels":[4,2,1,3,5],"source":"llm","cycle":128,"timestamp":"2026-09-16T11:20:00.123"}
```

`source` vale `llm`, `lda` o `safety`. `cycle = -1` marca el comando seguro que se envía al
cerrar. El protocolo completo está en [../docs/protocol.es.md](../docs/protocol.es.md).

## Simulador

**En proceso** (`protocol = 'SIM'`): sin red. Los comandos actualizan los ángulos internos.

```matlab
create_server_prosthesis_config('protocol', 'SIM');
prosthesis_simulator('plot');    % opcional: barras en vivo
main('Source', 'simulated');
```

**Servidor HTTP**: ejecútelo en una **segunda sesión de MATLAB**. MATLAB ejecuta los
callbacks en el mismo hilo, así que un servidor en la misma sesión que `main` no podría
responder mientras `main` espera dentro de `webwrite`.

```matlab
% Sesión 2 de MATLAB
prosthesis_simulator('start_server', 8080);
prosthesis_simulator('plot');
% Sesión 1 de MATLAB
create_server_prosthesis_config('ip', '127.0.0.1', 'port', 8080);
test_prosthesis_connection('Sweep', true)
```

Los ángulos de los gestos escalan como `preset × (0.4 + 0.6 · value/100)`, así que un gesto
sigue siendo reconocible incluso con poca fuerza. `#R` vuelve a la postura neutra
`[20 20 20 20 20 90]`.
