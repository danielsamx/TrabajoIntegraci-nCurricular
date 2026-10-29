# Control de prótesis de mano con sEMG + LLM (MATLAB)

> English: [README.md](README.md)

Lee 8 canales de EMG de un **Myo Armband**, envía cada ventana de 200 ms (texto + imagen) a
un **LLM en LM Studio**, y manda el comando resultante a la **prótesis** por HTTP, puerto serie o Bluetooth.
La única fuente es el Myo. No hay umbrales ni calibración.
 Todo lo que ocurre se imprime en la consola.

## Requisitos

- MATLAB R2023b o superior. No necesita toolboxes: el filtro Butterworth y el filtrado sin
  desfase están implementados en `processing/bandpass_sos.m` y `utils/zero_phase.m`.
- LM Studio con un modelo de visión cargado y el servidor activo en la red.
- Servidor de la prótesis que acepte `POST /api/command` con `{"command": "B"}`.

## Uso

1. Abra MATLAB y vaya a la carpeta del proyecto.
2. Revise `config/agent_config.m` (IP del LLM, IP de la prótesis, etc.).
3. Ejecute en la Command Window:

```matlab
agent_ui          % interfaz gráfica (recomendado)
main              % sin interfaz (consola)
```

### Interfaz gráfica (`agent_ui`)

Colores: azul `#002A5C` (botones y texto), rojo `#EE2E24` (Detener y alertas), amarillo
`#FDBE57` solo como acento y blanco. Logo: `assets/logo-laboratorio-alan-turing.png`.

- **Cabecera:** logo, **Dashboard** / **Prompt** e **Iniciar** / **Detener** (solo uno activo).
- **Barra lateral:** ocupa todo el alto visible y reparte el espacio entre secciones (sin desplazamiento).
  - **Adquisición (Myo):** conexión del Myo (**Adaptador USB** o **Bluetooth del PC**), puerto
    del adaptador o nombre del Myo, ventana, periodo, ciclos, red eléctrica y **Probar Myo** (conecta, lee una ventana y muestra el resultado
    o el motivo del fallo).
  - **Servidor LLM:** IP, puertos, timeout… **Modelo** es una lista: **Cargar** hace
    `GET /v1/models` al servidor y la rellena con los modelos disponibles. **Probar conexión**.
  - **Prótesis:** comunicación **HTTP**, **Puerto serie** o **Bluetooth**. En HTTP: host, puerto
    y ruta. En serie: puerto (↻ actualiza la lista) y baudios. En Bluetooth: nombre del dispositivo
    (↻ busca los cercanos) y canal. Además timeout, fin de línea, comando de reposo, comando al
    detener y dos botones de prueba: **Probar: abrir (O)** y **Probar: cerrar (C)**.
  - **Guardar configuración** escribe los cambios en `config/agent_config.m`.
- **Dashboard:** indicadores (ciclo, acción, confianza, respuesta del LLM, latencia y duración), los 8 canales individuales (EMG crudo de los últimos 2 s), las 3
  imágenes (cada una indica si se envía al LLM y tiene un botón **PNG** para guardarla en
  `logs/`) la postura enviada (cierre de cada dedo) y el cierre por ciclo. La barra de estado muestra
  el motivo del LLM y la referencia por reglas.
- **Prompt:** casillas de las imágenes que se envían al LLM, plantilla editable del system
  prompt y prompt final.

### Imágenes para el LLM

| Imagen | Contenido | Por defecto |
|---|---|---|
| Matriz de características | una fila por canal con RMS, MAV, WL, ZC y SSC | se envía |
| Ondas normalizadas | señal filtrada del último segundo de cada canal / RMS máximo | se envía |
| Envolvente general | una sola curva: media de las envolventes de los 8 canales | no |

Se configuran en `cfg.image.send` (o con las casillas de la vista Prompt). El prompt describe
solo las imágenes marcadas mediante el marcador `{{IMAGENES}}`. Cada imagen añadida aumenta
el tiempo de respuesta del LLM.

### Conectar el Myo

Si el Myo no se puede leer, la sesión no arranca y la interfaz muestra el motivo. El Myo usa dos conexiones USB distintas:

1. **Cable de carga (micro-USB):** enciende y carga el brazalete. Una vez encendido,
   desconéctelo: mientras carga el Myo puede no transmitir.
2. **Adaptador USB inalámbrico (BLED112, la llave azul):** es la conexión inalámbrica con el
   brazalete. Windows lo ve como un puerto COM ("Bluegiga Bluetooth Low Energy").

Pasos:

1. Encienda el Myo con el cable de carga y desconéctelo.
2. Enchufe el adaptador inalámbrico.
3. **Cierre Myo Connect** (icono de la bandeja > Quit): solo un programa puede usar el adaptador.
4. En **Adquisición**: Conexión Myo = Adaptador USB, Puerto USB = `auto` (busca solo
   el adaptador entre los puertos libres) o el COM concreto.
5. Pulse **Probar Myo**: muestra las 8 señales o el motivo exacto del fallo (puerto ocupado por
   Myo Connect, adaptador no enchufado, Myo apagado o cargando, sin EMG…).

