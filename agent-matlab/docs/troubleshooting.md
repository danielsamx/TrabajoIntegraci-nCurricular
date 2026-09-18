# Troubleshooting

> Español: [troubleshooting.es.md](troubleshooting.es.md)

Start with `main_debug`. It shows the EMG, the RMS, the latencies, the source of each
decision (green = LLM, orange = LDA), the LLM's answer and the exact image sent. Per-cycle
logs are in `logs/llm_*.jsonl`, and the console log is in `logs/main_*.log`.

## Setup

| Symptom | Fix |
|---|---|
| `Se requiere MATLAB R2023b` | Update MATLAB. `isMATLABReleaseOlderThan`, `backgroundPool`, `clim`, `tcpserver` and others need recent releases |
| `Signal Processing Toolbox es obligatorio` | Install it from the Add-On Explorer |
| `Undefined function 'get_signals'` | Run `setup` (it adds the paths) or `addpath(genpath(pwd))` from the project root |
| `Falta config/...mat` | Run `setup`, or the matching `create_*_config` |
| Changed a `prompts/*.txt` but nothing changed | Run `create_prompt_llm_config` again |

## LM Studio / LLM

| Symptom | Cause | Fix |
|---|---|---|
| `test_llm_connection`: `/v1/models` fails | Server stopped, `Serve on Local Network` off, firewall, wrong IP | Check in LM Studio → Developer. From another PC: `http://<ip>:1234/v1/models` in a browser |
| Every cycle `LDA`, error `timeout` | The 7B VLM takes longer than `timeout` | Measure the warm latency with `test_llm_connection`. Raise it with `create_server_llm_config('timeout', 1.5)`. Use a lighter image with `create_prompt_llm_config('render_mode','raster','image_width',320,'image_height',240)` |
| First call is very slow | Model loading, vision encoder, prompt caching | Normal. The test does 2 calls; the second is the representative one. Disable auto-unload in LM Studio |
| `invalid JSON` / `no JSON object found` | The model writes text or markdown | Check `llm_content` in the log. Try `create_server_llm_config('use_json_schema', true)`. Check that `temperature = 0` |
| `finger mismatch` / `action not allowed` | The model mixes `C` (middle) with `#C` (fist) | Usually a sign of a weak model or a long context. Reduce the context, use JSON Schema, check the prompt language |
| HTTP 400 `image` / `vision` | The loaded model has no vision | Load **Qwen2.5-VL** (VL = vision-language) and check the model name in `server_llm.models` |
| HTTP 400 with `response_format` | The LM Studio version does not support it | `use_json_schema = false` |
| Context overflow | Few-shot as messages + long prompt | `use_few_shot_messages = false` (default) and raise the context length in LM Studio |
| N=4: one port is never used | That port is down; failover jumps over it | See `Puerto / Port` in `llm_logger('summary')`. Start that instance |
| `parallel` switches to sequential | `webwrite` is not supported in `backgroundPool` in your release | Expected. Use `round-robin` |

## Myo Armband

| Symptom | Fix |
|---|---|
| `ble("Myo")` does not find the device | Close **Myo Connect** (it holds the connection). Wake the Myo by moving it. Pair it under Windows Settings → Bluetooth. Use `blelist` to see its name or address and pass `'MyoDevice', '<address>'` |
| Connects, but `Sin datos recientes` (no recent data) | The armband went to sleep or the notifications were not subscribed. Disconnect with `myo_interface.instance('reset')`, move the Myo and run `main` again |
| `STATE:NOISE` with `flat channel` | No data is arriving (stale buffer) or a pod has no contact |
| `STATE:NOISE` with `saturation` | Very strong contraction or poor contact. Reduce the force, check the fit |
| `STATE:NOISE` with `motion artifact` | Arm movement or a loose cable/armband. Rest your elbow on the table |
| Always `REST` even when contracting | Wrong calibration (MVC too high) or `emg_mode` changed after calibrating. Recalibrate |
| 50/60 Hz hum | `PowerlineHz` must match the mains frequency (60 in Ecuador) |
| BLE drops packets while the LLM is running | MATLAB callbacks wait while `webwrite` blocks. The 5 s buffer absorbs the gap, but if the LLM takes more than 5 s, samples are lost. Lower `timeout` |

## Classification

| Symptom | Fix |
|---|---|
| Wrong finger, consistently | Armband rotated since calibration: recalibrate. Check that `CALIB` in the payload changes accordingly |
| Ring and little finger confused | Common (shared musculature). Calibrate with clearly isolated contractions. Consider an 8th rep |
| Command flickers | Raise `window` in `smooth_command` (a K=5 vote) or `fast_confidence` to 0.9 |
| Too much delay when changing fingers | Lower `fast_confidence` (0.75) or `window` (1 = no smoothing) |
| LDA `cv_accuracy` < 80 % | Repeat the calibration with steadier contractions, and add `'Reps', 8` |

## Prosthesis

| Symptom | Fix |
|---|---|
| `prot FAIL` in every cycle | IP/port/endpoint. Firewall. The server must answer 2xx within `timeout` |
| `N fallos consecutivos` (N consecutive failures) | Link lost. `main` keeps going. Check WiFi and power |
| Simulator HTTP server does not answer | It must run in **another** MATLAB session (callbacks share the thread) |
| The hand does not relax on exit | Check that the firmware accepts `#R` (`cycle = -1`, `source = safety`) and add a watchdog |

## Performance

- `render_mode = 'raster'` + 320x240 saves 30–70 ms in MATLAB and ~70 % of the image tokens.
- Close other figures while `main` runs. `main_debug` uses `drawnow limitrate`.
- `Verbose = false` reduces console output.
- Check `mean_cycle_ms` and `mean_llm_ms` in the summary returned by `main`.
