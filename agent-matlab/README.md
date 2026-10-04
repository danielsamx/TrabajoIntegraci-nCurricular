# Robotic hand prosthesis control with sEMG + LLM (MATLAB)

> Español: [README.es.md](README.es.md)

Reads 8 EMG channels from a **Myo Armband**, sends each 200 ms window (text + image) to an
**LLM in LM Studio**, and posts the resulting command to the **prosthesis** over HTTP.
If the Myo is not active, the recordings `samples/muestra_1..15.csv` are processed instead.
No calibration is needed. Everything is printed to the console.

## Usage

```matlab
agent_ui          % graphical interface: settings sidebar, live dashboard, prompt editor
main              % Myo; falls back to the samples if it is not active
main('samples')   % play samples/ directly
```

All settings live in `config/agent_config.m`. **Ctrl+C** stops the agent and the rest command (`S`) is
always sent on exit. The full console output is saved to `logs/sesion_<date>.txt`.

Requirements: MATLAB R2023b+ with Signal Processing Toolbox, LM Studio with a vision model,
and a prosthesis server accepting `POST /api/command` with `{"command": "B"}`.

See [README.es.md](README.es.md) for the file layout and the console output.
