# Control de prótesis de mano con sEMG + LLM (MATLAB)

> English: [README.md](README.md)

Lee 8 canales de EMG de un **Myo Armband**, envía cada ventana de 200 ms (texto + imagen) a
un **LLM en LM Studio**, y manda el comando resultante a la **prótesis** por HTTP.
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
  - **Prótesis:** interruptor **HTTP / Serial**. En HTTP: host, puerto y ruta. En serie:
    puerto (lista con ↻ para actualizar), baudios y fin de línea. Además timeout, comando de
    reposo y comando al detener, y **Probar conexión**.
  - **Guardar configuración** escribe los cambios en `config/agent_config.m`.
- **Dashboard:** indicadores (ciclo, comando, confianza, decisión, latencia y duración), los 8 canales individuales (EMG crudo de los últimos 2 s), las 3
  imágenes (cada una indica si se envía al LLM y tiene un botón **PNG** para guardarla en
  `logs/`) y los comandos enviados.
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

### Prótesis por puerto serie

Con `cfg.prosthesis.mode = 'serial'` se envía la letra del comando seguida del fin de línea
(`LF`, `CR` o `CR/LF`) por `cfg.prosthesis.serial_port` a `cfg.prosthesis.baud_rate` baudios.
El puerto se abre una vez y se cierra al terminar la sesión o al cerrar la interfaz.

**Ctrl+C** detiene el agente; al salir siempre se envía el comando de reposo (`S`) a la prótesis.
La consola completa queda guardada en `logs/sesion_<fecha>.txt`.

## Qué se imprime en cada ciclo

1. Muestras recibidas del Myo.
2. Las 40 × 8 muestras crudas y las filtradas.
3. RMS y MAV por canal, crudos y normalizados, y la similitud y distancia a cada gesto y al reposo.
4. La petición al LLM (texto, imagen, puerto), la respuesta HTTP completa y el texto generado.
5. Si el comando es válido o por qué se descartó (en ese caso decide el respaldo local).
6. El comando decidido, el suavizado y el comando enviado.
7. El POST a la prótesis y su respuesta.

Para reducir la salida, ponga en `false` las opciones `cfg.console.*` de `agent_config.m`.

## Estructura

```
agent_ui.m                     interfaz gráfica
assets/                        logo de la interfaz
main.m                         bucle sin interfaz (consola)
add_project_paths.m            añade las carpetas al path
agent/agent_session.m          un ciclo completo del agente (lo usan main y agent_ui)
agent/build_system_prompt.m    inserta gestos y comando de reposo en el prompt
config/agent_config.m          TODA la configuración
config/system_es.txt / _en     system prompt del LLM
acquisition/myo_interface.m    Myo (adaptador USB o Bluetooth del PC)
processing/process_signals.m   filtro 20-95 Hz + notch, características, similitud y distancias
processing/bandpass_sos.m      diseño del Butterworth pasa-banda (sin toolboxes)
processing/build_payload.m     texto que recibe el LLM
processing/visual_data.m       datos de las 3 imágenes (características, ondas, envolvente)
processing/draw_emg_image.m    dibuja cada imagen (dashboard y LLM)
processing/generate_images.m   guarda como PNG las imágenes marcadas para el LLM
processing/image_kinds.m       nombres y descripciones de las 3 imágenes
llm/send_input_llm.m           petición HTTP al LLM
llm/parse_llm_response.m       extrae y valida el JSON de la respuesta
prosthesis/send_prosthesis_command.m   envío a la prótesis por HTTP o puerto serie
utils/fallback_command.m       decisión local si el LLM falla
utils/smooth_command.m         evita cambios bruscos entre ciclos
utils/log_msg.m                línea de consola con hora
utils/read_text.m, write_text.m   leer y guardar texto en UTF-8
utils/zero_phase.m             filtrado adelante y atrás (como filtfilt)
```

## Sin calibración

Cada canal se normaliza a [0, 1] con dos valores fijos de `agent_config.m`:
`cfg.signal.rest_rms` (reposo) y `cfg.signal.max_rms` (contracción máxima). Si con su
brazalete los valores quedan siempre bajos o siempre saturados, ajuste esos dos vectores.

## Comandos

La prótesis recibe solo letras, sin `#`:

| Comando | Gesto | Cómo se reconoce en las muestras |
|---|---|---|
| `C` | mano cerrada (puño) | CH7 alto y CH3 casi 0 |
| `O` | mano abierta | CH3 alto y CH7 casi 0 |
| `S` | reposo (mano relajada, algo abierta) | RMS más cerca de 0 que del gesto |

Cada gesto se define en `cfg.gestures` de `agent_config.m` (comando, nombre, canales clave y
perfil RMS medio). Esos datos se insertan en el system prompt al arrancar (marcador
`{{GESTOS}}`; el comando de reposo va en `{{REPOSO}}`) y se usan para calcular `SIM` y `DIST`. Para añadir un
gesto, añada otra entrada en `cfg.gestures` con su perfil.

Texto que recibe el LLM en cada ciclo:

```
RMS:[0.89,0.61,0.13,0.53,0.31,0.11,0.72,0.62]|SIM:[C=0.99,O=0.72]|DIST:[S=1.57,C=0.59,O=1.15]|PREV:S|T:1000
```

Respuesta esperada: `{"command":"C","confidence":0.90}`.

## Decisión sin umbrales

1. `SIM` (similitud coseno, forma del patrón) elige el gesto más parecido.
2. `DIST` compara la distancia al reposo (todos los canales en 0) con la distancia a ese gesto:
   si el reposo está más cerca, el comando es `S`; si no, el gesto.
3. La confianza crece con la diferencia entre esas dos distancias (0.50 a 0.95).

El LLM sigue este procedimiento (system prompt) y `utils/fallback_command.m` lo aplica en local
cuando el LLM no responde. Con las grabaciones de prueba acierta 147 de 149 ventanas.
