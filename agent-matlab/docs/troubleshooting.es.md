# Solución de problemas

> English: [troubleshooting.md](troubleshooting.md)

Empiece por `main_debug`. Muestra el EMG, el RMS, las latencias, el origen de cada decisión
(verde = LLM, naranja = LDA), la respuesta del LLM y la imagen exacta enviada. Los logs por
ciclo están en `logs/llm_*.jsonl`, y el log de consola en `logs/main_*.log`.

## Instalación

| Síntoma | Solución |
|---|---|
| `Se requiere MATLAB R2023b` | Actualice MATLAB. `isMATLABReleaseOlderThan`, `backgroundPool`, `clim`, `tcpserver` y otras funciones necesitan versiones recientes |
| `Signal Processing Toolbox es obligatorio` | Instálelo desde el Add-On Explorer |
| `Undefined function 'get_signals'` | Ejecute `setup` (añade las rutas) o `addpath(genpath(pwd))` desde la raíz del proyecto |
| `Falta config/...mat` | Ejecute `setup` o el `create_*_config` correspondiente |
| Cambié un `prompts/*.txt` y no cambió nada | Vuelva a ejecutar `create_prompt_llm_config` |

## LM Studio / LLM

| Síntoma | Causa | Solución |
|---|---|---|
| `test_llm_connection`: falla `/v1/models` | Servidor detenido, `Serve on Local Network` desactivado, firewall, IP incorrecta | Revise LM Studio → Developer. Desde otro PC: `http://<ip>:1234/v1/models` en un navegador |
| Todos los ciclos `LDA`, error `timeout` | El VLM de 7B tarda más que `timeout` | Mida la latencia en caliente con `test_llm_connection`. Súbalo con `create_server_llm_config('timeout', 1.5)`. Use una imagen más ligera con `create_prompt_llm_config('render_mode','raster','image_width',320,'image_height',240)` |
| La primera llamada es muy lenta | Carga del modelo, codificador de visión, caché del prompt | Es normal. La prueba hace 2 llamadas; la segunda es la representativa. Desactive la descarga automática en LM Studio |
| `invalid JSON` / `no JSON object found` | El modelo escribe texto o markdown | Revise `llm_content` en el log. Pruebe `create_server_llm_config('use_json_schema', true)`. Compruebe que `temperature = 0` |
| `finger mismatch` / `action not allowed` | El modelo confunde `C` (medio) con `#C` (puño) | Suele indicar un modelo débil o un contexto largo. Reduzca el contexto, use JSON Schema, revise el idioma del prompt |
| HTTP 400 `image` / `vision` | El modelo cargado no tiene visión | Cargue **Qwen2.5-VL** (VL = visión-lenguaje) y revise el nombre en `server_llm.models` |
| HTTP 400 con `response_format` | Su versión de LM Studio no lo admite | `use_json_schema = false` |
| Desbordamiento de contexto | Few-shot como mensajes + prompt largo | `use_few_shot_messages = false` (por defecto) y suba la longitud de contexto en LM Studio |
| N=4: un puerto nunca se usa | Ese puerto está caído; el failover lo salta | Vea `Puerto / Port` en `llm_logger('summary')`. Arranque esa instancia |
| `parallel` pasa a secuencial | Su versión no admite `webwrite` en `backgroundPool` | Es lo esperado. Use `round-robin` |

## Myo Armband

| Síntoma | Solución |
|---|---|
| `ble("Myo")` no encuentra el dispositivo | Cierre **Myo Connect** (retiene la conexión). Despierte el Myo moviéndolo. Emparéjelo en Configuración de Windows → Bluetooth. Use `blelist` para ver su nombre o dirección y pase `'MyoDevice', '<dirección>'` |
| Se conecta, pero aparece `Sin datos recientes` | El brazalete se durmió o no se activaron las notificaciones. Desconecte con `myo_interface.instance('reset')`, mueva el Myo y vuelva a ejecutar `main` |
| `STATE:NOISE` con `flat channel` | No llegan datos (buffer sin actualizar) o un pod no hace contacto |
| `STATE:NOISE` con `saturation` | Contracción muy fuerte o mal contacto. Reduzca la fuerza, revise el ajuste |
| `STATE:NOISE` con `motion artifact` | Movimiento del brazo o brazalete suelto. Apoye el codo en la mesa |
| Siempre `REST` aunque contraiga | Calibración errónea (MVC demasiado alto) o `emg_mode` cambiado tras calibrar. Recalibre |
| Zumbido de 50/60 Hz | `PowerlineHz` debe coincidir con la frecuencia de la red (60 en Ecuador) |
| BLE pierde paquetes mientras trabaja el LLM | Los callbacks de MATLAB esperan mientras `webwrite` bloquea. El buffer de 5 s absorbe la espera, pero si el LLM tarda más de 5 s se pierden muestras. Baje `timeout` |

## Clasificación

| Síntoma | Solución |
|---|---|
| Dedo equivocado de forma sistemática | Brazalete rotado desde la calibración: recalibre. Compruebe que `CALIB` cambia en el payload en consecuencia |
| Confusión entre anular y meñique | Es habitual (musculatura compartida). Calibre con contracciones bien aisladas. Considere 8 repeticiones |
| El comando parpadea | Suba `window` en `smooth_command` (voto K=5) o `fast_confidence` a 0.9 |
| Demasiado retardo al cambiar de dedo | Baje `fast_confidence` (0.75) o `window` (1 = sin suavizado) |
| `cv_accuracy` del LDA < 80 % | Repita la calibración con contracciones más constantes y añada `'Reps', 8` |

## Prótesis

| Síntoma | Solución |
|---|---|
| `prot FAIL` en todos los ciclos | IP/puerto/endpoint. Firewall. El servidor debe responder 2xx dentro de `timeout` |
| `N fallos consecutivos` | Enlace perdido. `main` sigue funcionando. Revise la WiFi y la alimentación |
| El servidor HTTP del simulador no responde | Debe ejecutarse en **otra** sesión de MATLAB (los callbacks comparten el hilo) |
| La mano no se relaja al salir | Compruebe que el firmware acepta `#R` (`cycle = -1`, `source = safety`) y añada un watchdog |

## Rendimiento

- `render_mode = 'raster'` + 320x240 ahorra 30–70 ms en MATLAB y ~70 % de los tokens de la
  imagen.
- Cierre otras figuras mientras corre `main`. `main_debug` usa `drawnow limitrate`.
- `Verbose = false` reduce la salida por consola.
- Revise `mean_cycle_ms` y `mean_llm_ms` en el resumen que devuelve `main`.
