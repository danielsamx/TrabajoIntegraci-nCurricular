# processing/

> English: [README.md](README.md)

Convierte una ventana de 40x8 en las entradas del modelo.

| Archivo | Firma | Función |
|---|---|---|
| `process_signals.m` | `[rms, mav, state, emg_f, rms_raw, mav_raw] = process_signals(emg, fs, calib)` | Quita el DC, aplica un pasa-banda Butterworth de orden 4 (20–95 Hz, `filtfilt`) y un notch de 60 Hz diseñado a mano, calcula RMS/MAV y los normaliza. Estado: REST < 0.15 ≤ TRANSITION < 0.40 ≤ ACTIVE (según el canal **máximo**) |
| `filter_noise.m` | `[state, is_clean, reason] = filter_noise(emg, emg_f, rms, state)` | Marca `NOISE` por saturación (>5 % de muestras en ±127), canal plano o artefacto de movimiento (energía filtrada/cruda < 0.20) |
| `normalize_signals.m` | `v = normalize_signals(values, calib, 'rms'/'mav')` | `clamp((x − reposo)/(mvc − reposo), 0, 1)` |
| `build_payload.m` | `payload = build_payload(rms, mav, state, calib, prev, t_ms)` | Línea ASCII para el LLM |
| `generate_heatmap.m` | `img_path = generate_heatmap(rms, state, t, opts)` | PNG de 640x480: barras turbo, umbrales 0.15/0.40, valores y título |

## Payload

```
RMS:[0.06,0.08,0.21,0.82,0.19,0.05,0.44,0.07]|MAV:[...]|STATE:ACTIVE|CALIB:[D1=5+6,D2=4+7,D3=3+7,D4=2+8,D5=1+8]|PREV:#R:000|T:10240
```

- Los valores se recortan a [0,1] con 2 decimales, lo que mantiene bajo el número de tokens.
- `CALIB` lleva los 2 canales dominantes de cada dedo del usuario. `,DEFAULT` marca una
  calibración genérica, y `NONE` significa que no hay calibración.
- `PREV` lleva el último comando enviado y su valor con 3 dígitos, o `NONE`.
- El payload siempre es ASCII puro.

## Imagen

- `render_mode = 'figure'` (por defecto) usa una figura invisible persistente que se
  actualiza con `set` y se captura con `print -RGBImage`. Incluye título, valores y
  etiquetas.
- `render_mode = 'raster'` dibuja directamente en píxeles, sin texto. Es 10–20× más rápido y
  sirve para imágenes pequeñas (320x240) cuando importa la latencia.
- Ambos modos reescalan al tamaño exacto por vecino más cercano, porque `imresize` pertenece
  a Image Processing Toolbox y no está permitido.

## Por qué no se descarta una ventana ruidosa

El LLM debe invocarse en cada ciclo, así que la ventana sale con `STATE:NOISE` y el prompt
aplica la regla R1 (mantener `PREV`).
