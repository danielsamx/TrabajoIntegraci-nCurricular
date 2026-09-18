# acquisition/

> English: [README.md](README.md)

Adquisición de sEMG del Myo Armband (8 canales, 200 Hz).

| Archivo | Función |
|---|---|
| `myo_interface.m` | Clase `handle` más singleton. Fuentes: `myo` (BLE nativo), `udp`, `simulated`. Buffer circular de 5 s |
| `get_signals.m` | `[emg_window, fs] = get_signals(200)` devuelve las últimas 40x8 muestras |
| `calibrate.m` | Protocolo de calibración por usuario (vea `docs/calibration_guide.es.md`) |

## Fuentes

### `myo`: Bluetooth LE nativo (sin Myo Connect ni MEX)

`myo_interface` implementa el protocolo GATT abierto del Myo (`myohw.h`) con la función
`ble()` de MATLAB base:

- Servicio de control `D5060001-…`, característica de comandos `D5060401-…`
- Servicio EMG `D5060005-…`, 4 características notify `D5060105/0205/0305/0405-…`
- Cada notificación trae 16 bytes: 2 muestras × 8 canales `int8`
- Comandos que se envían al conectar: `[09 01 01]` (no dormir), `[0A 01 02]` (desbloqueo),
  `[01 03 emg 00 00]` (EMG activo, IMU apagada, clasificador apagado) y una vibración corta

```matlab
myo_interface.instance('source', 'myo', 'device_name', 'Myo');   % o 'device_address', '...'
[emg, fs] = get_signals(200);
```

`emg_mode = 2` envía el EMG filtrado por el brazalete. `3` envía el EMG crudo.

### `udp`

Cualquier emisor externo puede enviar datagramas binarios a `udp_port` (10001). El formato
es el mismo que en BLE: múltiplo de 8 bytes, `int8`, ordenados muestra a muestra (CH1..CH8).

### `simulated`

Genera EMG sintético que sigue el mapa anatómico de referencia. Con `sim_label = 'auto'`
recorre el guion `REST, D2, REST, D3, …, #C, REST, #O, REST, #P`, 2 s por paso. Con
`sim_realtime = false` cada lectura crea exactamente `n` muestras nuevas, lo que hace que
las pruebas sean deterministas.

## Buffer circular

Los callbacks BLE escriben en el buffer a medida que llegan los datos. `read_window(n)`
devuelve las últimas `n` muestras. Si no llega nada durante `stale_timeout` (1 s), devuelve
`is_fresh = false`. `get_signals` registra entonces un aviso, y `filter_noise` marca la
ventana como `NOISE` (canal plano).

> MATLAB ejecuta los callbacks cuando está libre (`pause`, `drawnow`). El bucle principal
> siempre termina con `pause`, y `read_window` llama a `pause(0.001)` para que se ejecuten.
