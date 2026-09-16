"""Tablas de la mano: única fuente de verdad.
Hand tables: single source of truth.

ES: Todo lo que el simulador sabe de la mano está aquí. El servidor valida con
    estas tablas, la escena 3D las lee de ``GET /api/spec`` y quien escriba el
    emisor de comandos debería leerlas de ese mismo endpoint en vez de copiarlas.
EN: Everything the simulator knows about the hand lives here. The server
    validates against these tables, the 3D scene reads them from
    ``GET /api/spec``, and whoever writes the command emitter should read them
    from that same endpoint instead of copying them by hand.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Final

# ---------------------------------------------------------------------------
# Actuadores / Actuators
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Actuator:
    letter: str
    finger: str
    finger_es: str
    finger_id: str
    motion: str
    hardware: str


ACTUATORS: Final[tuple[Actuator, ...]] = (
    Actuator("A", "little", "meñique", "D5", "flexion/extension", "Pololu 380:1 + magnetic encoder"),
    Actuator("B", "ring", "anular", "D4", "flexion/extension", "Pololu 380:1 + magnetic encoder"),
    Actuator("C", "middle", "medio", "D3", "flexion/extension", "Pololu 380:1 + magnetic encoder"),
    Actuator("D", "index", "índice", "D2", "flexion/extension", "Pololu 380:1 + magnetic encoder"),
    Actuator("E", "thumb (lower)", "pulgar inferior", "D0", "rotation/opposition", "MG90S servo"),
    Actuator("F", "thumb (upper)", "pulgar superior", "D1", "flexion/extension", "Pololu 380:1 + magnetic encoder"),
)

ACTUATOR_LETTERS: Final[tuple[str, ...]] = tuple(a.letter for a in ACTUATORS)

# ---------------------------------------------------------------------------
# Perfiles de límites / Travel-limit profiles
#
# ES: El manual se contradice, por eso hay tres. 0 = extendido, max = flexionado.
# EN: The manual contradicts itself, hence three. 0 = extended, max = flexed.
# ---------------------------------------------------------------------------

DEFAULT_PROFILE: Final[str] = "TABLE_5_V3"

PROFILES: Final[dict[str, dict[str, tuple[int, int]]]] = {
    "TABLE_5_V3": {"A": (0, 600), "B": (0, 550), "C": (0, 600), "D": (0, 550), "E": (0, 130), "F": (0, 400)},
    "ANNEX_A_V3": {"A": (0, 350), "B": (0, 350), "C": (0, 440), "D": (0, 350), "E": (0, 120), "F": (0, 100)},
    "INTERSECTION": {"A": (0, 350), "B": (0, 350), "C": (0, 440), "D": (0, 350), "E": (0, 120), "F": (0, 100)},
}


def normalise(position: float, limits: tuple[int, int]) -> float:
    """(pos - min) / (max - min), acotado a [0, 1] / clamped to [0, 1].

    ES: Es lo único que consume la escena; la geometría no sabe de cuentas.
        Este acotado es de *representación*; la validación de rango ocurre
        antes y nunca acota un comando.
    EN: This is the only thing the scene consumes; geometry knows nothing about
        encoder counts. This clamp is for *display*; range validation happens
        earlier and never clamps a command.
    """
    lo, hi = limits
    value = (position - lo) / (hi - lo)
    return min(1.0, max(0.0, value))


# ---------------------------------------------------------------------------
# Cinemática: 15 articulaciones, 6 motores / Kinematics: 15 joints, 6 motors
#
# angle = min_flex + clamp(normalised * coupling, 0, 1) * (max_flex - min_flex)
#
# ES: D0 gira sobre Y (oposición). El pulgar NO tiene articulación intermedia.
# EN: D0 rotates about Y (opposition). The thumb has NO intermediate joint.
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Joint:
    id: str
    finger: str
    kind: str
    motor: str
    min_deg: float
    max_deg: float
    coupling: float
    axis: str


JOINTS: Final[tuple[Joint, ...]] = (
    Joint("D0", "thumb", "rotation", "E", 0, 60, 1.00, "Y"),
    Joint("D1_P", "thumb", "proximal", "F", 0, 55, 1.00, "X"),
    Joint("D1_D", "thumb", "distal", "F", 0, 80, 0.85, "X"),
    Joint("D2_P", "index", "proximal", "D", 0, 90, 1.00, "X"),
    Joint("D2_I", "index", "intermediate", "D", 0, 100, 0.95, "X"),
    Joint("D2_D", "index", "distal", "D", 0, 70, 0.70, "X"),
    Joint("D3_P", "middle", "proximal", "C", 0, 90, 1.00, "X"),
    Joint("D3_I", "middle", "intermediate", "C", 0, 100, 0.95, "X"),
    Joint("D3_D", "middle", "distal", "C", 0, 70, 0.70, "X"),
    Joint("D4_P", "ring", "proximal", "B", 0, 90, 1.00, "X"),
    Joint("D4_I", "ring", "intermediate", "B", 0, 100, 0.95, "X"),
    Joint("D4_D", "ring", "distal", "B", 0, 70, 0.70, "X"),
    Joint("D5_P", "little", "proximal", "A", 0, 90, 1.00, "X"),
    Joint("D5_I", "little", "intermediate", "A", 0, 100, 0.95, "X"),
    Joint("D5_D", "little", "distal", "A", 0, 70, 0.70, "X"),
)


def joint_angle_deg(joint: Joint, normalised_value: float) -> float:
    """Ángulo de una articulación / Angle of one joint (degrees)."""
    t = min(1.0, max(0.0, normalised_value * joint.coupling))
    return joint.min_deg + t * (joint.max_deg - joint.min_deg)


# ---------------------------------------------------------------------------
# Gestos / Gestures  (travesía normalizada A B C D E F / normalised travel)
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Gesture:
    letter: str
    name: str
    targets: dict[str, float]
    duration_ms: int


def _g(letter: str, name: str, values: tuple[float, ...], ms: int) -> Gesture:
    return Gesture(letter, name, dict(zip(ACTUATOR_LETTERS, values, strict=True)), ms)


GESTURES: Final[dict[str, Gesture]] = {
    g.letter: g
    for g in (
        _g("O", "OPEN", (0.00, 0.00, 0.00, 0.00, 0.00, 0.00), 800),
        _g("C", "CLOSE", (1.00, 1.00, 1.00, 1.00, 1.00, 1.00), 900),
        _g("P", "PINCH", (0.15, 0.15, 0.85, 0.15, 0.90, 0.80), 850),
        _g("R", "SPIDERMAN", (0.00, 1.00, 1.00, 0.00, 0.00, 0.00), 900),
        _g("W", "PARTIAL_CLAW", (0.00, 1.00, 0.00, 1.00, 0.00, 0.00), 900),
        _g("Y", "OK", (0.10, 0.10, 0.10, 0.85, 0.85, 0.75), 900),
        _g("L", "THUMBS_UP", (1.00, 1.00, 1.00, 1.00, 0.00, 0.00), 900),
        _g("M", "CALL_ME", (0.00, 1.00, 1.00, 1.00, 0.00, 0.00), 900),
        _g("H", "NUMBER_THREE", (1.00, 0.00, 0.00, 0.00, 1.00, 1.00), 900),
        _g("U", "NUMBER_FOUR", (0.00, 0.00, 0.00, 0.00, 1.00, 1.00), 900),
        _g("G", "POINT", (1.00, 1.00, 1.00, 0.00, 0.00, 0.00), 850),
    )
}

# ES: Letras que no son poses. Siempre van solas en la línea.
# EN: Letters that are not poses. Always alone on the line.
SPECIALS: Final[dict[str, dict[str, str]]] = {
    "S": {
        "name": "STOP",
        "effect": "Freezes motion where it is, mid-trajectory. Does not return to open.",
        "efecto": "Congela el movimiento donde esté, a mitad de trayectoria. No vuelve a abierto.",
    },
    "X": {
        "name": "CALIBRATE",
        "effect": "Sets the current pose as the encoder zero. Nothing moves.",
        "efecto": "Fija la pose actual como el cero de los encóderes. No se mueve nada.",
    },
    "I": {
        "name": "INIT_SHIELDS",
        "effect": "Re-initialises the motor drivers. No visual effect.",
        "efecto": "Reinicializa los drivers. Sin efecto visual.",
    },
}

# ---------------------------------------------------------------------------
# Protocolo y movimiento / Protocol and motion
# ---------------------------------------------------------------------------

MAX_LINE_CHARS: Final[int] = 128
MAX_POSITION_TOKENS: Final[int] = len(ACTUATORS)
SEPARATOR: Final[str] = ","
TERMINATOR: Final[str] = "\n"

MOTOR_COUNTS_PER_SECOND: Final[float] = 900.0  # 380:1 al 100 % / at 100 %
MIN_DURATION_MS: Final[int] = 120
MAX_DURATION_MS: Final[int] = 5000
MIN_COMMAND_INTERVAL_MS: Final[int] = 50

VALIDATION_STAGES: Final[tuple[str, ...]] = ("protocol", "exclusivity", "range", "kinematics", "timing")


def as_dict() -> dict:
    """Todo lo anterior como JSON para ``GET /api/spec`` / All of the above as JSON."""
    return {
        "actuators": [asdict(a) for a in ACTUATORS],
        "default_profile": DEFAULT_PROFILE,
        "profiles": {
            name: {k: {"min": lo, "max": hi} for k, (lo, hi) in limits.items()}
            for name, limits in PROFILES.items()
        },
        "normalisation": "clamp((pos - min) / (max - min), 0, 1)",
        "joints": [asdict(j) for j in JOINTS],
        "joint_angle": "min_deg + clamp(normalised * coupling, 0, 1) * (max_deg - min_deg)",
        "gestures": {
            g.letter: {"name": g.name, "targets": g.targets, "duration_ms": g.duration_ms}
            for g in GESTURES.values()
        },
        "specials": SPECIALS,
        "protocol": {
            "separator": SEPARATOR,
            "terminator": TERMINATOR,
            "terminator_required_over_http": False,
            "max_line_chars": MAX_LINE_CHARS,
            "max_position_tokens": MAX_POSITION_TOKENS,
            "case_sensitive": True,
            "position_token": "^[A-F][0-9]+$",
            "exclusive_letters": sorted(SPECIALS),
            "gestures_alone": True,
            "duplicate_letters": "rejected",
            "c_disambiguation": "'C' alone = CLOSE gesture; 'C<digits>' = middle-finger actuator.",
            "min_command_interval_ms": MIN_COMMAND_INTERVAL_MS,
            "stop_exempt_from_interval": True,
        },
        "motion": {
            "counts_per_second": MOTOR_COUNTS_PER_SECOND,
            "position_duration_ms": "clamp(max|delta_counts| / 900 * 1000, 120, 5000)",
            "min_duration_ms": MIN_DURATION_MS,
            "max_duration_ms": MAX_DURATION_MS,
            "easing": "easeInOutCubic, in normalised actuator space",
            "retarget": "a new command re-targets from the current pose; nothing is queued",
        },
        "validation_stages": list(VALIDATION_STAGES),
    }
