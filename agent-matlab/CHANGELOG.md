# Changelog / Historial de cambios

All notable changes to this project are documented here.
Todos los cambios relevantes del proyecto se documentan aquí.

Format based on [Keep a Changelog](https://keepachangelog.com/) · Versioning:
[SemVer](https://semver.org/).

## [2.6.0] - 2026-10-23

### Removed / Eliminado
- Fuente de muestras grabadas (`samples/`): el Myo es la única fuente. La carpeta de datos se conserva.
- Todos los umbrales (`rest_threshold`, `active_threshold`, `saturation_level`, `feature_threshold`)
  y el estado REST/TRANSITION/ACTIVE/NOISE.

### Changed / Cambiado
- Decisión sin umbrales: `SIM` (coseno) elige el gesto y `DIST` (distancia al reposo frente a la
  distancia a ese gesto) decide si es reposo. El LLM recibe `RMS|SIM|DIST|PREV|T`.
- System prompts (es/en) y respaldo local reescritos con ese procedimiento (147/149 en las grabaciones).
- La barra lateral reparte todo el alto visible entre secciones, sin desplazamiento.
- Indicadores del dashboard: ciclo, comando, confianza, decisión, latencia y duración.

### Added / Añadido
- Botón **Cargar** junto a *Modelo*: `GET /v1/models` rellena la lista con los modelos del servidor LLM.

## [2.5.1] - 2026-10-23

### Fixed / Corregido
- Ya no se usa Signal Processing Toolbox: `butter`, `zp2sos` y `filtfilt` se sustituyen por
  `processing/bandpass_sos.m` y `utils/zero_phase.m` (misma respuesta en frecuencia). Evita el
  error 5006 de MATLAB al pedir la licencia del toolbox en el primer ciclo.
- La UI guarda en el registro el informe completo de cualquier error durante la ejecución.
- `myo_interface` cierra los puertos serie que MATLAB hubiera dejado abiertos antes de buscar el adaptador.

## [2.5.0] - 2026-10-23

### Added / Añadido
- Lectura del Myo por su adaptador USB inalámbrico (BLED112, protocolo BGAPI por puerto serie),
  sin Myo Connect. `cfg.myo.dongle_port = 'auto'` busca el adaptador entre los puertos libres.
- Botón "Probar Myo" y mensajes que explican por qué no se puede leer el Myo (puerto ocupado por
  Myo Connect, adaptador no enchufado, Myo apagado o cargando, sin EMG, corte durante la sesión).

### Changed / Cambiado
- La fuente (Myo o muestras) la elige el usuario; ya no se cambia sola a las muestras.

## [2.4.1] - 2026-10-16

### Changed / Cambiado
- Vuelven los 8 canales individuales al dashboard.
- Matriz de características con una fila por canal (columnas RMS, MAV, WL, ZC, SSC).
- Envolvente general: una sola curva, la media de las envolventes de los 8 canales.
- La ventana se abre maximizada para que la cabecera (Prompt, Iniciar, Detener) siempre se vea.

### Removed / Eliminado
- Mapa de calor y panel "Detalle del ciclo" (el detalle sigue en la consola).

## [2.4.0] - 2026-10-16

### Added / Añadido
- Cuatro imágenes para el LLM, cada una con su casilla en la vista Prompt (`cfg.image.send`):
  matriz de características (RMS, MAV, WL, ZC, SSC), ondas normalizadas, envolvente general y
  mapa de calor. Por defecto se envían las dos primeras. Las cuatro se ven en el dashboard.
- Prótesis por puerto serie (`cfg.prosthesis.mode = 'serial'`) con interruptor HTTP / Serial.
- Marcador `{{IMAGENES}}` en el prompt; características WL, ZC y SSC en la consola.

### Changed / Cambiado
- Barra lateral sin desplazamiento (filas compactas y campos en pareja); botones azules con
  letra blanca en negrita (Detener en rojo); amarillo solo como acento.

### Removed / Eliminado
- `processing/generate_image.m` (gráfico de barras), sustituido por las 4 imágenes.

## [2.3.1] - 2026-10-04

### Fixed / Corregido
- Indicadores del dashboard: el título y el valor ya no se superponen (acento amarillo arriba,
  título pequeño y valor grande debajo). Todas las piezas se colocan en celdas explícitas.
- Iniciar / Detener pasan a la cabecera (sustituyen al indicador de estado): solo uno está
  activo a la vez.

## [2.3.0] - 2026-10-04

### Changed / Cambiado
- `agent_ui` rediseñada: colores del laboratorio (rojo #EE2E24, azul #002A5C, amarillo
  #FDBE57, blanco), logo `assets/logo-laboratorio-alan-turing.png` en la cabecera, navegación
  Dashboard/Prompt en la cabecera, píldora de estado y tarjetas blancas.
- Cada botón está en su apartado: Iniciar/Detener en Adquisición, Probar conexión en Servidor
  LLM y en Prótesis, Exportar PNG en la vista general, Guardar configuración al final.
- Comando de reposo `S` (antes `R`, que la prótesis interpreta como SPIDERMAN).

## [2.2.0] - 2026-10-03

### Added / Añadido
- `agent_ui`: interfaz gráfica con barra lateral (adquisición, servidor LLM, prótesis),
  dashboard (indicadores, 8 canales, vista general exportable, imagen enviada al LLM,
  historial de comandos, detalle del ciclo) y pestaña de prompt (plantilla editable y prompt
  final). "Guardar configuración" escribe los cambios en `config/agent_config.m`.
- `agent/agent_session.m`: el ciclo del agente en una clase que usan `main` y `agent_ui`.
- Marcador `{{REPOSO}}` en el prompt para el comando de reposo configurable.

## [2.1.0] - 2026-10-01

### Changed / Cambiado
- Comandos sin '#': la prótesis recibe `C` (puño), `O` (mano abierta) y `R` (reposo, mano
  relajada algo abierta). Se quitan los comandos de dedos A-F y el resto de gestos.
- Gestos definidos en `cfg.gestures` con su perfil RMS medio medido en `samples/`. El system
  prompt se reescribió: corto, con un procedimiento paso a paso y ejemplos reales; los gestos se
  insertan en `{{GESTOS}}` al arrancar.
- El payload incluye `SIM` (similitud coseno con cada perfil) y deja de incluir MAV.
- La respuesta del LLM es solo `{"command":"C","confidence":0.90}`; `max_tokens` = 40.
- El respaldo elige el gesto más parecido (o R sin actividad), con el mismo procedimiento.

## [2.0.0] - 2026-09-30

### Changed / Cambiado
- Sin calibración: cada canal se normaliza con valores fijos de reposo y máximo en
  `config/agent_config.m`. Se eliminan `calibrate`, el LDA y `calibration.mat`.
- Toda la configuración (fuente, señal, LLM, prótesis, suavizado, consola) está en
  `config/agent_config.m`; el system prompt pasa a `config/system_es.txt` / `system_en.txt`.
  Ya no hay archivos `.mat` ni `setup`.
- Todo se imprime en consola en cada ciclo: muestras crudas y filtradas, RMS/MAV, estado,
  petición y respuesta completa del LLM, validación, comando, suavizado y respuesta de la
  prótesis. La consola se guarda en `logs/sesion_<fecha>.txt`.
- Las muestras se procesan completas y en orden (ventanas de 40 filas por archivo); la
  sesión termina al acabar `muestra_15` (`cfg.samples.loop = true` para repetir).
- Si el LLM falla decide `utils/fallback_command.m`, con las mismas reglas del prompt.
- Código reescrito y reducido, con un comentario corto por línea.

### Removed / Eliminado
- Fuentes UDP y simulada, `main_debug`, el logger JSONL, la plantilla de calibración, los
  ejemplos few-shot sueltos y `docs/` (la documentación vigente está en los README).
  La versión anterior queda en `respaldo_v1.3.1.zip`.

## [1.3.1] - 2026-09-27

### Fixed / Corregido
- The fallback to `samples/muestra_1..15` now also triggers when the Myo connects but sends
  no EMG within 3 s, or stops sending it for 3 s during the session.
  / El respaldo con las muestras también se activa si el Myo conecta pero no envía EMG en
  3 s, o deja de enviarlo 3 s durante la sesión (`connect_timeout`, `dropout_timeout`).

## [1.3.0] - 2026-09-27

### Changed / Cambiado
- The prosthesis now lives in two files: `prosthesis/prosthesis_config.m` (host, port,
  endpoint, method, timeout, safe command) and `prosthesis/send_prosthesis_command.m`, which
  performs `POST http://localhost:8000/api/command` with `{"command": "B"}`.
  / La prótesis queda en dos archivos: `prosthesis_config.m` con los datos del servidor y
  `send_prosthesis_command.m` con el envío.
- The body carries only the validated command, as the prosthesis server expects.
  / El cuerpo lleva solo el comando validado, como espera el servidor de la prótesis.

### Removed / Eliminado
- `tests/` folder. / Carpeta `tests/`.
- `prosthesis_simulator.m` and the `SIM` protocol, replaced by the user's own server.
  / `prosthesis_simulator.m` y el protocolo `SIM`, sustituidos por el servidor propio.
- `config/create_server_prosthesis_config.m` and `server-prosthesis.mat`: the prosthesis
  configuration is plain code now. / El `.mat` de la prótesis: su configuración es código.
- The `mock` transport and the experimental `parallel` mode in `send_input_llm.m`, along
  with the config-injection options in `main.m`; they only existed for the tests.
  / El transporte `mock`, el modo `parallel` y las configuraciones inyectables de `main.m`.

## [1.2.0] - 2026-09-27

### Added / Añadido
- New `samples` acquisition source: plays back `samples/muestra_1..15` (`.csv` or `.xlsx`,
  header `CH0..CH7`, one sample per row) at 200 Hz, in numeric order and looping.
  / Nueva fuente de adquisición `samples`: reproduce `samples/muestra_1..15` a 200 Hz, en
  orden numérico y en bucle.
- Automatic fallback: with `'Source', 'myo'`, if the armband does not connect the loop
  continues with the recorded samples, or with the synthetic generator when there are none.
  / Respaldo automático: con `'Source', 'myo'`, si el brazalete no conecta el bucle sigue
  con las muestras grabadas, o con el generador sintético si no hay ninguna.
- `'SamplesDir'` option in `main` and `calibrate`; the folder is otherwise located
  automatically. / Opción `'SamplesDir'` en `main` y `calibrate`; si no, la carpeta se
  busca sola.
- `test_full_pipeline` gains scenario C over the recorded samples (skipped when the folder
  is empty). / `test_full_pipeline` añade el escenario C sobre las muestras grabadas.

### Changed / Cambiado
- `test_parallel_ports` compares the command sequence, not the angle, because the angle
  depends on the noise of the simulated source. / `test_parallel_ports` compara la
  secuencia de comandos, no el ángulo, que depende del ruido de la señal simulada.

## [1.1.0] - 2026-09-27

### Changed / Cambiado
- Code comments are now Spanish only, shorter and focused on the why; console messages and
  log entries are also Spanish only. / Los comentarios del código son solo en español, más
  breves y centrados en el motivo; los mensajes de consola y los logs también.
- Clean-code pass over the 35 `.m` files: long functions split into small local functions
  with intention-revealing names (`main.m` now reads as prepare, run loop, run cycle,
  decide command; `send_input_llm.m` separates settings, sequential, parallel and mock),
  magic numbers turned into named constants, guard clauses instead of nesting, and a single
  helper per repeated operation. / Pasada de clean code sobre los 35 `.m`: funciones largas
  divididas en funciones locales pequeñas con nombres que explican su intención, números
  mágicos convertidos en constantes con nombre, cláusulas de guarda en vez de anidamiento y
  un único ayudante por operación repetida.
- Behaviour is unchanged: the same commands, the same port distribution and the same tests.
  / El comportamiento no cambia: mismos comandos, mismo reparto de puertos y mismas pruebas.

### Fixed / Corregido
- Removed indexing into function call results (`ver().Name`, `train_lda(...).cv_accuracy`,
  `myo_interface.instance().vibrate`), which MATLAB does not allow. / Eliminadas las
  indexaciones sobre el resultado de una llamada, que MATLAB no permite.
- `llm_logger` counts held commands from the `smoothing` field. / `llm_logger` cuenta los
  comandos mantenidos con el campo `smoothing`.

## [1.0.0] - 2026-09-16

### Added / Añadido
- Real-time loop `main.m` with a **mandatory LLM call on every cycle** (TEXT + IMAGE),
  validation, emergency LDA fallback, temporal smoothing and HTTP delivery to the prosthesis.
  / Bucle en tiempo real `main.m` con **invocación obligatoria del LLM en cada ciclo**
  (TEXTO + IMAGEN), validación, fallback LDA de emergencia, suavizado temporal y envío HTTP a
  la prótesis.
- `main_debug.m`: live dashboard (EMG, RMS, latencies, decision source, VLM image).
  / Panel en vivo (EMG, RMS, latencias, origen de la decisión, imagen del VLM).
- Port abstraction in `send_input_llm.m`: `sequential`, `round-robin`, experimental
  `parallel` (`backgroundPool`) and failover, all driven by `config/server-llm.mat` (N=1 ↔ N=4).
  / Abstracción de puertos en `send_input_llm.m`: `sequential`, `round-robin`, `parallel`
  experimental y failover; todo controlado por `config/server-llm.mat` (N=1 ↔ N=4).
- `myo_interface.m`: native BLE Myo protocol with MATLAB `ble()`, a UDP source, a simulated
  source and a circular buffer. / Protocolo BLE nativo del Myo con `ble()`, fuente UDP,
  fuente simulada y buffer circular.
- Per-user calibration (`calibrate.m`) with rest/MVC normalization, finger profiles, dominant
  channels (`CALIB`) and LDA cross-validation. / Calibración por usuario con normalización
  reposo/MVC, perfiles por dedo, canales dominantes (`CALIB`) y validación cruzada del LDA.
- Bilingual system prompts (`prompts/system_es.txt`, `prompts/system_en.txt`), 10 few-shot
  examples and a calibration template. / System prompts bilingües, 10 ejemplos few-shot y
  plantilla de calibración.
- Prosthesis simulator (in-process `SIM` and HTTP server over `tcpserver`).
  / Simulador de prótesis (`SIM` en proceso y servidor HTTP sobre `tcpserver`).
- Standalone tests: `test_payload`, `test_llm_connection`, `test_prosthesis_connection`,
  `test_full_pipeline`, `test_parallel_ports`. / Pruebas independientes.
- Bilingual documentation (README, per-module READMEs, `docs/`).
  / Documentación bilingüe.

### Notes / Notas
- Function files use underscores instead of the hyphens in the original spec, because MATLAB
  cannot call hyphenated function names. / Los archivos de función usan guion bajo en vez de
  guion porque MATLAB no puede llamar funciones con guiones.
