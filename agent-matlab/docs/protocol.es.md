# Protocolo de comunicación

> English: [protocol.md](protocol.md)

## 1. MATLAB → LM Studio

**Petición:** `POST http://<ip>:<puerto>/v1/chat/completions`
Cabeceras: `Content-Type: application/json`, `Authorization: Bearer lm-studio`

```json
{
  "model": "qwen2.5-vl-7b-instruct",
  "messages": [
    {"role": "system", "content": "<system_es.txt + calibración del usuario>"},
    {"role": "user", "content": [
      {"type": "text", "text": "RMS:[0.06,0.08,0.21,0.82,0.19,0.05,0.44,0.07]|MAV:[0.05,0.07,0.18,0.79,0.17,0.04,0.41,0.06]|STATE:ACTIVE|CALIB:[D1=5+6,D2=4+7,D3=3+7,D4=2+8,D5=1+8]|PREV:#R:000|T:10240"},
      {"type": "image_url", "image_url": {"url": "data:image/png;base64,iVBORw0KGgo..."}}
    ]}
  ],
  "temperature": 0,
  "top_p": 1,
  "max_tokens": 200,
  "stream": false,
  "stop": ["}\n", "}\r\n", "\n\n"]
}
```

Con `use_json_schema = true`, la petición lleva además
`"response_format": {"type": "json_schema", "json_schema": {"name": "prosthesis_command",
"strict": true, "schema": {...}}}`.

Con `use_few_shot_messages = true`, los 10 ejemplos se insertan como pares
`user`/`assistant` entre `system` y el mensaje `user` final.

**Respuesta (la parte que usa MATLAB):**

```json
{"choices": [{"message": {"role": "assistant",
  "content": "{\"command\":\"B\",\"finger\":\"D2\",\"action\":\"flex\",\"confidence\":0.92,\"trigger_channels\":[4,7],\"value\":95"}}]}
```

Puede faltar la `}` final, porque la secuencia de parada `}\n` la elimina.
`parse_llm_response` la vuelve a añadir.

### Campos del payload

| Campo | Formato | Descripción |
|---|---|---|
| `RMS` | `[8 × 0.00-1.00]` | RMS normalizado por canal |
| `MAV` | `[8 × 0.00-1.00]` | MAV normalizado por canal |
| `STATE` | `REST`, `TRANSITION`, `ACTIVE`, `NOISE` | Umbrales 0.15 / 0.40 sobre el canal máximo; `NOISE` lo marca `filter_noise` |
| `CALIB` | `[D1=a+b,…,D5=a+b(,DEFAULT)]` o `[NONE]` | Canales dominantes del usuario |
| `PREV` | `<cmd>:<3 dígitos>` o `NONE` | Último comando enviado |
| `T` | entero en ms | Tiempo desde el inicio de la sesión |

### Respuesta de comando

| Campo | Tipo | Valores permitidos |
|---|---|---|
| `command` | texto | `A B C D E F #O #C #P #R #W #Y #L #M #H #U #G` |
| `finger` | texto | `D1 D2 D3 D4 D5 WRIST MULTI NONE` (debe coincidir con el comando) |
| `action` | texto | A–E: `flex extend hold` · F: `rotate hold` · gestos: `gesture hold` · #R: `rest hold` |
| `confidence` | número | 0–1 |
| `trigger_channels` | enteros[] | valores únicos en 1–8; vacío solo con `rest`/`hold` |
| `value` | entero | A 0–90 · B–E 0–120 · F 0–180 · gestos 0–100 · #R 0 |

### Tabla de comandos

| Comando | Significado |
|---|---|
| `A` / `B` / `C` / `D` / `E` | Pulgar / índice / medio / anular / meñique (ángulo) |
| `F` | Rotación de muñeca (90 = neutro) |
| `#O` | Mano abierta |
| `#C` | Puño / agarre de fuerza |
| `#P` | Pinza fina |
| `#R` | Reposo (postura neutra) — **comando seguro** |
| `#W` | Tres dedos extendidos |
| `#Y` | Shaka |
| `#L` | Forma de L |
| `#M` | Agarre de ratón |
| `#H` | Gancho |
| `#U` | Índice + medio extendidos |
| `#G` | Señalar |

## 2. MATLAB → prótesis

**Petición:** `POST http://<ip>:<puerto>/api/command`, `Content-Type: application/json`

```json
{"command":"B","finger":"D2","action":"flex","value":95,"confidence":0.92,
 "trigger_channels":[4,7],"source":"llm","cycle":42,"timestamp":"2026-09-16T11:20:00.123"}
```

| Campo | Notas |
|---|---|
| `source` | `llm` (principal), `lda` (respaldo), `safety` (cierre), `test` |
| `cycle` | Número de ciclo; `-1` = comando seguro enviado al cerrar |
| `timestamp` | Hora local `yyyy-MM-ddTHH:mm:ss.SSS` |

**Respuesta esperada:** cualquier HTTP 2xx dentro de `timeout`. El cuerpo es opcional y se
registra si es JSON, p. ej. `{"status":"ok","angles":[20,95,20,20,20,90]}`.

**Recomendaciones para el firmware (ESP32 o similar):**

- Trate los comandos como **absolutos** (idempotentes). Repetir el mismo comando no debe
  mover más la mano.
- Use un **watchdog**: si no llega nada durante más de 2 s, pase a `#R`.
- Recorte `value` a los límites mecánicos de cada servo.
- En los gestos, `value` es un porcentaje de fuerza. El simulador incluido aplica
  `ángulo = preset × (0.4 + 0.6 · value/100)`.

## 3. Myo Armband → MATLAB (BLE)

| Elemento | UUID / valor |
|---|---|
| Servicio de control | `D5060001-A904-DEB9-4748-2C7F4A124842` |
| Característica de comandos | `D5060401-A904-DEB9-4748-2C7F4A124842` |
| Servicio EMG | `D5060005-A904-DEB9-4748-2C7F4A124842` |
| Características EMG (notify) | `D5060105-…`, `D5060205-…`, `D5060305-…`, `D5060405-…` |
| Paquete | 16 bytes = 2 muestras × 8 canales `int8` |
| Fijar modo | `[0x01, 0x03, emg_mode, 0x00, 0x00]` (`emg_mode` 2 = filtrado, 3 = crudo) |
| No dormir | `[0x09, 0x01, 0x01]` |
| Desbloqueo | `[0x0A, 0x01, 0x02]` |
| Vibrar | `[0x03, 0x01, 1/2/3]` |

## 4. Fuente UDP (opcional)

Datagramas enviados a `udp_port` (10001) cuya longitud es múltiplo de 8 bytes. Cada bloque de
8 bytes `int8` es una muestra (CH1..CH8). El paquete BLE de 16 bytes se puede reenviar tal
cual.

## 5. Servidor HTTP de prueba (simulador)

| Ruta | Método | Respuesta |
|---|---|---|
| `/api/command` | POST | `{"status":"ok","angles":[...],"command":"B","commands":N}` |
| `/api/status` | GET | igual, sin aplicar ningún comando |
| otra | cualquiera | 404 |
