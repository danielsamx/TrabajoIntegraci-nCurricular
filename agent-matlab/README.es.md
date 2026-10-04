# Control de prótesis de mano con sEMG + LLM (MATLAB)

> English: [README.md](README.md)

Lee 8 canales de EMG de un **Myo Armband**, envía cada ventana de 200 ms (texto + imagen) a
un **LLM en LM Studio**, y manda el comando resultante a la **prótesis** por HTTP.
Si el Myo no está activo, se procesan las grabaciones `samples/muestra_1..15.csv`.
No hace falta calibrar. Todo lo que ocurre se imprime en la consola.

## Requisitos

- MATLAB R2023b o superior con **Signal Processing Toolbox** (`butter`, `zp2sos`, `filtfilt`).
- LM Studio con un modelo de visión cargado y el servidor activo en la red.
- Servidor de la prótesis que acepte `POST /api/command` con `{"command": "B"}`.

## Uso

1. Abra MATLAB y vaya a la carpeta del proyecto.
2. Revise `config/agent_config.m` (IP del LLM, IP de la prótesis, etc.).
3. Ejecute en la Command Window:

```matlab
agent_ui          % interfaz gráfica (recomendado)
main              % sin interfaz: Myo; si no está activo, usa las muestras
main('samples')   % sin interfaz: directamente las muestras de samples/
```

### Interfaz gráfica (`agent_ui`)

Colores: rojo `#EE2E24`, azul `#002A5C`, amarillo `#FDBE57` y blanco. El logo se lee de
`assets/logo-laboratorio-alan-turing.png`.

- **Cabecera:** logo, botones **Dashboard** / **Prompt** e **Iniciar** / **Detener**. Solo uno
  de los dos está activo: detenido, Iniciar se puede pulsar y Detener está apagado; en marcha,
  al revés.
- **Barra lateral:**
  - **Adquisición** (fuente, carpeta de muestras, ventana, periodo, umbrales).
  - **Servidor LLM**: **Probar conexión** (lista los modelos de LM Studio).
  - **Prótesis** (incluye el comando de reposo): **Probar conexión** (envía el reposo).
  - **Guardar configuración** escribe los cambios en `config/agent_config.m`.
- **Dashboard:** indicadores (ciclo, fuente, estado, quién decidió, comando enviado, latencia),
  los 8 canales por separado, la vista general con los 8 canales juntos (**Exportar PNG** la
  guarda en `logs/`), la imagen que recibe el LLM, el historial de comandos y el detalle del
  ciclo (payload, respuesta del LLM, validación, envío).
- **Prompt:** plantilla editable del system prompt (`system_es.txt` o `system_en.txt`) y el
  prompt final con los gestos insertados. La sesión usa el texto del editor; **Guardar** lo
  escribe en el archivo.

**Ctrl+C** detiene el agente; al salir siempre se envía el comando de reposo (`S`) a la prótesis.
La consola completa queda guardada en `logs/sesion_<fecha>.txt`.

## Qué se imprime en cada ciclo

1. Origen de la ventana (Myo, o archivo y filas de la muestra).
2. Las 40 × 8 muestras crudas y las filtradas.
3. RMS y MAV por canal, crudos y normalizados, y el estado (REST, TRANSITION, ACTIVE, NOISE).
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
acquisition/myo_interface.m    Myo por Bluetooth o muestras grabadas
processing/process_signals.m   filtro 20-95 Hz + notch, RMS, MAV, estado, ruido
processing/build_payload.m     texto que recibe el LLM
processing/generate_image.m    gráfico de barras que recibe el LLM
llm/send_input_llm.m           petición HTTP al LLM
llm/parse_llm_response.m       extrae y valida el JSON de la respuesta
prosthesis/send_prosthesis_command.m   POST a la prótesis
utils/fallback_command.m       decisión local si el LLM falla
utils/smooth_command.m         evita cambios bruscos entre ciclos
utils/log_msg.m                línea de consola con hora
utils/read_text.m, write_text.m   leer y guardar texto en UTF-8
samples/muestra_N.csv          grabaciones: cabecera CH0..CH7, una fila por muestra
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
| `S` | reposo (mano relajada, algo abierta) | todos los RMS < 0.15 |

Cada gesto se define en `cfg.gestures` de `agent_config.m` (comando, nombre, canales clave y
perfil RMS medio). Esos datos se insertan en el system prompt al arrancar (marcador
`{{GESTOS}}`; el comando de reposo va en `{{REPOSO}}`) y se usan para calcular la similitud `SIM` que recibe el LLM. Para añadir un
gesto, añada otra entrada en `cfg.gestures` con su perfil.

Texto que recibe el LLM en cada ciclo:

```
RMS:[0.89,0.61,0.13,0.53,0.31,0.11,0.72,0.62]|SIM:[C=0.99,O=0.72]|STATE:ACTIVE|PREV:S|T:1000
```

Respuesta esperada: `{"command":"C","confidence":0.90}`.
