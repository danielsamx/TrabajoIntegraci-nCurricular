# prosthesis/

> Español: [README.es.md](README.es.md)

| File | Role |
|---|---|
| `send_signals_prosthesis.m` | `[ok, reply, ms] = send_signals_prosthesis(cfg, command, cycle)`. Sends `POST /api/command` (`HTTP`) or calls the simulator (`SIM`). Counts consecutive failures |
| `prosthesis_simulator.m` | 6-DOF simulator (A–E fingers + F wrist): `reset`, `command`, `state`, `plot`, `start_server`, `stop_server` |

## Sent JSON

```json
{"command":"#C","finger":"MULTI","action":"gesture","value":77,"confidence":0.93,
 "trigger_channels":[4,2,1,3,5],"source":"llm","cycle":128,"timestamp":"2026-09-16T11:20:00.123"}
```

`source` is `llm`, `lda` or `safety`. `cycle = -1` marks the safe command sent when
shutting down. The full protocol is in [../docs/protocol.md](../docs/protocol.md).

## Simulator

**In-process** (`protocol = 'SIM'`): no network. Commands update the internal angles.

```matlab
create_server_prosthesis_config('protocol', 'SIM');
prosthesis_simulator('plot');    % optional: live bars
main('Source', 'simulated');
```

**HTTP server**: run it in a **second MATLAB session**. MATLAB runs callbacks on the same
thread, so a server in the same session as `main` could not answer while `main` waits
inside `webwrite`.

```matlab
% MATLAB session 2
prosthesis_simulator('start_server', 8080);
prosthesis_simulator('plot');
% MATLAB session 1
create_server_prosthesis_config('ip', '127.0.0.1', 'port', 8080);
test_prosthesis_connection('Sweep', true)
```

Gesture angles scale as `preset × (0.4 + 0.6 · value/100)`, so a gesture stays
recognizable even at low strength. `#R` goes back to the neutral pose `[20 20 20 20 20 90]`.
