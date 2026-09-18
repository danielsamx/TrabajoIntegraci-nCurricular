# Calibration guide

> Español: [calibration_guide.es.md](calibration_guide.es.md)

Calibration adapts the system to each person: skin, fat, muscle size and, above all, **where
the armband sits**. Calibrate at the start of every session, and again whenever you take the
armband off.

## 1. Preparation

1. Clean the forearm skin (dry, no lotion).
2. Put the Myo on the **right forearm**, about one third of the way from the elbow, with the
   **USB port towards the wrist**.
3. Reference placement: **CH1 over the flexor carpi ulnaris** (palm up, little-finger side).
   The channels go around the palmar side towards the thumb (CH5) and come back over the
   dorsum (CH6–CH8).

   | Channel | Muscle (reference) | Finger |
   |---|---|---|
   | CH1 | Flexor carpi ulnaris | D5 flexion |
   | CH2 | Flexor digitorum superficialis (ulnar) | D4 flexion |
   | CH3 | Flexor digitorum superficialis (central) | D3 flexion |
   | CH4 | Flexor digitorum superficialis/profundus (radial) | D2 flexion |
   | CH5 | Flexor pollicis longus / flexor carpi radialis | D1 flexion |
   | CH6 | Abductor pollicis longus / thumb extensors | D1 extension |
   | CH7 | Extensor digitorum + extensor indicis | D2–D3 extension |
   | CH8 | Extensor digiti minimi + extensor carpi ulnaris | D4–D5 extension |

   The exact placement does **not** have to be perfect. Calibration measures the real
   dominant channels and sends them to the LLM in `CALIB`, which takes priority over this
   table.
4. Wait **2–3 minutes** so the skin–electrode contact stabilizes (the Myo warms up).
5. Sit down with your elbow resting on the table and your forearm relaxed.

## 2. Running the calibration

```matlab
calib = calibrate('Source', 'myo', 'UserId', 'daniel', 'Reps', 5, ...
                  'HoldSeconds', 3, 'RelaxSeconds', 2, 'PowerlineHz', 60);
```

The console shows each step in Spanish and English. Press **Enter**; the Myo vibrates and a
3-2-1 countdown starts. Hold the contraction until the step ends.

| # | Step | Duration | Instruction |
|---|---|---|---|
| 1 | Rest | 5 s | Hand completely relaxed |
| 2–6 | Thumb × 5 | 3 s each | Bend only the thumb towards the palm, **moderate, steady** force |
| 7–11 | Index × 5 | 3 s each | Bend only the index finger |
| 12–16 | Middle × 5 | 3 s each | Bend only the middle finger |
| 17–21 | Ring × 5 | 3 s each | Bend only the ring finger (the little finger may follow a little) |
| 22–26 | Little × 5 | 3 s each | Bend only the little finger |
| 27 | Fist MVC | 3 s | Close the fist with **maximum** force |
| 28 | Open MVC | 3 s | Open and spread the fingers with **maximum** force |

Tips:

- Vary the force slightly between repetitions (60–100 %). This makes the LDA more robust.
- Do not move your wrist or elbow.
- If you make a mistake, finish anyway and repeat the whole calibration.

## 3. What gets computed

1. The first 0.5 s of each contraction is discarded.
2. Non-overlapping 200 ms windows are filtered with the same chain as `main`.
3. `rest_rms` / `rest_mav` = median of the rest windows.
4. `mvc_rms` / `mvc_mav` = for each channel, the **maximum of the per-task medians**
   (fingers + fist + open hand).
5. Every window is normalized: `(x − rest) / (mvc − rest)`, clipped to [0,1].
6. Features = `[rms_norm, mav_norm]` (16) with the labels `pulgar, D2, D3, D4, D5`.
7. `profiles` = mean normalized RMS per finger. `top_channels` = the 2 highest channels.
8. The LDA is trained and 5-fold cross-validated (`cv_accuracy`).
9. Everything is saved to `config/calibration.mat` (variable `calib`).

The console prints the profile table:

```
Normalized RMS profile
clase      CH1   CH2   CH3   CH4   CH5   CH6   CH7   CH8   | top
pulgar    0.02  0.02  0.05  0.15  0.93  0.65  0.06  0.02   | 5+6
D2        0.02  0.04  0.20  0.79  0.18  0.02  0.42  0.04   | 4+7
...
```

## 4. How to judge the quality

| Indicator | Good | Acceptable | Repeat |
|---|---|---|---|
| `cv_accuracy` | ≥ 90 % | 80–90 % | < 80 % (the system warns you) |
| Main channel of each finger in `profiles` | ≥ 0.6 | 0.4–0.6 | < 0.4 |
| `top_channels` | different for each finger | two fingers share their 1st channel | three or more share it |

If two fingers share a channel (common for ring and little), that is fine. The LLM and the
LDA use the whole pattern. If the armband is **rotated**, `top_channels` shifts consistently
(for example D2=5+8 instead of 4+7). The LLM follows `CALIB`.

## 5. Generic calibration

`setup` creates a synthetic calibration (`is_default = true`) so you can test without a user.
`main` warns when it is in use, and the payload sends `CALIB:[…,DEFAULT]`, which tells the
LLM to cap its confidence at 0.80. **Do not use it with a real user.**

```matlab
create_calibration_config('Overwrite', true);   % regenerate the generic calibration
```

## 6. Calibration without hardware

```matlab
calib = calibrate('Source', 'simulated', 'Interactive', false, 'Seed', 1);
```

This generates the data instantly with the synthetic generator.
