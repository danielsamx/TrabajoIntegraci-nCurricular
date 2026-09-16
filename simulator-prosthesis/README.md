# Simulador de mano protésica

**Español** · [English](README.en.md)

Un servidor que, al levantarlo, sirve una página con una mano protésica en 3D. Mientras corre, acepta comandos por HTTP y la mano se mueve en tiempo real según los recibe.

```
POST /api/command  {"command": "C"}          →  la mano se cierra en pantalla
POST /api/command  {"command": "A320,D180"}  →  meñique e índice a esas posiciones
```

Solo la mano: sin brazo, sin EMG, sin lógica de decisión. Lo que decide qué comando enviar vive fuera de este proyecto. El formato de la línea es el mismo que el del enlace SPP real, así que el mismo emisor sirve para ambos.

---

## Arranque rápido (Docker)

Requisito: Docker Desktop (Windows/macOS) o Docker Engine con Compose (Linux).

```bash
docker compose up --build -d
```

- Página: <http://localhost:8000>
- Documentación interactiva de la API (Swagger): <http://localhost:8000/docs>
- Parar: `docker compose down`
- Ver el estado del contenedor: `docker compose ps` (incluye *healthcheck*)

Prueba desde otra terminal:

```bash
# Linux / macOS / Git Bash
curl -X POST http://localhost:8000/api/command -H "Content-Type: application/json" -d '{"command":"C"}'
```

```powershell
# Windows PowerShell
Invoke-RestMethod -Method Post -Uri http://localhost:8000/api/command -ContentType "application/json" -Body '{"command":"C"}'
```

Pruebas automáticas (también en Docker):

```bash
docker compose --profile test run --rm tests
```

### Si ves la mano antigua (bloques azules)

Tras actualizar el proyecto, reconstruye el contenedor y fuerza la recarga una vez:

```bash
docker compose up --build -d
```

Luego, en el navegador, pulsa **Ctrl + F5** (o **Ctrl + Shift + R**; en macOS **Cmd + Shift + R**). Las versiones anteriores del servidor no le decían al navegador que revalidara el JS y el CSS, así que podía mezclar la página nueva con los scripts viejos. Desde esta versión todos los archivos se sirven con `Cache-Control: no-cache` y esto no debería repetirse.

### Configuración

Copia `.env.example` a `.env` si quieres cambiar algo.

| Variable | Por defecto | Qué hace |
|---|---|---|
| `SIM_PORT` | `8000` | Puerto de tu máquina donde se publica el simulador. |
| `SIM_ALLOWED_ORIGINS` | *(vacío)* | Orígenes de navegador **adicionales** con permiso, separados por comas (p. ej. `http://localhost:5173`). Vacío = solo la propia página. |

El estado vive en memoria. `docker compose restart` equivale a un ciclo de alimentación: la mano vuelve a abierto, perfil `TABLE_5_V3` y origen de fábrica.

---

## Usar la API desde otro programa u otra máquina

El servidor escucha en todas las interfaces del contenedor y Compose lo publica en el puerto `SIM_PORT` de tu máquina.

1. Averigua la IP de tu PC (`ipconfig` en Windows, `ip a` en Linux).
2. Desde el otro equipo: `http://<IP-de-tu-PC>:8000/api/command`.
3. En Windows, si no conecta, permite el puerto en el firewall (PowerShell como administrador):
   ```powershell
   New-NetFirewallRule -DisplayName "Simulador mano 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
   ```

