"""Parser de la línea de comandos (mismo formato que el enlace SPP real).
Command-line parser (same format as the real SPP link).

ES: Este módulo solo cubre las etapas que no dependen del estado de la mano:
    ``protocol`` y ``exclusivity``. Rango, cinemática y cadencia dependen de la
    pose y del perfil activos y viven en ``motion.py``.
EN: This module only covers the stages that do not depend on hand state:
    ``protocol`` and ``exclusivity``. Range, kinematics and timing depend on the
    current pose and profile and live in ``motion.py``.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Literal

from . import spec

Kind = Literal["positions", "gesture", "special"]

# ES: Solo dígitos ASCII. ``str.isdigit`` aceptaría "²" o dígitos árabes.
# EN: ASCII digits only. ``str.isdigit`` would accept "²" or Arabic digits.
_TOKEN_RE = re.compile(r"([A-Z])([0-9]+)?")


class Rejection(Exception):
    """Un comando rechazado: etapa, código y motivo legible.
    A rejected command: stage, code and a human-readable reason."""

    def __init__(self, stage: str, code: str, message: str, retry_after_ms: int | None = None):
        super().__init__(message)
        self.stage = stage
        self.code = code
        self.message = message
        self.retry_after_ms = retry_after_ms

    def as_dict(self) -> dict:
        out = {"accepted": False, "stage": self.stage, "code": self.code, "message": self.message}
        if self.retry_after_ms is not None:
            out["retry_after_ms"] = self.retry_after_ms
        return out


@dataclass(frozen=True, slots=True)
class Command:
    """Una línea ya parseada / A parsed line.

    ``frame`` es la línea sin terminador / is the line without its terminator.
    """

    frame: str
    kind: Kind
    positions: dict[str, int] = field(default_factory=dict)  # kind == "positions"
    letter: str | None = None  # kind in ("gesture", "special")


def parse(raw: str) -> Command:
    """Etapas ``protocol`` y ``exclusivity``. Lanza ``Rejection``.
    Stages ``protocol`` and ``exclusivity``. Raises ``Rejection``."""

    # --- protocolo / protocol -------------------------------------------------
    # ES: Por HTTP el terminador sobra; si viene, se acepta y se descarta.
    #     Solo uno, y solo al final.
    # EN: Over HTTP the terminator is optional; if present it is dropped.
    #     Only one, and only at the end.
    line = raw[:-1] if raw.endswith(spec.TERMINATOR) else raw

    if line == "":
        raise Rejection("protocol", "EMPTY_COMMAND", "The command line is empty.")

    if len(line) > spec.MAX_LINE_CHARS:
        raise Rejection(
            "protocol",
            "LINE_TOO_LONG",
            f"The line has {len(line)} characters; the maximum is {spec.MAX_LINE_CHARS}.",
        )

    tokens = line.split(spec.SEPARATOR)
    parsed: list[tuple[str, str | None]] = []
    for index, token in enumerate(tokens):
        if token == "":
            raise Rejection(
                "protocol",
                "EMPTY_TOKEN",
                f"Token {index + 1} is empty (stray or doubled '{spec.SEPARATOR}').",
            )
        match = _TOKEN_RE.fullmatch(token)
        if match is None:
            raise Rejection(
                "protocol",
                "MALFORMED_TOKEN",
                f"Token '{_show(token)}' is not an uppercase letter followed by an optional "
                "unsigned integer (the protocol is case-sensitive, with no spaces).",
            )
        letter, digits = match.group(1), match.group(2)

        # ES: DESAMBIGUACIÓN DE LA 'C' — léase antes de tocar nada.
        #     'C' aparece en la tabla de gestos (CLOSE) y en la de actuadores
        #     (dedo medio). Ninguna de las dos tablas está mal. Lo que decide es
        #     el sufijo numérico, y solo eso:
        #         "C"    -> gesto CLOSE (cierra toda la mano)
        #         "C400" -> actuador C (dedo medio) a la posición 400
        #     Lo mismo vale en general: con dígitos, la letra debe ser un
        #     actuador (A-F); sin dígitos, debe ser un gesto o una especial.
        # EN: THE 'C' AMBIGUITY — read this before changing anything.
        #     'C' is in the gesture table (CLOSE) and in the actuator table
        #     (middle finger). Neither table is wrong. The numeric suffix decides,
        #     and nothing else does:
        #         "C"    -> CLOSE gesture (closes the whole hand)
        #         "C400" -> actuator C (middle finger) to position 400
        #     The same rule applies generally: with digits the letter must be an
        #     actuator (A-F); without digits it must be a gesture or a special.
        if digits is not None:
            if letter not in spec.ACTUATOR_LETTERS:
                known = letter in spec.GESTURES or letter in spec.SPECIALS
                what = "takes no position" if known else "is not a known command letter"
                raise Rejection(
                    "protocol",
                    "UNEXPECTED_POSITION" if known else "UNKNOWN_LETTER",
                    f"'{letter}' {what} (token '{token}'). Only A-F take a numeric position.",
                )
        elif letter not in spec.GESTURES and letter not in spec.SPECIALS:
            if letter in spec.ACTUATOR_LETTERS:
                raise Rejection(
                    "protocol",
                    "MISSING_POSITION",
                    f"Actuator '{letter}' needs a position, e.g. '{letter}100'.",
                )
            raise Rejection("protocol", "UNKNOWN_LETTER", f"'{letter}' is not a known command letter.")
        parsed.append((letter, digits))

    position_tokens = [p for p in parsed if p[1] is not None]
    if len(position_tokens) > spec.MAX_POSITION_TOKENS:
        raise Rejection(
            "protocol",
            "TOO_MANY_TOKENS",
            f"{len(position_tokens)} position tokens; the hand has {spec.MAX_POSITION_TOKENS} actuators.",
        )

    # ES: Una letra repetida es contradictoria, no "gana el último".
    #     Esto incluye "C,C400": la misma letra dos veces en la línea.
    # EN: A repeated letter is contradictory, not "last one wins".
    #     This includes "C,C400": the same letter twice on the line.
    seen: set[str] = set()
    for letter, _ in parsed:
        if letter in seen:
            raise Rejection(
                "protocol",
                "DUPLICATE_LETTER",
                f"'{letter}' appears more than once in '{_show(line)}'; the line is contradictory.",
            )
        seen.add(letter)

    # --- exclusividad / exclusivity -------------------------------------------
    letters = [letter for letter, _ in parsed]
    if len(parsed) > 1:
        specials = [letter for letter, d in parsed if d is None and letter in spec.SPECIALS]
        if specials:
            s = specials[0]
            raise Rejection(
                "exclusivity",
                "EXCLUSIVE_COMMAND",
                f"'{s}' ({spec.SPECIALS[s]['name']}) must be the only token on the line; "
                f"got {len(parsed)} tokens.",
            )
        # ES: Decisión: un gesto también va solo. Mezclar "P,A320" no tiene una
        #     semántica definida y no la inventamos.
        # EN: Decision: a gesture is also alone. "P,A320" has no defined
        #     meaning and we do not invent one.
        gestures = [letter for letter, d in parsed if d is None and letter in spec.GESTURES]
        if gestures:
            g = gestures[0]
            raise Rejection(
                "exclusivity",
                "GESTURE_NOT_ALONE",
                f"Gesture '{g}' ({spec.GESTURES[g].name}) must be the only token on the line; "
                f"got {len(parsed)} tokens.",
            )

    letter, digits = parsed[0]
    if digits is None:
        kind: Kind = "special" if letter in spec.SPECIALS else "gesture"
        return Command(frame=line, kind=kind, letter=letter)

    positions = {letter: int(digits) for letter, digits in parsed}
    assert list(positions) == letters
    return Command(frame=line, kind="positions", positions=positions)


def _show(text: str, limit: int = 40) -> str:
    """Recorta y escapa texto para mensajes / Trim and escape text for messages."""
    shown = text.encode("unicode_escape").decode("ascii")
    return shown if len(shown) <= limit else shown[: limit - 1] + "…"
