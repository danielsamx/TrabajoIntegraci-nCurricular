# utils/

> Español: [README.es.md](README.es.md)

| File | Role |
|---|---|
| `train_lda.m` | Closed-form LDA (pooled covariance + shrinkage 0.1) over 16 features `[rms_norm, mav_norm]`. Classes `pulgar, D2, D3, D4, D5`. Reproducible 5-fold CV. `fitcdiscr` is only used as a cross-check when Statistics Toolbox is available |
| `lda_classify.m` | `[label, confidence, posteriors] = lda_classify(model, features)`: softmax(W·x + b), under 1 ms |
| `smooth_command.m` | Majority vote over the last K = 3 commands + value EMA (α = 0.5). Fast path when confidence ≥ 0.85. `#R` switches with confidence ≥ 0.60. Output field `smoothing` = `pass`, `ema` or `held` |
| `label_to_finger.m` | **The single finger/gesture table**: command, finger, names, range, primary channels, allowed actions, aliases (`'pulgar'`, `'thumb'`, `'D1'` → `A`) |
| `rms_to_value.m` | Value rules from the prompt (flex, extend, rotate, gesture, hold, rest) |
| `is_composite_gesture.m` | Composite gesture rules G1–G10 from the prompt |
| `base64encode.m` | `matlab.net.base64encode` with a vectorized pure-MATLAB fallback |
| `logger.m` | `logger('INFO', 'module', fmt, ...)` with a timestamp, levels, stderr for ERROR and an optional file |

## Finger table

| command | finger | range |
|---|---|---|
| A | D1 thumb | 0–90 |
| B | D2 index | 0–120 |
| C | D3 middle | 0–120 |
| D | D4 ring | 0–120 |
| E | D5 little | 0–120 |
| F | WRIST | 0–180 (90 neutral) |
| #O #C #P #W #Y #L #M #H #U #G | MULTI | 0–100 % |
| #R | NONE | 0 |

## LDA fallback (in `main.m`)

1. `NOISE` → hold `PREV`
2. `REST` or max < 0.15 → `#R`
3. `is_composite_gesture` → gesture, or hold if no gesture rule matches
4. `TRANSITION` → hold `PREV`
5. LDA → finger, `flex`, and value from `rms_to_value` using the user's dominant channels
