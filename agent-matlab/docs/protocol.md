# Communication protocol

> Español: [protocol.es.md](protocol.es.md)

## 1. MATLAB → LM Studio

**Request:** `POST http://<ip>:<port>/v1/chat/completions`
Headers: `Content-Type: application/json`, `Authorization: Bearer lm-studio`

```json
{
  "model": "qwen2.5-vl-7b-instruct",
  "messages": [
    {"role": "system", "content": "<system_es.txt + user calibration>"},
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

With `use_json_schema = true`, the request also carries
`"response_format": {"type": "json_schema", "json_schema": {"name": "prosthesis_command",
"strict": true, "schema": {...}}}`.

With `use_few_shot_messages = true`, the 10 examples are inserted as `user`/`assistant`
pairs between `system` and the final `user` message.

**Response (the part MATLAB uses):**

```json
{"choices": [{"message": {"role": "assistant",
  "content": "{\"command\":\"B\",\"finger\":\"D2\",\"action\":\"flex\",\"confidence\":0.92,\"trigger_channels\":[4,7],\"value\":95"}}]}
```

The final `}` may be missing because the `}\n` stop sequence removes it.
`parse_llm_response` adds it back.

### Payload fields

| Field | Format | Description |
|---|---|---|
| `RMS` | `[8 × 0.00-1.00]` | Normalized RMS per channel |
| `MAV` | `[8 × 0.00-1.00]` | Normalized MAV per channel |
| `STATE` | `REST`, `TRANSITION`, `ACTIVE`, `NOISE` | 0.15 / 0.40 thresholds on the maximum channel; `NOISE` from `filter_noise` |
| `CALIB` | `[D1=a+b,…,D5=a+b(,DEFAULT)]` or `[NONE]` | The user's dominant channels |
| `PREV` | `<cmd>:<3 digits>` or `NONE` | Last command sent |
| `T` | integer ms | Time since the session started |

### Command response

| Field | Type | Allowed values |
|---|---|---|
| `command` | string | `A B C D E F #O #C #P #R #W #Y #L #M #H #U #G` |
| `finger` | string | `D1 D2 D3 D4 D5 WRIST MULTI NONE` (must match the command) |
| `action` | string | A–E: `flex extend hold` · F: `rotate hold` · gestures: `gesture hold` · #R: `rest hold` |
| `confidence` | number | 0–1 |
| `trigger_channels` | integer[] | unique values in 1–8; empty only with `rest`/`hold` |
| `value` | integer | A 0–90 · B–E 0–120 · F 0–180 · gestures 0–100 · #R 0 |

### Command table

| Command | Meaning |
|---|---|
| `A` / `B` / `C` / `D` / `E` | Thumb / index / middle / ring / little finger (angle) |
| `F` | Wrist rotation (90 = neutral) |
| `#O` | Open hand |
| `#C` | Fist / power grip |
| `#P` | Precision pinch |
| `#R` | Rest (neutral pose) — **safe command** |
| `#W` | Three fingers extended |
| `#Y` | Shaka |
| `#L` | L shape |
| `#M` | Mouse grip |
| `#H` | Hook |
| `#U` | Index + middle extended |
| `#G` | Point |

## 2. MATLAB → prosthesis

**Request:** `POST http://<ip>:<port>/api/command`, `Content-Type: application/json`

```json
{"command":"B","finger":"D2","action":"flex","value":95,"confidence":0.92,
 "trigger_channels":[4,7],"source":"llm","cycle":42,"timestamp":"2026-09-16T11:20:00.123"}
```

| Field | Notes |
|---|---|
| `source` | `llm` (primary), `lda` (fallback), `safety` (shutdown), `test` |
| `cycle` | Cycle number; `-1` = safe command sent on shutdown |
| `timestamp` | Local time `yyyy-MM-ddTHH:mm:ss.SSS` |

**Expected response:** any HTTP 2xx within `timeout`. The body is optional and is logged if
it is JSON, e.g. `{"status":"ok","angles":[20,95,20,20,20,90]}`.

**Recommendations for the firmware (ESP32 or similar):**

- Treat commands as **absolute** (idempotent). Repeating the same command must not move the
  hand any further.
- Use a **watchdog**: if nothing arrives for more than 2 s, go to `#R`.
- Clip `value` to each servo's mechanical limits.
- For gestures, `value` is a strength percentage. The included simulator applies
  `angle = preset × (0.4 + 0.6 · value/100)`.

## 3. Myo Armband → MATLAB (BLE)

| Item | UUID / value |
|---|---|
| Control service | `D5060001-A904-DEB9-4748-2C7F4A124842` |
| Command characteristic | `D5060401-A904-DEB9-4748-2C7F4A124842` |
| EMG service | `D5060005-A904-DEB9-4748-2C7F4A124842` |
| EMG characteristics (notify) | `D5060105-…`, `D5060205-…`, `D5060305-…`, `D5060405-…` |
| Packet | 16 bytes = 2 samples × 8 `int8` channels |
| Set mode | `[0x01, 0x03, emg_mode, 0x00, 0x00]` (`emg_mode` 2 = filtered, 3 = raw) |
| Never sleep | `[0x09, 0x01, 0x01]` |
| Unlock hold | `[0x0A, 0x01, 0x02]` |
| Vibrate | `[0x03, 0x01, 1/2/3]` |

## 4. UDP source (optional)

Datagrams sent to `udp_port` (10001) whose length is a multiple of 8 bytes. Each block of 8
`int8` bytes is one sample (CH1..CH8). The 16-byte BLE packet can be forwarded unchanged.

## 5. Test HTTP server (simulator)

| Route | Method | Response |
|---|---|---|
| `/api/command` | POST | `{"status":"ok","angles":[...],"command":"B","commands":N}` |
| `/api/status` | GET | same, without applying a command |
| other | any | 404 |
