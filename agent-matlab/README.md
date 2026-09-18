# sEMG + LLM Robotic Hand Prosthesis Control (MATLAB)

> Español: [README.es.md](README.es.md)

A 100 % MATLAB real-time agent that reads 8-channel sEMG from a **Myo Armband**, works out
which finger (or preset gesture) the user is moving, and sends the command to a **robotic
hand prosthesis** over HTTP/REST. The **main classifier is a vision-language model**
(Qwen2.5-VL-7B) served by **LM Studio** on another machine on the same network. **It is called
on every cycle** with an **ASCII payload + a bar-chart image** of the signal. A local **LDA**
classifier only takes over as an **emergency fallback** when the LLM fails.

The architecture supports **N = 1 or N = 4 LM Studio ports with no code changes**. The only
thing that changes is `config/server-llm.mat`.

---

## Table of contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Quick start](#quick-start)
4. [Directory structure](#directory-structure)
5. [Agent flow](#agent-flow)
6. [LM Studio configuration](#lm-studio-configuration)
7. [Prosthesis configuration](#prosthesis-configuration)
8. [User calibration](#user-calibration)
9. [Troubleshooting](#troubleshooting)
10. [Design notes and assumptions](#design-notes-and-assumptions)
11. [License](#license)
12. [Contact](#contact)

---

## Requirements

| Component | Version / notes |
|---|---|
| MATLAB | **R2023b or newer** |
| Signal Processing Toolbox | **Required** (`butter`, `zp2sos`, `filtfilt`) |
| Statistics and Machine Learning Toolbox | Optional (used only to cross-check the LDA with `fitcdiscr`) |
| LM Studio | Running on a machine on the same LAN, with **Qwen2.5-VL-7B-Instruct** loaded and the local server enabled (`Serve on Local Network`) |
| Myo Armband | Connected over **Bluetooth LE** (built-in `ble()` in MATLAB). As alternatives, a UDP streamer or the built-in simulator |
| Prosthesis | HTTP server that accepts `POST /api/command` with JSON (e.g. an ESP32). As an alternative, the included simulator |
| OS | Windows 10/11 recommended (BLE support in MATLAB) |

No other toolboxes and no Python, C++ or MEX files are used.

## Installation

1. Copy or clone the `proyecto_protesis/` folder.
2. Open MATLAB R2023b+ and `cd` into `proyecto_protesis/`.
3. Run:

   ```matlab
   setup
   ```

   `setup` checks the MATLAB version and toolboxes and creates `logs/`. It adds the project
   folders to the path and generates any missing `config/*.mat` files. Then it runs the
   offline tests and the connection tests. Connection tests may fail if LM Studio or the
   prosthesis are not running yet; that is expected.
4. Point the configuration at your network:

   ```matlab
   create_server_llm_config('ip', '192.168.1.100');          % LM Studio
   create_server_prosthesis_config('ip', '192.168.1.101');   % prosthesis
   ```

5. Check the connections:

   ```matlab
   test_llm_connection
   test_prosthesis_connection
   ```

6. Calibrate the user (see [User calibration](#user-calibration)):

   ```matlab
   calibrate('Source', 'myo', 'UserId', 'daniel')
   ```

> `.mat` files are binary. Do not edit them by hand. Regenerate them with the
> `create_*_config` functions, which take name-value pairs.

## Quick start

```matlab
setup                                        % once
main('Source', 'simulated', 'Duration', 30)  % no hardware: simulated Myo
main                                         % real Myo over BLE
main_debug                                   % same loop + live dashboard
```

Useful `main` options: `'Source'` (`'myo'|'udp'|'simulated'`), `'MyoDevice'`, `'Period'`
(0.2 s), `'Duration'`, `'MaxCycles'`, `'Verbose'`.

To try everything **without any hardware or network**, generate a simulated-prosthesis
config and run the offline tests:

```matlab
create_server_prosthesis_config('protocol', 'SIM');
test_payload; test_parallel_ports; test_full_pipeline;
```

Stop the loop with **Ctrl+C**, or by closing the `main_debug` window. Either way `main`
sends the safe command `#R` (rest) and releases the Myo.

## Directory structure

```
proyecto_protesis/
├── README.md / README.es.md     General documentation
├── CHANGELOG.md, LICENSE, .gitignore
├── setup.m                      Initial setup
├── main.m                       Main loop
├── main_debug.m                 Main loop + visual dashboard
├── config/                      Generators for the .mat configuration files
├── prompts/                     System prompt (ES/EN), few-shot examples, calibration template
├── acquisition/                 Myo interface (BLE/UDP/simulated), window reader, calibration
├── processing/                  Filtering, RMS/MAV, noise rejection, image, payload
├── llm/                         Port abstraction, request body, parser, validator, logger
├── prosthesis/                  HTTP sender and local simulator
├── utils/                       LDA, smoothing, maps, Base64, logger
├── tests/                       Standalone tests (each returns true/false)
├── docs/                        Architecture, protocol, calibration, troubleshooting
└── logs/                        (generated) session logs and llm_*.jsonl
```

Each folder has its own `README.md` / `README.es.md`.

> **File names:** the specification asked for hyphenated names (`get-signals.m`). MATLAB
> cannot call those: `get-signals(x)` is parsed as `get - signals(x)`. All function files
> therefore use underscores (`get_signals.m`, `process_signals.m`, `send_input_llm.m`, …).
> Data files keep the hyphen (`server-llm.mat`).

## Agent flow

```
          ┌──────────────┐   BLE / UDP / sim   ┌──────────────────────────┐
          │  Myo Armband │ ──────────────────▶ │ myo_interface            │
          └──────────────┘   200 Hz x 8 ch     │ (circular buffer, 5 s)   │
                                               └────────────┬─────────────┘
 every cycle (target 200 ms)                                 │ get_signals(200) → 40x8
 ┌───────────────────────────────────────────────────────────▼──────────────────────────┐
 │ 1 process_signals   Butterworth 20-95 Hz + 60 Hz notch → RMS/MAV → normalize (calib) │
 │ 2 filter_noise      saturation / flat channel / motion artifact → STATE:NOISE        │
 │ 3 build_payload     RMS:[..]|MAV:[..]|STATE:..|CALIB:[..]|PREV:..|T:..               │
 │ 4 generate_heatmap  640x480 PNG, turbo bars, 0.15 / 0.40 thresholds                  │
 │ 5 send_input_llm    ALWAYS ─────HTTP────▶ LM Studio :1234 [:1235 :1236 :1237]        │
 │ 6 parse + validate  JSON → is_valid_response                                         │
 │ 7   └─ failed? ───▶ LDA fallback (rest/noise/gesture rules + LDA over 16 features)   │
 │ 8 smooth_command    majority vote K=3 + value EMA (+ fast path, safe #R)             │
 │ 9 send_signals_prosthesis ──HTTP POST /api/command──▶ prosthesis (or SIM)            │
 │10 llm_logger + wait for the next cycle                                               │
 └──────────────────────────────────────────────────────────────────────────────────────┘
```

Full details are in [docs/architecture.md](docs/architecture.md).

## LM Studio configuration

1. In LM Studio, download and load **Qwen2.5-VL-7B-Instruct** (a vision model is required).
2. Open **Developer → Local Server**, start the server on port `1234` and enable **Serve on
   Local Network**. Allow the port through the firewall.
3. Recommended: context of at least 8k tokens (the system prompt is ~3k tokens plus ~400
   image tokens), GPU offload at maximum, and keep the model loaded (no auto-unload).
4. In MATLAB:

   ```matlab
   create_server_llm_config('ip', '<LM Studio IP>');                         % N = 1
   create_server_llm_config('ip', '<IP>', 'ports', [1234 1235 1236 1237], ...
                            'mode', 'round-robin');                          % N = 4
   ```

   N = 4 means four LM Studio servers or instances, one per port. With
   `'models', {'m1','m2','m3','m4'}` you can use one model per port. With
   `'ips', {...}` each port can live on a different machine.

Main fields of `server_llm`:

| Field | Default | Meaning |
|---|---|---|
| `ip` | `192.168.1.100` | LM Studio host |
| `ports` | `1234` | Port array (N = numel) |
| `models` | `{'qwen2.5-vl-7b-instruct'}` | One shared model or one per port |
| `mode` | `sequential` | `sequential`, `round-robin` or `parallel` (experimental, `backgroundPool`) |
| `timeout` | `0.5` s | Per-cycle LLM time budget |
| `temperature` / `top_p` | `0` / `1` | Deterministic output |
| `max_tokens` | `200` | Output tokens |
| `stop` | `}\n`, `}\r\n`, `\n\n` | Stop sequences (built with real line breaks) |
| `use_json_schema` | `false` | Sends `response_format` with a JSON Schema |
| `transport` | `http` | `mock` = offline deterministic classifier (tests) |

> ⚠️ **Latency:** a 7B vision model rarely answers in under 500 ms on consumer GPUs,
> because the image has to be encoded on every call. Run `test_llm_connection` to measure
> the warm latency. Then either raise `timeout`
> (`create_server_llm_config('timeout', 1.5)`) or use a smaller, faster image
> (`create_prompt_llm_config('render_mode','raster','image_width',320,'image_height',240)`).
> If the LLM does not answer in time, the LDA fallback decides that cycle and the LLM is
> still called on the next cycle.

## Prosthesis configuration

```matlab
create_server_prosthesis_config('ip', '192.168.1.101', 'port', 8080);   % real HTTP
create_server_prosthesis_config('protocol', 'SIM');                     % in-process simulator
```

The prosthesis receives `POST http://<ip>:<port>/api/command`:

```json
{"command":"B","finger":"D2","action":"flex","value":95,"confidence":0.92,
 "trigger_channels":[4,7],"source":"llm","cycle":42,"timestamp":"2026-09-16T11:20:00.123"}
```

It must reply with HTTP 2xx. The command table (A–F fingers, `#X` gestures) and the full
protocol are in [docs/protocol.md](docs/protocol.md). To emulate the prosthesis over HTTP,
open a **second MATLAB session** and run `prosthesis_simulator('start_server', 8080)` and
`prosthesis_simulator('plot')`.

## User calibration

```matlab
calib = calibrate('Source', 'myo', 'UserId', 'daniel', 'Reps', 5);
```

The protocol is:

1. 5 s at rest.
2. For the thumb, index, middle, ring and little finger: 5 flexions × 3 s each.
3. Maximum-force fist.
4. Maximum-force hand opening.

`calibrate` then computes the rest and MVC levels for each channel, the average profile of
each finger and the 2 dominant channels of each finger. Those channels travel to the LLM in
`CALIB`. It also trains and validates the LDA and saves `config/calibration.mat`. `setup`
creates a **generic calibration** (`is_default = true`) so the system can start right away.
Replace it with your own before real use. Step-by-step guide:
[docs/calibration_guide.md](docs/calibration_guide.md).

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Every cycle shows `LDA` | LLM timeout. Measure it with `test_llm_connection` and raise `timeout` or use the `raster` image |
| `ble` cannot find the Myo | Close Myo Connect, pair the armband in Windows, try `'MyoDevice'` with the BLE address |
| `STATE:NOISE` all the time | Armband loose or wet, wrong `PowerlineHz` (60 Hz in Ecuador/Americas, 50 Hz in Europe) |
| Wrong finger | Recalibrate. Check that `CALIB` shows the expected channels. Check the armband rotation |
| Prosthesis `FAIL` | IP/port, firewall, the endpoint must return 2xx within `timeout` |

More in [docs/troubleshooting.md](docs/troubleshooting.md).

## Design notes and assumptions

- The original specification referred to a "previous document" (sections 1, 2.1 and 4)
  that was not available. The system prompt, the channel map, the A–F table and the gesture
  rules were therefore designed from the requirements. The code mirrors them exactly:
  `is_composite_gesture.m` and `rms_to_value.m` implement the same rules, and
  `test_payload` checks that every prompt example matches the code.
- The channel map is a **reference placement**. Per-user calibration (`CALIB`) takes
  priority over it.
- Every design decision is documented in the code as
  `% DECISIÓN: … | RAZÓN: … | ALTERNATIVA DESCARTADA: …` (plus its English line).

## License

MIT. See [LICENSE](LICENSE).

## Contact

Author: Anderson — andersoncango09@gmail.com
Issues and suggestions: open an issue in the repository or write to the address above.

> ⚠️ This is a research prototype. It is not a certified medical device. Always test with
> the prosthesis unloaded and with an emergency stop within reach.
