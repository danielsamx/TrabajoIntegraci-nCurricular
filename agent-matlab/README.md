# Robotic hand prosthesis control with sEMG + LLM (MATLAB)

> Español: [README.es.md](README.es.md)

Reads 8 EMG channels from a **Myo Armband**, sends each 200 ms window (text + image) to an
**LLM in LM Studio**, and sends the resulting command to the **prosthesis** over HTTP, serial or
Bluetooth Classic (SPP, MATLAB `bluetooth`, default device `Handi_EPN_V3`; needs a PC Bluetooth radio,
the Myo's BLED112 dongle cannot be used).
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

Actions follow the Handi EPN V3 manual: `C` close, `O` open, `S` stop motors (hand stays), or one
position per finger `A..B..C..D..E..F..` (e.g. `A240B240C300D240E80F70`) for partial closure. The vision
model is not trained on EMG: every step (filters, rectification, RMS, SIM, DIST, activation, closure,
posture) is computed first and printed as PASO1..PASO10; the model gets the measures plus images and
answers `{"command","confidence","reason"}`.

Only the LLM decides: on start the server is checked with `GET /v1/models` (no server or missing
model = the session does not start), and if a cycle gets no valid answer nothing is sent to the
prosthesis. There is no local fallback.

See [README.es.md](README.es.md) for the file layout and the console output.
