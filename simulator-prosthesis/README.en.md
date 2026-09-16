# Prosthetic hand simulator

[Español](README.md) · **English**

A server that, once started, serves a page with a 3D prosthetic hand. While it runs, it accepts commands over HTTP and the hand moves in real time as they arrive.

```
POST /api/command  {"command": "C"}          →  the hand closes on screen
POST /api/command  {"command": "A320,D180"}  →  little and index fingers to those positions
```

Only the hand: no arm, no EMG, no decision logic. Whatever decides which command to send lives outside this project. The line format is the same as on the real SPP link, so the same emitter works for both.

---

## Quick start (Docker)

Requirement: Docker Desktop (Windows/macOS) or Docker Engine with Compose (Linux).

```bash
docker compose up --build -d
```

- Page: <http://localhost:8000>
- Interactive API docs (Swagger): <http://localhost:8000/docs>
- Stop: `docker compose down`
- Container status: `docker compose ps` (includes a healthcheck)

Try it from another terminal:

```bash
# Linux / macOS / Git Bash
curl -X POST http://localhost:8000/api/command -H "Content-Type: application/json" -d '{"command":"C"}'
```

```powershell
# Windows PowerShell
Invoke-RestMethod -Method Post -Uri http://localhost:8000/api/command -ContentType "application/json" -Body '{"command":"C"}'
```

Automated tests (also in Docker):

```bash
docker compose --profile test run --rm tests
```

### If you still see the old hand (navy blocks)

After updating the project, rebuild the container and force a reload once:

```bash
docker compose up --build -d
```

Then press **Ctrl + F5** in the browser (or **Ctrl + Shift + R**; **Cmd + Shift + R** on macOS). Earlier server versions did not tell the browser to revalidate JS and CSS, so it could mix the new page with stale scripts. Every file is now served with `Cache-Control: no-cache`, so this should not happen again.

### Configuration

Copy `.env.example` to `.env` to change anything.

| Variable | Default | What it does |
|---|---|---|
| `SIM_PORT` | `8000` | Port on your machine where the simulator is published. |
| `SIM_ALLOWED_ORIGINS` | *(empty)* | **Extra** browser origins allowed, comma-separated (e.g. `http://localhost:5173`). Empty = only the page itself. |

State lives in memory. `docker compose restart` is a power cycle: the hand returns to open, profile `TABLE_5_V3`, factory origin.

---

## Using the API from another program or machine

The server listens on all container interfaces and Compose publishes it on port `SIM_PORT` of your machine.

1. Find your PC's IP (`ipconfig` on Windows, `ip a` on Linux).
2. From the other machine: `http://<your-PC-IP>:8000/api/command`.
3. On Windows, if it does not connect, allow the port through the firewall (PowerShell as administrator):
   ```powershell
   New-NetFirewallRule -DisplayName "Hand simulator 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
   ```

