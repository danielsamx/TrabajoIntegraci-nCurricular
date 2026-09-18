# Control de prótesis de mano robótica con sEMG + LLM (MATLAB)

> English: [README.md](README.md)

Agente en tiempo real, 100 % MATLAB. Lee sEMG de 8 canales de un **Myo Armband**, identifica
qué dedo (o gesto preestablecido) mueve el usuario y envía el comando a una **prótesis de
mano robótica** por HTTP/REST. El **clasificador principal es un modelo de visión y lenguaje**
(Qwen2.5-VL-7B) servido por **LM Studio** en otra máquina de la misma red. **Se le llama en
cada ciclo** con un **payload ASCII + una imagen de barras** de la señal. Un clasificador
**LDA** local solo toma el control como **respaldo de emergencia** cuando el LLM falla.

La arquitectura admite **N = 1 o N = 4 puertos de LM Studio sin cambiar código**. Lo único que
cambia es `config/server-llm.mat`.

---

## Índice

1. [Requisitos](#requisitos)
2. [Instalación](#instalación)
3. [Uso rápido](#uso-rápido)
4. [Estructura de directorios](#estructura-de-directorios)
5. [Flujo del agente](#flujo-del-agente)
6. [Configuración de LM Studio](#configuración-de-lm-studio)
7. [Configuración de la prótesis](#configuración-de-la-prótesis)
8. [Calibración del usuario](#calibración-del-usuario)
9. [Solución de problemas](#solución-de-problemas)
10. [Notas de diseño y supuestos](#notas-de-diseño-y-supuestos)
11. [Licencia](#licencia)
12. [Contacto](#contacto)

---

## Requisitos

| Componente | Versión / notas |
|---|---|
| MATLAB | **R2023b o superior** |
| Signal Processing Toolbox | **Obligatorio** (`butter`, `zp2sos`, `filtfilt`) |
| Statistics and Machine Learning Toolbox | Opcional (solo para verificar el LDA con `fitcdiscr`) |
| LM Studio | En una máquina de la misma LAN, con **Qwen2.5-VL-7B-Instruct** cargado y el servidor local activo (`Serve on Local Network`) |
| Myo Armband | Conectado por **Bluetooth LE** (función `ble()` de MATLAB). Como alternativa, un emisor UDP o el simulador integrado |
| Prótesis | Servidor HTTP que acepte `POST /api/command` con JSON (p. ej. un ESP32). Como alternativa, el simulador incluido |
| Sistema operativo | Se recomienda Windows 10/11 (soporte BLE de MATLAB) |

No se usan otros toolboxes ni archivos Python, C++ o MEX.

## Instalación

1. Copie o clone la carpeta `proyecto_protesis/`.
2. Abra MATLAB R2023b+ y haga `cd` a `proyecto_protesis/`.
3. Ejecute:

   ```matlab
   setup
   ```

   `setup` verifica la versión de MATLAB y los toolboxes y crea `logs/`. Añade las carpetas del
   proyecto al path y genera los `config/*.mat` que falten. Después ejecuta las pruebas sin
   red y las de conexión. Las de conexión pueden fallar si LM Studio o la prótesis aún no
   están encendidos; es lo esperado.
4. Apunte la configuración a su red:

   ```matlab
   create_server_llm_config('ip', '192.168.1.100');          % LM Studio
   create_server_prosthesis_config('ip', '192.168.1.101');   % prótesis
   ```

5. Compruebe las conexiones:

   ```matlab
   test_llm_connection
   test_prosthesis_connection
   ```

6. Calibre al usuario (vea [Calibración del usuario](#calibración-del-usuario)):

   ```matlab
   calibrate('Source', 'myo', 'UserId', 'daniel')
   ```

> Los `.mat` son binarios. No los edite a mano. Regenérelos con las funciones
> `create_*_config`, que aceptan pares nombre-valor.

## Uso rápido

```matlab
setup                                        % una vez
main('Source', 'simulated', 'Duration', 30)  % sin hardware: Myo simulado
main                                         % Myo real por BLE
main_debug                                   % mismo bucle + panel en vivo
```

Opciones útiles de `main`: `'Source'` (`'myo'|'udp'|'simulated'`), `'MyoDevice'`,
`'Period'` (0.2 s), `'Duration'`, `'MaxCycles'`, `'Verbose'`.

Para probar todo **sin hardware ni red**, genere una configuración con la prótesis simulada y
ejecute las pruebas sin red:

```matlab
create_server_prosthesis_config('protocol', 'SIM');
test_payload; test_parallel_ports; test_full_pipeline;
```

Detenga el bucle con **Ctrl+C** o cerrando la ventana de `main_debug`. En ambos casos `main`
envía el comando seguro `#R` (reposo) y libera el Myo.

## Estructura de directorios

```
proyecto_protesis/
├── README.md / README.es.md     Documentación general
├── CHANGELOG.md, LICENSE, .gitignore
├── setup.m                      Configuración inicial
├── main.m                       Bucle principal
├── main_debug.m                 Bucle principal + panel visual
├── config/                      Generadores de los archivos .mat de configuración
├── prompts/                     System prompt (ES/EN), ejemplos few-shot, plantilla de calibración
├── acquisition/                 Interfaz Myo (BLE/UDP/simulado), lectura de ventanas, calibración
├── processing/                  Filtrado, RMS/MAV, rechazo de ruido, imagen, payload
├── llm/                         Abstracción de puertos, cuerpo JSON, parser, validador, log
├── prosthesis/                  Envío HTTP y simulador local
├── utils/                       LDA, suavizado, mapas, Base64, logger
├── tests/                       Pruebas independientes (cada una devuelve true/false)
├── docs/                        Arquitectura, protocolo, calibración, solución de problemas
└── logs/                        (generado) logs de sesión y llm_*.jsonl
```

Cada carpeta tiene su `README.md` / `README.es.md`.

> **Nombres de archivo:** la especificación pedía nombres con guiones (`get-signals.m`).
> MATLAB no puede llamarlos: `get-signals(x)` se interpreta como `get - signals(x)`. Por eso
> todos los archivos de función usan guion bajo (`get_signals.m`, `process_signals.m`,
> `send_input_llm.m`, …). Los archivos de datos conservan el guion (`server-llm.mat`).

## Flujo del agente

```
          ┌──────────────┐   BLE / UDP / sim   ┌──────────────────────────┐
          │  Myo Armband │ ──────────────────▶ │ myo_interface            │
          └──────────────┘   200 Hz x 8 can.   │ (buffer circular, 5 s)   │
                                               └────────────┬─────────────┘
 cada ciclo (objetivo 200 ms)                                │ get_signals(200) → 40x8
 ┌───────────────────────────────────────────────────────────▼──────────────────────────┐
 │ 1 process_signals   Butterworth 20-95 Hz + notch 60 Hz → RMS/MAV → normalizar        │
 │ 2 filter_noise      saturación / canal plano / artefacto de movimiento → NOISE       │
 │ 3 build_payload     RMS:[..]|MAV:[..]|STATE:..|CALIB:[..]|PREV:..|T:..               │
 │ 4 generate_heatmap  PNG 640x480, barras turbo, umbrales 0.15 / 0.40                  │
 │ 5 send_input_llm    SIEMPRE ────HTTP────▶ LM Studio :1234 [:1235 :1236 :1237]        │
 │ 6 parsear + validar JSON → is_valid_response                                         │
 │ 7   └─ ¿falló? ───▶ fallback LDA (reglas reposo/ruido/gestos + LDA de 16 rasgos)     │
 │ 8 smooth_command    voto mayoritario K=3 + EMA del valor (+ vía rápida, #R seguro)   │
 │ 9 send_signals_prosthesis ──HTTP POST /api/command──▶ prótesis (o SIM)               │
 │10 llm_logger + espera al siguiente ciclo                                             │
 └──────────────────────────────────────────────────────────────────────────────────────┘
```

Todos los detalles están en [docs/architecture.es.md](docs/architecture.es.md).

## Configuración de LM Studio

1. En LM Studio, descargue y cargue **Qwen2.5-VL-7B-Instruct** (se necesita un modelo con
   visión).
2. Abra **Developer → Local Server**, inicie el servidor en el puerto `1234` y active **Serve
   on Local Network**. Permita el puerto en el firewall.
3. Recomendado: contexto de al menos 8k tokens (el system prompt ocupa ~3k tokens más ~400 de
   la imagen), descarga máxima a GPU y mantener el modelo cargado (sin descarga automática).
4. En MATLAB:

   ```matlab
   create_server_llm_config('ip', '<IP de LM Studio>');                      % N = 1
   create_server_llm_config('ip', '<IP>', 'ports', [1234 1235 1236 1237], ...
                            'mode', 'round-robin');                          % N = 4
   ```

   N = 4 significa cuatro servidores o instancias de LM Studio, una por puerto. Con
   `'models', {'m1','m2','m3','m4'}` puede usar un modelo por puerto. Con `'ips', {...}`
   cada puerto puede estar en una máquina distinta.

Campos principales de `server_llm`:

| Campo | Defecto | Significado |
|---|---|---|
| `ip` | `192.168.1.100` | Host de LM Studio |
| `ports` | `1234` | Array de puertos (N = numel) |
| `models` | `{'qwen2.5-vl-7b-instruct'}` | Un modelo compartido o uno por puerto |
| `mode` | `sequential` | `sequential`, `round-robin` o `parallel` (experimental, `backgroundPool`) |
| `timeout` | `0.5` s | Presupuesto de tiempo del LLM por ciclo |
| `temperature` / `top_p` | `0` / `1` | Salida determinista |
| `max_tokens` | `200` | Tokens de salida |
| `stop` | `}\n`, `}\r\n`, `\n\n` | Secuencias de parada (con saltos de línea reales) |
| `use_json_schema` | `false` | Envía `response_format` con un JSON Schema |
| `transport` | `http` | `mock` = clasificador determinista sin red (pruebas) |

> ⚠️ **Latencia:** un modelo de visión de 7B rara vez responde en menos de 500 ms en GPU de
> consumo, porque tiene que codificar la imagen en cada llamada. Ejecute
> `test_llm_connection` para medir la latencia en caliente. Después suba `timeout`
> (`create_server_llm_config('timeout', 1.5)`) o use una imagen más pequeña y rápida
> (`create_prompt_llm_config('render_mode','raster','image_width',320,'image_height',240)`).
> Si el LLM no responde a tiempo, el fallback LDA decide ese ciclo y el LLM se vuelve a
> llamar en el siguiente.

## Configuración de la prótesis

```matlab
create_server_prosthesis_config('ip', '192.168.1.101', 'port', 8080);   % HTTP real
create_server_prosthesis_config('protocol', 'SIM');                     % simulador en proceso
```

La prótesis recibe `POST http://<ip>:<puerto>/api/command`:

```json
{"command":"B","finger":"D2","action":"flex","value":95,"confidence":0.92,
 "trigger_channels":[4,7],"source":"llm","cycle":42,"timestamp":"2026-09-16T11:20:00.123"}
```

Debe responder con HTTP 2xx. La tabla de comandos (dedos A–F, gestos `#X`) y el protocolo
completo están en [docs/protocol.es.md](docs/protocol.es.md). Para emular la prótesis por
HTTP, abra una **segunda sesión de MATLAB** y ejecute
`prosthesis_simulator('start_server', 8080)` y `prosthesis_simulator('plot')`.

## Calibración del usuario

```matlab
calib = calibrate('Source', 'myo', 'UserId', 'daniel', 'Reps', 5);
```

El protocolo es:

1. 5 s en reposo.
2. Para pulgar, índice, medio, anular y meñique: 5 flexiones de 3 s cada una.
3. Puño con fuerza máxima.
4. Apertura de la mano con fuerza máxima.

Después, `calibrate` calcula los niveles de reposo y MVC de cada canal, el perfil medio de
cada dedo y los 2 canales dominantes de cada dedo. Esos canales viajan al LLM en `CALIB`.
También entrena y valida el LDA y guarda `config/calibration.mat`. `setup` crea una
**calibración genérica** (`is_default = true`) para que el sistema pueda arrancar de
inmediato. Reemplácela por la suya antes del uso real. Guía paso a paso:
[docs/calibration_guide.es.md](docs/calibration_guide.es.md).

## Solución de problemas

| Síntoma | Causa probable / solución |
|---|---|
| Todos los ciclos muestran `LDA` | Timeout del LLM. Mídalo con `test_llm_connection` y suba `timeout` o use la imagen `raster` |
| `ble` no encuentra el Myo | Cierre Myo Connect, empareje el brazalete en Windows, pruebe `'MyoDevice'` con la dirección BLE |
| `STATE:NOISE` constante | Brazalete flojo o mojado, `PowerlineHz` incorrecto (60 Hz en Ecuador/América, 50 Hz en Europa) |
| Dedo equivocado | Recalibre. Revise que `CALIB` muestre los canales esperados. Revise la rotación del brazalete |
| Prótesis `FAIL` | IP/puerto, firewall, el endpoint debe devolver 2xx dentro de `timeout` |

Más en [docs/troubleshooting.es.md](docs/troubleshooting.es.md).

## Notas de diseño y supuestos

- La especificación original hacía referencia a un "documento anterior" (secciones 1, 2.1
  y 4) que no estaba disponible. Por eso el system prompt, el mapa de canales, la tabla A–F y
  las reglas de gestos se diseñaron a partir de los requisitos. El código los refleja
  exactamente: `is_composite_gesture.m` y `rms_to_value.m` implementan las mismas reglas, y
  `test_payload` comprueba que cada ejemplo del prompt coincide con el código.
- El mapa de canales es una **colocación de referencia**. La calibración de cada usuario
  (`CALIB`) tiene prioridad sobre él.
- Cada decisión de diseño está documentada en el código como
  `% DECISIÓN: … | RAZÓN: … | ALTERNATIVA DESCARTADA: …` (más su línea en inglés).

## Licencia

MIT. Vea [LICENSE](LICENSE).

## Contacto

Autor: Anderson — andersoncango09@gmail.com
Incidencias y sugerencias: abra un issue en el repositorio o escriba a la dirección anterior.

> ⚠️ Esto es un prototipo de investigación. No es un dispositivo médico certificado. Pruebe
> siempre con la prótesis sin carga y con una parada de emergencia a mano.