**Clientes que no son navegadores** (Python, Node, C#, un microcontrolador, curl) funcionan sin configurar nada: no envían la cabecera `Origin`.

**Una página web servida desde otro origen** (p. ej. un panel en `http://localhost:5173`) necesita estar en `SIM_ALLOWED_ORIGINS`; si no, recibe `403 ORIGIN_NOT_ALLOWED`.

### Emisores de ejemplo (`examples/`)

| Archivo | Uso |
|---|---|
| `emitter.py` | Solo biblioteca estándar. Conexión *keep-alive*, respeta los 50 ms. `python examples/emitter.py "A320,D180"`, `--interactive`, `--demo`, `--url http://IP:8000` |
| `emitter.ps1` | PowerShell. `.\examples\emitter.ps1 C`, `-Interactive`, `-Url http://IP:8000` |
| `curl.sh` | Recorrido rápido con curl. `BASE=http://IP:8000 sh examples/curl.sh` |

Para tiempo real:

- Reutiliza la conexión HTTP (*keep-alive*); no abras una nueva por comando.
- Envía como mucho un comando cada 50 ms. Si llegas antes recibes `422 timing/TOO_SOON` con `retry_after_ms`.
- No esperes a que termine un movimiento: un comando nuevo reorienta la mano desde donde esté.
- Lee las tablas desde `GET /api/spec` en vez de copiarlas.

---

## El protocolo de línea

```
A320,B120,E45     posiciones individuales, separadas por coma
P                 un gesto preestablecido
S                 parada de emergencia
```

- Mayúsculas; sensible a mayúsculas (`a320` no es válido). Sin espacios.
- Separador `,`. Terminador `\n` opcional por HTTP: si viene al final, se descarta (solo uno).
- Máximo 128 caracteres (sin contar el terminador) y 6 tokens de posición.
- Una letra no puede repetirse (`A320,A100` → error, no «gana el último»).
- `S`, `X` e `I` van siempre solas. **Decisión de este simulador:** un gesto también va solo (`P,A320` → error), porque mezclar un gesto con posiciones no tiene una semántica definida.

### La ambigüedad de la `C`

| Línea | Significado |
|---|---|
| `C` | Gesto **CLOSE**: cierra toda la mano. |
| `C400` | Actuador **C** (dedo medio) a la posición 400. |

Lo decide la presencia de sufijo numérico y nada más. `C,C400` es una letra repetida y se rechaza.

### Actuadores

| Letra | Dedo | Movimiento | Hardware |
|---|---|---|---|
| A | meñique (D5) | flexión/extensión | Pololu 380:1 + encóder magnético |
| B | anular (D4) | flexión/extensión | Pololu 380:1 + encóder magnético |
| C | medio (D3) | flexión/extensión | Pololu 380:1 + encóder magnético |
| D | índice (D2) | flexión/extensión | Pololu 380:1 + encóder magnético |
| E | pulgar inferior (D0) | rotación / oposición | servo MG90S |
| F | pulgar superior (D1) | flexión/extensión | Pololu 380:1 + encóder magnético |

### Perfiles de límites

| Letra | TABLE_5_V3 (defecto) | ANNEX_A_V3 | INTERSECTION |
|---|---|---|---|
| A | 0–600 | 0–350 | 0–350 |
| B | 0–550 | 0–350 | 0–350 |
| C | 0–600 | 0–440 | 0–440 |
| D | 0–550 | 0–350 | 0–350 |
| E | 0–130 | 0–120 | 0–120 |
| F | 0–400 | 0–100 | 0–100 |

0 = extendido, máximo = flexionado. Posición normalizada = `clamp((pos − min) / (max − min), 0, 1)`; es lo único que consume la escena.

### Gestos y comandos especiales

| Letra | Nombre | A | B | C | D | E | F | ms |
|---|---|---|---|---|---|---|---|---|
| O | OPEN | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 800 |
| C | CLOSE | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 900 |
| P | PINCH | 0.15 | 0.15 | 0.85 | 0.15 | 0.90 | 0.80 | 850 |
| R | SPIDERMAN | 0.00 | 1.00 | 1.00 | 0.00 | 0.00 | 0.00 | 900 |
| W | PARTIAL_CLAW | 0.00 | 1.00 | 0.00 | 1.00 | 0.00 | 0.00 | 900 |
| Y | OK | 0.10 | 0.10 | 0.10 | 0.85 | 0.85 | 0.75 | 900 |
| L | THUMBS_UP | 1.00 | 1.00 | 1.00 | 1.00 | 0.00 | 0.00 | 900 |
| M | CALL_ME | 0.00 | 1.00 | 1.00 | 1.00 | 0.00 | 0.00 | 900 |
| H | NUMBER_THREE | 1.00 | 0.00 | 0.00 | 0.00 | 1.00 | 1.00 | 900 |
| U | NUMBER_FOUR | 0.00 | 0.00 | 0.00 | 0.00 | 1.00 | 1.00 | 900 |
| G | POINT | 1.00 | 1.00 | 1.00 | 0.00 | 0.00 | 0.00 | 850 |

Un gesto se convierte a cuentas con el perfil activo (`round(n × max)`), como haría el firmware.

| Letra | Nombre | Qué hace |
|---|---|---|
| S | STOP | Congela el movimiento donde esté. **No** vuelve a abierto. Nunca se rechaza por cadencia. |
| X | CALIBRATE | Fija la pose actual como cero de los encóderes. No se mueve nada; el panel muestra «recalibrado» y el desplazamiento. |
| I | INIT_SHIELDS | Reinicializa los drivers. Se acepta y no se mueve nada. |

---

## API

### `POST /api/command`

```json
{ "command": "A320,D180" }
```

**Aceptado — 200**

```json
{
  "accepted": true,
  "frame": "A320,D180",
  "pose": {
    "actuator_positions":  { "A": 320, "D": 180 },
    "actuator_normalised": { "A": 0.5333, "D": 0.3273 },
    "duration_ms": 356
  }
}
```

Los gestos añaden `"gesture": {"letter", "name"}`. `S`, `X` e `I` añaden `"action"`; `X` añade además `"calibration_offset"`.

**Rechazado — 422** (la mano no se mueve)

```json
{
  "accepted": false,
  "stage": "range",
  "code": "OUT_OF_RANGE",
  "message": "A=900 is outside 0-600 for profile TABLE_5_V3."
}
```

#### Etapas de validación, en orden

| Etapa | Código | Cuándo |
|---|---|---|
| `protocol` | `EMPTY_COMMAND` | Línea vacía. |
| | `LINE_TOO_LONG` | Más de 128 caracteres. |
| | `EMPTY_TOKEN` | Coma sobrante o doble (`A1,,B2`, `A1,`). |
| | `MALFORMED_TOKEN` | No es «letra mayúscula + entero sin signo opcional» (`a320`, `A-5`, `A 3`). |
| | `UNKNOWN_LETTER` | Letra que no existe (`Z`, `Q10`). |
| | `UNEXPECTED_POSITION` | Gesto o especial con número (`P20`, `S1`). |
| | `MISSING_POSITION` | Actuador sin número (`A`, `D`). Excepción: `C` sola es el gesto CLOSE. |
| | `TOO_MANY_TOKENS` | Más de 6 posiciones. |
| | `DUPLICATE_LETTER` | Letra repetida (`A320,A100`, `C,C400`). |
| `exclusivity` | `EXCLUSIVE_COMMAND` | `S`, `X` o `I` acompañadas (`S,A320`). |
| | `GESTURE_NOT_ALONE` | Gesto acompañado (`P,A320`). |
| `range` | `OUT_OF_RANGE` | Posición fuera del perfil activo. **No se acota.** |
| `kinematics` | `BEYOND_MECHANICAL_TRAVEL` | Tras un `X` con la mano flexionada, encóder + desplazamiento cae fuera del recorrido. Con el origen de fábrica nunca ocurre. Aquí irá la colisión pulgar-índice. |
| | `CALIBRATE_WHILE_MOVING` | `X` con la mano en movimiento (envía `S` antes). |
| `timing` | `TOO_SOON` | Menos de 50 ms desde el último comando aceptado. Trae `retry_after_ms` y cabecera `Retry-After`. `S` está exenta. |

Errores de la petición (no de la línea), con `"stage": "request"`:

| HTTP | Código | Causa |
|---|---|---|
| 415 | `UNSUPPORTED_MEDIA_TYPE` | Falta `Content-Type: application/json`. |
| 400 | `INVALID_JSON` | El cuerpo no es JSON. |
| 413 | `BODY_TOO_LARGE` | Cuerpo de más de 4 KB. |
| 422 | `BAD_REQUEST` | Falta `command` o no es texto. |
| 403 | `ORIGIN_NOT_ALLOWED` | Petición de navegador desde un origen no permitido. |

### `GET /api/state`

Pose actual (cuentas de encóder y normalizadas, interpoladas al instante), destinos, perfil y límites activos, si hay movimiento (`moving`, `moving_actuators`), desplazamiento de calibración, actuadores fuera del perfil, último comando y trayectorias en curso. Sin histórico.

### `GET /api/spec`

Todas las tablas (actuadores, perfiles, 15 articulaciones, gestos, especiales, reglas de protocolo y de movimiento), servidas desde `app/spec.py`, el mismo sitio del que las lee el simulador y la escena.

### `POST /api/profile`

```json
{ "profile": "INTERSECTION" }
```

Valores: `TABLE_5_V3`, `ANNEX_A_V3`, `INTERSECTION`. No mueve la mano. Si la pose actual queda fuera del nuevo envolvente, lo dice en `out_of_envelope` y el panel lo marca en ámbar:

```json
{
  "profile": "INTERSECTION",
  "previous": "TABLE_5_V3",
  "moved": false,
  "out_of_envelope": [{ "actuator": "A", "position": 500, "target": 500, "limits": { "min": 0, "max": 350 } }],
  "message": "Profile changed to INTERSECTION. The hand did not move; actuator(s) A are now outside the INTERSECTION envelope."
}
```

### `WS /ws`

El servidor empuja; el navegador no pregunta. Al conectar llega un `snapshot` con el estado completo (y las trayectorias en curso, para continuar donde van). Después:

```json
{ "type": "pose", "target": { "A": 0.5333, "D": 0.3273 }, "target_counts": { "A": 320, "D": 180 }, "duration_ms": 356, "frame": "A320,D180" }
{ "type": "stop", "pose": { "A": 0.41, "...": 0 }, "counts": { "A": 246, "...": 0 } }
{ "type": "calibrated", "offset": { "A": 300, "...": 0 }, "counts": { "A": 0, "...": 0 } }
{ "type": "profile", "profile": "INTERSECTION", "out_of_envelope": [] }
{ "type": "command", "frame": "A900", "accepted": false, "stage": "range", "code": "OUT_OF_RANGE", "message": "..." }
```

`target` solo incluye los actuadores que cambian; los demás siguen su trayectoria.

---

## Movimiento

- Nada se teletransporta: cada comando es un movimiento con duración.
- Posiciones: `duración = clamp(max|Δcuentas| / 900 × 1000, 120, 5000)` ms, con Δ medido desde la posición **actual** (interpolada).
- Gestos: la duración de su tabla.
- Se interpola en el espacio normalizado de cada actuador con `easeInOutCubic`; los ángulos de las 15 articulaciones se derivan de ahí: `ángulo = min + clamp(n × acoplamiento, 0, 1) × (max − min)`.
- Un comando nuevo reorienta desde donde esté. No hay cola.
- El servidor manda destinos, no fotogramas; el navegador interpola con `requestAnimationFrame`. El servidor calcula la misma curva para saber dónde está la mano (para `S`, reorientar y calcular duraciones).

### Calibración (`X`) en detalle

El simulador guarda cuentas «absolutas» desde el origen de fábrica. El encóder lee `absoluta − desplazamiento`. `X` hace `desplazamiento = absoluta actual`: el panel pasa a mostrar 0 y la mano no se mueve. Los comandos siguientes hablan en cuentas de encóder, como el firmware: si calibras con el meñique a 300 de 600, `A300` lo lleva al tope y `A301` se rechaza en `kinematics`. Para volver al origen de fábrica, reinicia el contenedor.

---

## La escena

La pantalla es solo la mano. Todo lo demás está plegado:

- **Arriba a la izquierda:** el nombre y un punto de conexión (marino = conectado, ámbar parpadeando = sin conexión). Mientras algo se mueve aparece una etiqueta rosa con las letras en curso.
- **Abajo, en el centro:** un aviso breve con cada comando (línea, gesto, duración). Se oculta solo a los 2,6 s; los rechazos se quedan 7 s con una barra ámbar y el botón del panel muestra un punto ámbar.
- **Botón arriba a la derecha** (o tecla <kbd>I</kbd>): abre y cierra el **panel de estado** con las seis posiciones (cuentas y normalizadas), el perfil, si hay movimiento, el origen de encóderes y el último comando con su veredicto y motivo. <kbd>Esc</kbd> lo cierra. El navegador recuerda si lo dejaste abierto. Con el panel abierto, la mano se desplaza hacia el espacio libre. En el móvil el panel sale desde abajo.
- **Ratón:** arrastrar para orbitar, rueda para acercar, doble clic para volver a la vista inicial. La cámara nunca se mueve sola.

### La mano

- Mano derecha realista vista por el dorso en tres cuartos, de pie sobre la muñeca, con sombra suave en el suelo.
- **Piel:** la malla se genera al cargar la página a partir de un campo de distancias (conos redondeados y elipsoides unidos con suavidad): palma con arco metacarpiano, eminencias tenar e hipotenar, membranas entre los dedos, nudillos, yemas y muñeca. Material físico con brillo tenue, dispersión aparente en los bordes, poros, pliegues de flexión en dedos, palma y muñeca, arrugas en los nudillos y oclusión ambiental.
- **Uñas** con lúnula y borde libre.
- **Luces:** iluminación de estudio (entorno de habitación) más una luz principal con sombra.
- **Articulaciones:** jerarquía mano → dedo → proximal → intermedia → distal. Cada falange rota en su articulación, y sus extremos son esferas centradas en ella, así que la piel no se abre al flexionar. D0 gira sobre **Y** (oposición); el pulgar tiene D1_P y D1_D, sin intermedia. La posición del pulgar se ajustó numéricamente para que las yemas se toquen en `Y` (OK, pulgar-índice) y en `P` (PINCH, pulgar-medio).
- **Colores de estado sobre la piel:** el dedo que se mueve se tiñe de rosa suave y el que queda fuera del perfil, de ámbar. Se desactiva con el interruptor del panel.

Parámetros de la URL:

| Parámetro | Efecto |
|---|---|
| `?view=palm` / `?view=side` | Vista inicial por la palma o de lado (por defecto, `back`: el dorso). |
| `?hand=left` | Mano izquierda (misma geometría con X invertida). |
| `?lang=en` | Interfaz en inglés. |
| `?quality=0.7` | Malla más ligera para equipos lentos (1 = normal). |

La página solo dibuja cuando algo cambia (cámara, pose o tinte); en reposo no gasta GPU. La malla tarda alrededor de 1 s en generarse.

Three.js 0.186 va incluido en `static/vendor/three` (licencia MIT): la página funciona sin Internet. No se usan modelos, texturas ni fuentes externas.

> **Cambio respecto al encargo original.** A petición tuya, la mano ya no es marina ni sin sombras: es de color piel, con sombra suave en el suelo y un tramo corto de muñeca para que se vea natural (sigue sin haber brazo ni brazalete). La paleta fija se mantiene en toda la interfaz, y el rosa y el ámbar siguen marcando movimiento y avisos. Sigue sin haber modo oscuro.

---

## Restricciones que se cumplen a propósito

- Sin inicio de sesión, usuarios ni tokens.
- CORS cerrado: sin `*`. Además, un guardián de origen rechaza con 403 cualquier petición HTTP o WebSocket de navegador cuyo `Origin` no sea el que sirve la página (CORS por sí solo no impide que un POST de otro sitio llegue). Exigir `application/json` obliga a *preflight*.
- Sin almacenamiento: ni base de datos, ni ficheros, ni historial. El contenedor corre con sistema de ficheros de solo lectura.
- Sin trazabilidad: Uvicorn corre con `--no-access-log`; no se registran comandos.
- Sin lógica de decisión: se valida y se obedece o se rechaza. Nunca se corrige un comando.
- Un solo proceso (`--workers 1`): con varios habría varias manos.

> **Aviso:** no hay autenticación por diseño. No publiques el puerto en Internet; úsalo en tu máquina o en una red de confianza.

---

## Estructura

```
app/
  spec.py        tablas: única fuente de verdad (también servidas en /api/spec)
  protocol.py    parser de la línea: etapas protocol y exclusivity
  motion.py      estado, trayectorias, etapas range, kinematics y timing, S/X/I
  main.py        FastAPI: rutas, WebSocket, guardián de origen
static/
  index.html     una sola página
  js/app.js      WebSocket, escena, panel plegable y bucle de animación
  js/hand.js     anatomía, piel y uñas; jerarquía de articulaciones
  js/sdf.js      campos de distancia y mallado (surface nets)
  js/motion.js   interpolación por actuador (misma curva que motion.py)
  css/style.css  paleta fija
  vendor/three/  Three.js incluido
tests/           pytest (parser, API, movimiento, WebSocket, origen)
examples/        emisores en Python, PowerShell y curl
Dockerfile       etapas runtime y test (Python 3.13-slim, usuario sin privilegios)
compose.yaml     servicio simulator (+ tests con --profile test)
```

### Sin Docker (desarrollo)

```bash
python -m venv .venv && . .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8000 --no-access-log
python -m pytest
```