La opción **Bluetooth del PC** usa la función `ble` de MATLAB con el Bluetooth propio del equipo
(no con el adaptador). Necesita el Bluetooth del PC encendido, el nombre exacto del brazalete
(p. ej. `MYO.94`) y también Myo Connect cerrado.

### Prótesis por puerto serie o Bluetooth

Con `cfg.prosthesis.mode = 'serial'` se envía la letra del comando seguida del fin de línea
(`LF`, `CR` o `CR/LF`) por `cfg.prosthesis.serial_port` a `cfg.prosthesis.baud_rate` baudios.
El puerto se abre una vez y se cierra al terminar la sesión o al cerrar la interfaz.

Con `cfg.prosthesis.mode = 'bluetooth'` se usa Bluetooth clásico (SPP) con la función `bluetooth`
de MATLAB (R2020b+, sin toolboxes), como hace la app *Serial Bluetooth Terminal* del manual de la
mano Handi EPN V3. Nombre por defecto: `Handi_EPN_V3` (exacto, como aparece en Windows), canal `1`.

1. El PC necesita Bluetooth propio o un adaptador USB Bluetooth. El adaptador del Myo (BLED112)
   **no sirve**: solo hace Bluetooth Low Energy y además está ocupado con el Myo.
2. Encienda la mano y emparéjela en Configuración de Windows > Bluetooth ("Handi_EPN_V3").
   Desconéctela del móvil: el ESP32 acepta una sola conexión.
3. En la interfaz: Comunicación = Bluetooth, ↻ para buscarla y **Probar: abrir (O)** o **Probar: cerrar (C)**.

Al pulsar **Iniciar** se conecta antes del primer ciclo; si no puede, la sesión no arranca y se
explica el motivo. Alternativa equivalente: al emparejarla, Windows crea un puerto COM
("Puerto serie estándar a través de vínculo Bluetooth"); ese COM funciona con la opción Serie.

Según el manual, `S` **detiene los motores** (no mueve la mano), `O` abre y `C` cierra.

**Ctrl+C** detiene el agente; al salir siempre se envía el comando de reposo (`S`) a la prótesis.
La consola completa queda guardada en `logs/sesion_<fecha>.txt`.

## Cadena de procesamiento (se imprime en cada ciclo)

El modelo de visión **no está entrenado con EMG** (no se usa ChatEMG ni ningún modelo
preentrenado en biosignales). Por eso todo el procesamiento se hace antes, de forma explícita,
y el modelo recibe medidas ya calculadas e imágenes. La consola numera cada paso:

| Paso | Qué se hace | Resultado |
|---|---|---|
| PASO1 | Ventana de 200 ms del Myo | 40 × 8 muestras |
| PASO2 | Pasa-banda 20-90 Hz (Butterworth, sin desfase) + notch 60 Hz | señal filtrada |
| PASO3 | Rectificación de onda completa y características | RMS, MAV, WL, ZC, SSC por canal |
| PASO4 | Normalización con el reposo y el máximo del usuario | RMS en [0, 1] |
| PASO5 | Comparación con el perfil de cada gesto | `SIM` (forma), `DIST` (distancia) |
| PASO6 | Activación de cada gesto (RMS = suma de perfiles × activación, ≥ 0) | `ACT`, `CIERRE` |
| PASO7 | Postura de los 6 dedos para ese cierre y referencia por reglas | `POS`, referencia |
| PASO8 | Entrada al modelo: texto + imágenes marcadas | petición |
| PASO9 | Respuesta del modelo, validación y motivo (`reason`) | acción |
| PASO10 | Suavizado, envío y retroalimentación (`FB`) | comando a la prótesis |

La **referencia por reglas** aplica el mismo procedimiento del prompt sin LLM. Solo se imprime
(no se envía) para comprobar si el modelo de visión lo sigue; el resumen muestra cuántas
acciones coincidieron. Para reducir la salida, ponga en `false` las opciones `cfg.console.*`.

## Estructura

```
agent_ui.m                     interfaz gráfica
assets/                        logo de la interfaz
main.m                         bucle sin interfaz (consola)
add_project_paths.m            añade las carpetas al path
agent/agent_session.m          un ciclo completo del agente (lo usan main y agent_ui)
agent/build_system_prompt.m    completa los marcadores del prompt
config/agent_config.m          TODA la configuración
config/system_es.txt / _en     system prompt del LLM
acquisition/myo_interface.m    Myo (adaptador USB o Bluetooth del PC)
processing/process_signals.m   cadena completa: filtros, rectificación, características, SIM, DIST, ACT, CIERRE, POS
processing/bandpass_sos.m      diseño del Butterworth pasa-banda (sin toolboxes)
processing/build_payload.m     texto que recibe el LLM
processing/visual_data.m       datos de las 3 imágenes (características, ondas, envolvente)
processing/draw_emg_image.m    dibuja cada imagen (dashboard y LLM)
processing/generate_images.m   guarda como PNG las imágenes marcadas para el LLM
processing/image_kinds.m       nombres y descripciones de las 3 imágenes
llm/send_input_llm.m           petición HTTP al LLM
llm/parse_llm_response.m       extrae y valida el JSON de la respuesta
llm/list_llm_models.m          GET /v1/models: modelos del servidor (Cargar y comprobación al iniciar)
prosthesis/send_prosthesis_command.m   envío a la prótesis por HTTP, puerto serie o Bluetooth
utils/smooth_command.m         evita cambios bruscos (vota por tipo: S, C, O o POS)
utils/posture_string.m         cierre (0-1) -> 'A..B..C..D..E..F..'
utils/posture_values.m         'A..F..' -> 6 posiciones validadas
utils/log_msg.m                línea de consola con hora
utils/read_text.m, write_text.m   leer y guardar texto en UTF-8
utils/zero_phase.m             filtrado adelante y atrás (como filtfilt)
```

