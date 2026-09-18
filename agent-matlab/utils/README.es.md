# utils/

> English: [README.md](README.md)

| Archivo | Función |
|---|---|
| `train_lda.m` | LDA en forma cerrada (covarianza combinada + contracción 0.1) sobre 16 rasgos `[rms_norm, mav_norm]`. Clases `pulgar, D2, D3, D4, D5`. Validación cruzada de 5 particiones reproducible. `fitcdiscr` solo se usa como verificación si Statistics Toolbox está disponible |
| `lda_classify.m` | `[label, confidence, posteriors] = lda_classify(model, features)`: softmax(W·x + b), menos de 1 ms |
| `smooth_command.m` | Voto mayoritario sobre los últimos K = 3 comandos + EMA del valor (α = 0.5). Vía rápida con confianza ≥ 0.85. `#R` cambia con confianza ≥ 0.60. El campo de salida `smoothing` vale `pass`, `ema` o `held` |
| `label_to_finger.m` | **La única tabla de dedos/gestos**: comando, dedo, nombres, rango, canales primarios, acciones permitidas, alias (`'pulgar'`, `'thumb'`, `'D1'` → `A`) |
| `rms_to_value.m` | Reglas de value del prompt (flex, extend, rotate, gesture, hold, rest) |
| `is_composite_gesture.m` | Reglas de gestos compuestos G1–G10 del prompt |
| `base64encode.m` | `matlab.net.base64encode` con respaldo vectorizado en MATLAB puro |
| `logger.m` | `logger('INFO', 'modulo', fmt, ...)` con marca de tiempo, niveles, stderr para ERROR y archivo opcional |

## Tabla de dedos

| command | finger | rango |
|---|---|---|
| A | D1 pulgar | 0–90 |
| B | D2 índice | 0–120 |
| C | D3 medio | 0–120 |
| D | D4 anular | 0–120 |
| E | D5 meñique | 0–120 |
| F | WRIST muñeca | 0–180 (90 neutro) |
| #O #C #P #W #Y #L #M #H #U #G | MULTI | 0–100 % |
| #R | NONE | 0 |

## Fallback LDA (en `main.m`)

1. `NOISE` → mantener `PREV`
2. `REST` o máximo < 0.15 → `#R`
3. `is_composite_gesture` → gesto, o mantener si ninguna regla de gesto coincide
4. `TRANSITION` → mantener `PREV`
5. LDA → dedo, `flex`, y value con `rms_to_value` usando los canales dominantes del usuario
