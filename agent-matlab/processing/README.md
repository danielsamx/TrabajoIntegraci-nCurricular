# processing/

> Español: [README.es.md](README.es.md)

Turns a 40x8 window into the model inputs.

| File | Signature | Role |
|---|---|---|
| `process_signals.m` | `[rms, mav, state, emg_f, rms_raw, mav_raw] = process_signals(emg, fs, calib)` | Removes DC, applies a 4th-order Butterworth band-pass (20–95 Hz, `filtfilt`) and a hand-designed 60 Hz notch, computes RMS/MAV and normalizes them. State: REST < 0.15 ≤ TRANSITION < 0.40 ≤ ACTIVE (based on the **maximum** channel) |
| `filter_noise.m` | `[state, is_clean, reason] = filter_noise(emg, emg_f, rms, state)` | Marks `NOISE` on saturation (>5 % of samples at ±127), a flat channel, or a motion artifact (filtered/raw energy < 0.20) |
| `normalize_signals.m` | `v = normalize_signals(values, calib, 'rms'/'mav')` | `clamp((x − rest)/(mvc − rest), 0, 1)` |
| `build_payload.m` | `payload = build_payload(rms, mav, state, calib, prev, t_ms)` | ASCII line for the LLM |
| `generate_heatmap.m` | `img_path = generate_heatmap(rms, state, t, opts)` | 640x480 PNG: turbo bars, 0.15/0.40 thresholds, values and title |

## Payload

```
RMS:[0.06,0.08,0.21,0.82,0.19,0.05,0.44,0.07]|MAV:[...]|STATE:ACTIVE|CALIB:[D1=5+6,D2=4+7,D3=3+7,D4=2+8,D5=1+8]|PREV:#R:000|T:10240
```

- Values are clipped to [0,1] with 2 decimals, which keeps the token count low.
- `CALIB` holds the user's 2 dominant channels per finger. `,DEFAULT` marks a generic
  calibration, and `NONE` means there is no calibration.
- `PREV` holds the last command sent and its 3-digit value, or `NONE`.
- The payload is always pure ASCII.

## Image

- `render_mode = 'figure'` (default) uses a persistent invisible figure that is updated with
  `set` and captured with `print -RGBImage`. It includes title, values and labels.
- `render_mode = 'raster'` draws directly into pixels with no text. It is 10–20× faster and
  suits small images (320x240) when latency matters.
- Both modes resize to the exact size with nearest-neighbour sampling, because `imresize`
  belongs to Image Processing Toolbox and is not allowed.

## Why a noisy window is not dropped

The LLM must be called on every cycle, so the window goes out with `STATE:NOISE` and the
prompt applies rule R1 (hold `PREV`).
