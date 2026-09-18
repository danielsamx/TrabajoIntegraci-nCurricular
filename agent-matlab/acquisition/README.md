# acquisition/

> Español: [README.es.md](README.es.md)

sEMG acquisition from the Myo Armband (8 channels, 200 Hz).

| File | Role |
|---|---|
| `myo_interface.m` | `handle` class plus singleton. Sources: `myo` (native BLE), `udp`, `simulated`. 5 s circular buffer |
| `get_signals.m` | `[emg_window, fs] = get_signals(200)` returns the last 40x8 samples |
| `calibrate.m` | Per-user calibration protocol (see `docs/calibration_guide.md`) |

## Sources

### `myo`: native Bluetooth LE (no Myo Connect, no MEX)

`myo_interface` implements the open Myo GATT protocol (`myohw.h`) with base MATLAB's `ble()`:

- Control service `D5060001-…`, command characteristic `D5060401-…`
- EMG service `D5060005-…`, 4 notify characteristics `D5060105/0205/0305/0405-…`
- Each notification carries 16 bytes: 2 samples × 8 `int8` channels
- Commands sent on connect: `[09 01 01]` (never sleep), `[0A 01 02]` (unlock hold),
  `[01 03 emg 00 00]` (EMG on, IMU off, classifier off), then a short vibration

```matlab
myo_interface.instance('source', 'myo', 'device_name', 'Myo');   % or 'device_address', '...'
[emg, fs] = get_signals(200);
```

`emg_mode = 2` sends EMG filtered by the armband. `3` sends raw EMG.

### `udp`

Any external streamer can send binary datagrams to `udp_port` (10001). The format is the
same as BLE: a multiple of 8 bytes, `int8`, ordered sample by sample (CH1..CH8).

### `simulated`

Generates synthetic EMG that follows the reference anatomical map. With `sim_label = 'auto'`
it runs the script `REST, D2, REST, D3, …, #C, REST, #O, REST, #P`, 2 s per step. With
`sim_realtime = false` each read creates exactly `n` new samples, which makes tests
deterministic.

## Circular buffer

BLE callbacks write into the buffer as data arrives. `read_window(n)` returns the last `n`
samples. If nothing has arrived for `stale_timeout` (1 s), it returns `is_fresh = false`.
`get_signals` then logs a warning, and `filter_noise` marks the window as `NOISE`
(flat channel).

> MATLAB runs callbacks when it is idle (`pause`, `drawnow`). The main loop always ends with
> `pause`, and `read_window` calls `pause(0.001)` so the callbacks run.
