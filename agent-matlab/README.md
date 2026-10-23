# Robotic hand prosthesis control with sEMG + LLM (MATLAB)

> Español: [README.es.md](README.es.md)

Reads 8 EMG channels from a **Myo Armband**, sends each 200 ms window (text + image) to an
**LLM in LM Studio**, and posts the resulting command to the **prosthesis** over HTTP.
The Myo is the only source. No thresholds and no calibration: cosine similarity (`SIM`)
picks the gesture and the distance to rest vs that gesture (`DIST`) decides rest (`S`). Everything is printed to the console.

## Usage

```matlab
agent_ui          % graphical interface: settings sidebar, live dashboard, prompt editor
main              % console only, no interface
```

All settings live in `config/agent_config.m`. **Ctrl+C** stops the agent and the rest command (`S`) is
always sent on exit. The full console output is saved to `logs/sesion_<date>.txt`.

Requirements: MATLAB R2023b+ (no toolboxes needed), LM Studio with a vision model,
and a prosthesis server accepting `POST /api/command` with `{"command": "B"}`.

In the interface, the **Load** (Cargar) button next to *Modelo* fetches `GET /v1/models` and lists
the models available on the LLM server. The sidebar fills the visible height with no scrolling.

See [README.es.md](README.es.md) for the file layout and the console output.