## Sin calibración

Cada canal se normaliza a [0, 1] con dos valores fijos de `agent_config.m`:
`cfg.signal.rest_rms` (reposo) y `cfg.signal.max_rms` (contracción máxima). Si con su
brazalete los valores quedan siempre bajos o siempre saturados, ajuste esos dos vectores.

## Acciones de la prótesis

Según el manual de la Handi EPN V3:

| Acción | Significado |
|---|---|
| `C` | cerrar la mano por completo |
| `O` | abrir la mano por completo |
| `S` | reposo: detiene los motores; la mano se queda como está |
| `A..B..C..D..E..F..` | posición de cada dedo, p. ej. `A240B240C300D240E80F70` |

Dedos y rangos (`cfg.fingers`, Anexo A del manual): A meñique 0-350, B anular 0-350,
C medio 0-440, D índice 0-350, E pulgar inferior 0-120, F pulgar superior 0-100.
Se supone 0 = dedo extendido y máximo = flexionado (`cfg.fingers.open_at_zero`). Las
posiciones se redondean a `cfg.fingers.step` (10). `C` sola es cerrar; `C` con número es el dedo medio.

Texto que recibe el LLM en cada ciclo:

```
RMS:[0.52,0.21,0.00,0.20,0.04,0.03,0.31,0.20]|SIM:[C=0.96,O=0.65]|DIST:[S=0.70,C=0.38,O=0.62]|ACT:[C=0.67,O=0.00]|CIERRE:0.67|POS:A240B240C300D240E80F70|PREV:S|FB:OK|T:1200
```

Respuesta esperada: `{"command":"A240B240C300D240E80F70","confidence":0.82,"reason":"cierre parcial 0.67, copio POS"}`.

## Cómo se decide

1. **Reposo:** `SIM` elige el gesto más parecido; si en `DIST` el reposo está más cerca que ese
   gesto, la acción es `S`.
2. **Cierre:** `ACT` dice cuánto de cada perfil contiene la ventana. `CIERRE` = (parte de cierre)
   × fuerza, de 0 a 1. `CIERRE` 1.00 → `C`; 0.00 → `O`; cualquier otro valor → la postura `POS`.
3. **Confianza:** 0.50 + diferencia entre las dos distancias del paso 1 (máximo 0.95). Si las
   imágenes contradicen el texto, el modelo baja la confianza a 0.50.
4. **Retroalimentación:** `FB` indica si el envío anterior llegó a la prótesis (OK, FALLO o NADA).

En las grabaciones de prueba (149 ventanas), con la referencia por reglas:

| Archivos | `S` | `C` | postura parcial | `O` |
|---|---|---|---|---|
| reposo (50) | 50 | 0 | 0 | 0 |
| puño (49) | 21 | 4 | 24 (cierre 50-99 %) | 0 |
| mano abierta (50) | 11 | 0 | 19 (cierre 1-17 %) | 20 |

Las ventanas débiles (inicio y final de cada gesto) salen como `S`: la mano se queda como está.
Por debajo de ~50 % del perfil de puño la ventana está más cerca del reposo, así que los cierres
parciales empiezan en ~50 %. Los perfiles de `cfg.gestures` definen qué es el 100 %.

Cada gesto se define en `cfg.gestures` (comando, nombre, canales clave, perfil RMS y `closure`:
1 = cierra, 0 = abre). Marcadores del prompt: `{{GESTOS}}`, `{{REPOSO}}`, `{{DEDOS}}`,
`{{FILTRO}}`, `{{IMAGENES}}` y `{{POS:x}}` (postura para un cierre x, usada en los ejemplos).

## Solo decide el LLM

- Al pulsar **Iniciar** (o al ejecutar `main`) se comprueba el servidor con `GET /v1/models`. Si no
  responde, o no tiene el modelo elegido, la sesión no arranca y se muestra el motivo.
- Si en un ciclo el LLM no responde o su respuesta no es válida, **no se envía nada** a la
  prótesis: mantiene el último comando. El dashboard muestra *SIN RESPUESTA* o *DESCARTADA*
  y el motivo; la consola lo imprime. No hay decisión local de respaldo.