**Non-browser clients** (Python, Node, C#, a microcontroller, curl) work with no configuration: they send no `Origin` header.

**A web page served from another origin** (e.g. a dashboard on `http://localhost:5173`) must be listed in `SIM_ALLOWED_ORIGINS`; otherwise it gets `403 ORIGIN_NOT_ALLOWED`.

### Example emitters (`examples/`)

| File | Usage |
|---|---|
| `emitter.py` | Standard library only. Keep-alive connection, respects the 50 ms interval. `python examples/emitter.py "A320,D180"`, `--interactive`, `--demo`, `--url http://IP:8000` |
| `emitter.ps1` | PowerShell. `.\examples\emitter.ps1 C`, `-Interactive`, `-Url http://IP:8000` |
| `curl.sh` | Quick tour with curl. `BASE=http://IP:8000 sh examples/curl.sh` |

For real time:

- Reuse the HTTP connection (keep-alive); do not open a new one per command.
- Send at most one command every 50 ms. Arrive earlier and you get `422 timing/TOO_SOON` with `retry_after_ms`.
- Do not wait for a motion to finish: a new command re-targets the hand from wherever it is.
- Read the tables from `GET /api/spec` instead of copying them.

---

## The line protocol

```
A320,B120,E45     individual positions, comma-separated
P                 a preset gesture
S                 emergency stop
```

- Uppercase; case-sensitive (`a320` is invalid). No spaces.
- Separator `,`. The `\n` terminator is optional over HTTP: if it is at the end, it is dropped (only one).
- At most 128 characters (terminator excluded) and 6 position tokens.
- A letter may not repeat (`A320,A100` → error, not "last one wins").
- `S`, `X` and `I` are always alone. **Decision taken by this simulator:** a gesture is alone too (`P,A320` → error), because mixing a gesture with positions has no defined meaning.

### The `C` ambiguity

| Line | Meaning |
|---|---|
| `C` | **CLOSE** gesture: closes the whole hand. |
| `C400` | Actuator **C** (middle finger) to position 400. |

The numeric suffix decides, and nothing else. `C,C400` is a repeated letter and is rejected.

### Actuators

| Letter | Finger | Motion | Hardware |
|---|---|---|---|
| A | little (D5) | flexion/extension | Pololu 380:1 + magnetic encoder |
| B | ring (D4) | flexion/extension | Pololu 380:1 + magnetic encoder |
| C | middle (D3) | flexion/extension | Pololu 380:1 + magnetic encoder |
| D | index (D2) | flexion/extension | Pololu 380:1 + magnetic encoder |
| E | lower thumb (D0) | rotation / opposition | MG90S servo |
| F | upper thumb (D1) | flexion/extension | Pololu 380:1 + magnetic encoder |

### Limit profiles

| Letter | TABLE_5_V3 (default) | ANNEX_A_V3 | INTERSECTION |
|---|---|---|---|
| A | 0–600 | 0–350 | 0–350 |
| B | 0–550 | 0–350 | 0–350 |
| C | 0–600 | 0–440 | 0–440 |
| D | 0–550 | 0–350 | 0–350 |
| E | 0–130 | 0–120 | 0–120 |
| F | 0–400 | 0–100 | 0–100 |

0 = extended, max = flexed. Normalised position = `clamp((pos − min) / (max − min), 0, 1)`; it is the only thing the scene consumes.

### Gestures and special commands

| Letter | Name | A | B | C | D | E | F | ms |
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

A gesture is converted to counts with the active profile (`round(n × max)`), as the firmware would.

| Letter | Name | What it does |
|---|---|---|
| S | STOP | Freezes motion where it is. Does **not** return to open. Never rejected for timing. |
| X | CALIBRATE | Sets the current pose as the encoder zero. Nothing moves; the panel shows "recalibrated" and the offset. |
| I | INIT_SHIELDS | Re-initialises the drivers. Accepted; nothing moves. |

---

## API

### `POST /api/command`

```json
{ "command": "A320,D180" }
```

**Accepted — 200**

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

Gestures add `"gesture": {"letter", "name"}`. `S`, `X` and `I` add `"action"`; `X` also adds `"calibration_offset"`.

**Rejected — 422** (the hand does not move)

```json
{
  "accepted": false,
  "stage": "range",
  "code": "OUT_OF_RANGE",
  "message": "A=900 is outside 0-600 for profile TABLE_5_V3."
}
```

#### Validation stages, in order

| Stage | Code | When |
|---|---|---|
| `protocol` | `EMPTY_COMMAND` | Empty line. |
| | `LINE_TOO_LONG` | More than 128 characters. |
| | `EMPTY_TOKEN` | Stray or doubled comma (`A1,,B2`, `A1,`). |
| | `MALFORMED_TOKEN` | Not "uppercase letter + optional unsigned integer" (`a320`, `A-5`, `A 3`). |
| | `UNKNOWN_LETTER` | Letter that does not exist (`Z`, `Q10`). |
| | `UNEXPECTED_POSITION` | Gesture or special with a number (`P20`, `S1`). |
| | `MISSING_POSITION` | Actuator without a number (`A`, `D`). Exception: `C` alone is the CLOSE gesture. |
| | `TOO_MANY_TOKENS` | More than 6 positions. |
| | `DUPLICATE_LETTER` | Repeated letter (`A320,A100`, `C,C400`). |
| `exclusivity` | `EXCLUSIVE_COMMAND` | `S`, `X` or `I` with company (`S,A320`). |
| | `GESTURE_NOT_ALONE` | Gesture with company (`P,A320`). |
| `range` | `OUT_OF_RANGE` | Position outside the active profile. **Never clamped.** |
| `kinematics` | `BEYOND_MECHANICAL_TRAVEL` | After an `X` with a flexed hand, encoder + offset falls outside travel. Never happens with the factory origin. The thumb-index collision check belongs here. |
| | `CALIBRATE_WHILE_MOVING` | `X` while the hand is moving (send `S` first). |
| `timing` | `TOO_SOON` | Less than 50 ms since the last accepted command. Carries `retry_after_ms` and a `Retry-After` header. `S` is exempt. |

Request errors (not line errors), with `"stage": "request"`:

| HTTP | Code | Cause |
|---|---|---|
| 415 | `UNSUPPORTED_MEDIA_TYPE` | Missing `Content-Type: application/json`. |
| 400 | `INVALID_JSON` | Body is not JSON. |
| 413 | `BODY_TOO_LARGE` | Body over 4 KB. |
| 422 | `BAD_REQUEST` | `command` missing or not a string. |
| 403 | `ORIGIN_NOT_ALLOWED` | Browser request from a disallowed origin. |

### `GET /api/state`

Current pose (encoder counts and normalised, interpolated to this instant), targets, active profile and limits, whether anything is moving (`moving`, `moving_actuators`), calibration offset, actuators outside the profile, last command and in-flight trajectories. No history.

### `GET /api/spec`

All tables (actuators, profiles, 15 joints, gestures, specials, protocol and motion rules), served from `app/spec.py`, the same place the simulator and the scene read them from.

### `POST /api/profile`

```json
{ "profile": "INTERSECTION" }
```

Values: `TABLE_5_V3`, `ANNEX_A_V3`, `INTERSECTION`. Does not move the hand. If the current pose ends up outside the new envelope, it says so in `out_of_envelope` and the panel marks it amber:

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

The server pushes; the browser never asks. On connect a `snapshot` arrives with the full state (and in-flight trajectories, so animation resumes where it is). After that:

```json
{ "type": "pose", "target": { "A": 0.5333, "D": 0.3273 }, "target_counts": { "A": 320, "D": 180 }, "duration_ms": 356, "frame": "A320,D180" }
{ "type": "stop", "pose": { "A": 0.41, "...": 0 }, "counts": { "A": 246, "...": 0 } }
{ "type": "calibrated", "offset": { "A": 300, "...": 0 }, "counts": { "A": 0, "...": 0 } }
{ "type": "profile", "profile": "INTERSECTION", "out_of_envelope": [] }
{ "type": "command", "frame": "A900", "accepted": false, "stage": "range", "code": "OUT_OF_RANGE", "message": "..." }
```

`target` only includes the actuators that change; the rest keep their trajectory.

---

## Motion

- Nothing teleports: every command is a motion with a duration.
- Positions: `duration = clamp(max|Δcounts| / 900 × 1000, 120, 5000)` ms, with Δ measured from the **current** (interpolated) position.
- Gestures: their table duration.
- Interpolation happens in each actuator's normalised space with `easeInOutCubic`; the 15 joint angles derive from it: `angle = min + clamp(n × coupling, 0, 1) × (max − min)`.
- A new command re-targets from wherever the hand is. There is no queue.
- The server sends targets, not frames; the browser interpolates with `requestAnimationFrame`. The server evaluates the same curve to know where the hand is (for `S`, re-targeting and durations).

### Calibration (`X`) in detail

The simulator keeps "absolute" counts from the factory origin. The encoder reads `absolute − offset`. `X` sets `offset = current absolute`: the panel shows 0 and the hand does not move. Later commands speak encoder counts, like the firmware: if you calibrate with the little finger at 300 of 600, `A300` drives it to the end stop and `A301` is rejected at `kinematics`. To return to the factory origin, restart the container.

---

## The scene

The screen is just the hand. Everything else folds away:

- **Top left:** the name and a connection dot (navy = connected, blinking amber = disconnected). While something moves, a pink label lists the letters in motion.
- **Bottom centre:** a brief notice for each command (line, gesture, duration). It hides itself after 2.6 s; rejections stay 7 s with an amber bar, and the panel button shows an amber dot.
- **Top-right button** (or key <kbd>I</kbd>): opens and closes the **status panel** with the six positions (counts and normalised), the profile, whether anything is moving, the encoder origin and the last command with its verdict and reason. <kbd>Esc</kbd> closes it. The browser remembers whether you left it open. With the panel open, the hand shifts into the free space. On phones the panel slides up from the bottom.
- **Mouse:** drag to orbit, wheel to zoom, double-click to return to the starting view. The camera never moves on its own.

### The hand

- A realistic right hand seen from the back in three-quarter view, standing on its wrist with a soft floor shadow.
- **Skin:** the mesh is generated on page load from a distance field (round cones and ellipsoids smoothly blended): a palm with a metacarpal arch, thenar and hypothenar eminences, finger webs, knuckles, pads and a wrist. A physical material with a soft sheen, apparent light scattering at the edges, pores, flexion creases on fingers, palm and wrist, knuckle wrinkles and ambient occlusion.
- **Nails** with a lunula and a free edge.
- **Lighting:** studio lighting (room environment) plus a key light that casts the shadow.
- **Joints:** hierarchy hand → finger → proximal → intermediate → distal. Each phalanx rotates at its joint, and its ends are spheres centred on it, so the skin never opens when flexing. D0 rotates about **Y** (opposition); the thumb has D1_P and D1_D, no intermediate joint. The thumb placement was tuned numerically so the pads meet in `Y` (OK, thumb-index) and `P` (PINCH, thumb-middle).
- **State colours on the skin:** the moving finger takes a soft pink tint, and a finger outside the profile turns amber. A switch in the panel turns this off.

URL parameters:

| Parameter | Effect |
|---|---|
| `?view=palm` / `?view=side` | Start from the palm or the side (default `back`: the back of the hand). |
| `?hand=left` | Left hand (same geometry, X mirrored). |
| `?lang=en` | English UI. |
| `?quality=0.7` | Lighter mesh for slow machines (1 = normal). |

The page only draws when something changes (camera, pose or tint), so it uses no GPU at rest. Building the mesh takes about 1 s.

Three.js 0.186 is bundled in `static/vendor/three` (MIT licence): the page works offline. No external models, textures or fonts are used.

> **Change from the original brief.** At your request, the hand is no longer navy and shadowless: it is skin-coloured, with a soft floor shadow and a short wrist stub so it looks natural (there is still no arm or armband). The fixed palette still applies to the whole interface, and pink and amber still mark motion and warnings. There is still no dark mode.

---

## Constraints honoured on purpose

- No login, users or tokens.
- CORS closed: no `*`. On top of that, an origin guard answers 403 to any browser HTTP or WebSocket request whose `Origin` is not the one serving the page (CORS alone does not stop a cross-site POST from arriving). Requiring `application/json` forces a preflight.
- No storage: no database, no files, no history. The container runs with a read-only filesystem.
- No traceability: Uvicorn runs with `--no-access-log`; commands are not logged.
- No decision logic: validate, then obey or reject. A command is never corrected.
- One process (`--workers 1`): several would mean several hands.

> **Warning:** there is no authentication by design. Do not expose the port to the Internet; use it on your machine or a trusted network.

---

## Layout

```
app/
  spec.py        tables: single source of truth (also served at /api/spec)
  protocol.py    line parser: protocol and exclusivity stages
  motion.py      state, trajectories, range/kinematics/timing stages, S/X/I
  main.py        FastAPI: routes, WebSocket, origin guard
static/
  index.html     single page
  js/app.js      WebSocket, scene, folding panel and animation loop
  js/hand.js     anatomy, skin and nails; joint hierarchy
  js/sdf.js      distance fields and meshing (surface nets)
  js/motion.js   per-actuator interpolation (same curve as motion.py)
  css/style.css  fixed palette
  vendor/three/  bundled Three.js
tests/           pytest (parser, API, motion, WebSocket, origin)
examples/        Python, PowerShell and curl emitters
Dockerfile       runtime and test stages (Python 3.13-slim, unprivileged user)
compose.yaml     simulator service (+ tests with --profile test)
```

### Without Docker (development)

```bash
python -m venv .venv && . .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8000 --no-access-log
python -m pytest
```
