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
main              % Myo; si no está activo, usa las muestras
main('samples')   % directamente las muestras de samples/
```

**Ctrl+C** detiene el agente; al salir siempre se envía `#R` (reposo) a la prótesis.
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
main.m                         bucle principal
config/agent_config.m          TODA la configuración
config/system_es.txt / _en     system prompt del LLM
acquisition/myo_interface.m    Myo por Bluetooth o muestras grabadas
processing/process_signals.m   filtro 20-95 Hz + notch, RMS, MAV, estado, ruido
processing/build_payload.m     texto que recibe el LLM
processing/generate_image.m    gráfico de barras que recibe el LLM
llm/send_input_llm.m           petición HTTP al LLM
llm/parse_llm_response.m       extrae el JSON de la respuesta
llm/validate_command.m         comprueba que el comando es coherente
prosthesis/send_prosthesis_command.m   POST a la prótesis
utils/command_info.m           tabla de comandos (dedos y gestos)
utils/fallback_command.m       decisión local si el LLM falla
utils/smooth_command.m         evita cambios bruscos entre ciclos
utils/log_msg.m                línea de consola con hora
samples/muestra_N.csv          grabaciones: cabecera CH0..CH7, una fila por muestra
```

## Sin calibración

Cada canal se normaliza a [0, 1] con dos valores fijos de `agent_config.m`:
`cfg.signal.rest_rms` (reposo) y `cfg.signal.max_rms` (contracción máxima). Si con su
brazalete los valores quedan siempre bajos o siempre saturados, ajuste esos dos vectores.

## Comandos

`A`–`E` = pulgar, índice, medio, anular, meñique (grados) · `F` = muñeca ·
gestos `#O #C #P #R #W #Y #L #M #H #U #G` (% de fuerza). La tabla está en
`utils/command_info.m`.
