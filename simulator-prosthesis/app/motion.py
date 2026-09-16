"""Estado de la mano y trayectorias. Todo en memoria, nada persiste.
Hand state and trajectories. All in memory, nothing persists.

ES: El servidor modela las trayectorias con la misma curva que el navegador para
    saber dónde está la mano en cada instante (lo necesitan S, la reorientación
    y el cálculo de duración). Pero el servidor NO emite fotogramas: envía el
    destino y la duración una sola vez y el navegador interpola.
EN: The server models trajectories with the same curve as the browser so it
    knows where the hand is at any instant (STOP, re-targeting and duration all
    need it). But the server does NOT stream frames: it sends the target and
    the duration once and the browser interpolates.

Cuentas / Counts
----------------
ES: ``abs`` = cuentas desde el origen de fábrica (0 = extendido). El encóder lee
    ``abs - offset``. ``X`` (CALIBRATE) fija ``offset = abs`` actual: el encóder
    pasa a leer 0 y la mano no se mueve. Los comandos hablan en cuentas de
    encóder, igual que el firmware.
EN: ``abs`` = counts from the factory origin (0 = extended). The encoder reads
    ``abs - offset``. ``X`` (CALIBRATE) sets ``offset = current abs``: the
    encoder now reads 0 and the hand does not move. Commands speak encoder
    counts, exactly like the firmware.
"""

from __future__ import annotations

import math
import time
from collections.abc import Callable
from dataclasses import dataclass

from . import spec
from .protocol import Command, Rejection, parse

Event = dict


def ease_in_out_cubic(u: float) -> float:
    """Misma curva que ``static/js/motion.js`` / Same curve as ``static/js/motion.js``."""
    u = min(1.0, max(0.0, u))
    return 4 * u * u * u if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2


@dataclass(slots=True)
class Track:
    """Trayectoria de un actuador / One actuator's trajectory.

    Interpola a la vez la posición normalizada (lo que ve la escena) y las
    cuentas absolutas (lo que ve el panel), con la misma curva.
    Interpolates normalised position (what the scene sees) and absolute counts
    (what the panel sees) together, with the same curve.
    """

    from_norm: float
    to_norm: float
    from_abs: float
    to_abs: float
    start: float
    duration: float  # s

    @classmethod
    def still(cls, norm: float, abs_counts: float, now: float) -> Track:
        return cls(norm, norm, abs_counts, abs_counts, now, 0.0)

    def progress(self, now: float) -> float:
        if self.duration <= 0:
            return 1.0
        return min(1.0, max(0.0, (now - self.start) / self.duration))

    def at(self, now: float) -> tuple[float, float]:
        k = ease_in_out_cubic(self.progress(now))
        return (
            self.from_norm + (self.to_norm - self.from_norm) * k,
            self.from_abs + (self.to_abs - self.from_abs) * k,
        )

    def moving(self, now: float) -> bool:
        return self.progress(now) < 1.0 and (self.from_norm != self.to_norm or self.from_abs != self.to_abs)


def _r4(x: float) -> float:
    return round(x, 4)


class HandSimulator:
    """La mano simulada. No es segura entre hilos: úsese desde un solo bucle.
    The simulated hand. Not thread-safe: use it from a single event loop."""

    def __init__(self, clock: Callable[[], float] = time.monotonic):
        self._clock = clock
        now = clock()
        self.profile: str = spec.DEFAULT_PROFILE
        self.tracks: dict[str, Track] = {k: Track.still(0.0, 0.0, now) for k in spec.ACTUATOR_LETTERS}
        self.offset: dict[str, int] = {k: 0 for k in spec.ACTUATOR_LETTERS}
        self.last_command: dict | None = None
        self._last_accepted_at: float | None = None

    # ------------------------------------------------------------------ helpers

    @property
    def limits(self) -> dict[str, tuple[int, int]]:
        return spec.PROFILES[self.profile]

    def _encoder(self, letter: str, abs_counts: float) -> float:
        return abs_counts - self.offset[letter]

    def is_moving(self, now: float | None = None) -> bool:
        now = self._clock() if now is None else now
        return any(t.moving(now) for t in self.tracks.values())

    def current(self, now: float | None = None) -> tuple[dict[str, int], dict[str, float]]:
        """Cuentas de encóder y normalizadas actuales / Current encoder counts and normalised."""
        now = self._clock() if now is None else now
        counts, norms = {}, {}
        for k, track in self.tracks.items():
            n, a = track.at(now)
            counts[k] = round(self._encoder(k, a))
            norms[k] = _r4(n)
        return counts, norms

    def out_of_envelope(self, now: float | None = None) -> list[dict]:
        """Actuadores cuya posición actual o destino queda fuera del perfil activo.
        Actuators whose current or target position is outside the active profile."""
        now = self._clock() if now is None else now
        result = []
        for k, track in self.tracks.items():
            lo, hi = self.limits[k]
            _, a = track.at(now)
            pos = round(self._encoder(k, a))
            target = round(self._encoder(k, track.to_abs))
            if not (lo <= pos <= hi) or not (lo <= target <= hi):
                result.append({"actuator": k, "position": pos, "target": target, "limits": {"min": lo, "max": hi}})
        return result

    # ------------------------------------------------------------------ commands

    def handle(self, raw: str) -> tuple[dict, list[Event]]:
        """Valida y aplica una línea. Devuelve (respuesta, eventos para el WS).
        Validates and applies one line. Returns (response, WebSocket events).

        Un rechazo no toca la pose / A rejection never touches the pose.
        """
        now = self._clock()
        try:
            cmd = parse(raw)
            if cmd.kind == "positions":
                plan = self._plan_positions(cmd, now)
            elif cmd.kind == "gesture":
                plan = self._plan_gesture(cmd, now)
            else:
                plan = self._plan_special(cmd, now)
            self._check_timing(cmd, now)
        except Rejection as rej:
            frame = raw[:-1] if raw.endswith(spec.TERMINATOR) else raw
            self.last_command = {"frame": frame[: spec.MAX_LINE_CHARS + 16], **rej.as_dict()}
            return rej.as_dict(), [{"type": "command", **self.last_command}]

        # ES: A partir de aquí el comando está aceptado y se aplica.
        # EN: From here on the command is accepted and applied.
        self._last_accepted_at = now
        response, events = plan()
        self.last_command = {"frame": cmd.frame, "accepted": True, **_summary(response)}
        events.append({"type": "command", **self.last_command})
        return response, events

    # ES: Cada _plan_* valida (rango, cinemática) SIN mutar y devuelve una
    #     función que aplica el cambio. Así la etapa de cadencia, que va
    #     después, puede rechazar sin haber tocado nada.
    # EN: Each _plan_* validates (range, kinematics) WITHOUT mutating and
    #     returns a function that applies the change. That way the timing
    #     stage, which comes last, can reject with nothing touched.

    def _plan_positions(self, cmd: Command, now: float):
        limits = self.limits
        # --- rango / range
        for k, pos in cmd.positions.items():
            lo, hi = limits[k]
            if not lo <= pos <= hi:
                raise Rejection(
                    "range",
                    "OUT_OF_RANGE",
                    f"{k}={pos} is outside {lo}-{hi} for profile {self.profile}.",
                )
        # --- cinemática / kinematics
        targets_abs = {k: pos + self.offset[k] for k, pos in cmd.positions.items()}
        self._check_kinematics(targets_abs)

        def apply():
            deltas = []
            target_norm = {}
            for k, pos in cmd.positions.items():
                n_now, a_now = self.tracks[k].at(now)
                deltas.append(abs(targets_abs[k] - a_now))
                target_norm[k] = spec.normalise(targets_abs[k], limits[k])
            duration_ms = _position_duration_ms(max(deltas))
            for k in cmd.positions:
                self._retarget(k, target_norm[k], targets_abs[k], duration_ms, now)
            return _pose_response(cmd.frame, dict(cmd.positions), target_norm, duration_ms), [
                _pose_event(cmd.frame, target_norm, dict(cmd.positions), duration_ms)
            ]

        return apply

    def _plan_gesture(self, cmd: Command, now: float):
        gesture = spec.GESTURES[cmd.letter]
        limits = self.limits
        # ES: El gesto se traduce a cuentas con el perfil activo, como el firmware.
        # EN: The gesture is converted to counts using the active profile, like the firmware.
        counts = {k: round(lo + n * (hi - lo)) for k, n in gesture.targets.items() for lo, hi in [limits[k]]}
        # --- rango: siempre dentro por construcción / range: always inside by construction
        targets_abs = {k: c + self.offset[k] for k, c in counts.items()}
        self._check_kinematics(targets_abs)

        def apply():
            target_norm = {k: spec.normalise(targets_abs[k], limits[k]) for k in counts}
            for k in counts:
                self._retarget(k, target_norm[k], targets_abs[k], gesture.duration_ms, now)
            response = _pose_response(cmd.frame, counts, target_norm, gesture.duration_ms)
            response["gesture"] = {"letter": gesture.letter, "name": gesture.name}
            return response, [_pose_event(cmd.frame, target_norm, counts, gesture.duration_ms, gesture.name)]

        return apply

    def _plan_special(self, cmd: Command, now: float):
        letter = cmd.letter
        name = spec.SPECIALS[letter]["name"]

        if letter == "S":

            def apply_stop():
                # ES: Congela donde esté. NO vuelve a abierto: en el hardware
                #     desenergiza los motores.
                # EN: Freeze where it is. Does NOT return to open: on the
                #     hardware it de-energises the motors.
                for k, track in self.tracks.items():
                    n, a = track.at(now)
                    self.tracks[k] = Track.still(n, a, now)
                counts, norms = self.current(now)
                response = {"accepted": True, "frame": cmd.frame, "action": name,
                            "pose": {"actuator_positions": counts, "actuator_normalised": norms, "duration_ms": 0}}
                return response, [{"type": "stop", "pose": norms, "counts": counts}]

            return apply_stop

        if letter == "X":
            # ES: El nuevo origen debe ser una pose quieta; con la mano en
            #     movimiento el cero quedaría en un punto arbitrario.
            # EN: The new origin must be a still pose; with the hand moving the
            #     zero would land at an arbitrary point.
            if self.is_moving(now):
                raise Rejection(
                    "kinematics",
                    "CALIBRATE_WHILE_MOVING",
                    "Cannot set the encoder zero while the hand is moving; send S first.",
                )

            def apply_calibrate():
                for k, track in self.tracks.items():
                    _, a = track.at(now)
                    self.offset[k] = round(a)
                counts, norms = self.current(now)
                response = {"accepted": True, "frame": cmd.frame, "action": name,
                            "calibration_offset": dict(self.offset),
                            "pose": {"actuator_positions": counts, "actuator_normalised": norms, "duration_ms": 0}}
                return response, [{"type": "calibrated", "offset": dict(self.offset), "counts": counts}]

            return apply_calibrate

        # I — INIT_SHIELDS: se acepta y no se mueve nada / accepted, nothing moves.
        def apply_init():
            return {"accepted": True, "frame": cmd.frame, "action": name}, []

        return apply_init

    def _check_kinematics(self, targets_abs: dict[str, float]) -> None:
        """Etapa ``kinematics``: ¿la pose resultante es representable?
        Stage ``kinematics``: is the resulting pose representable?

        ES: Con el origen de fábrica siempre lo es si pasó el rango. Solo tras
            un ``X`` con la mano flexionada puede pedirse una posición que
            cae más allá del recorrido mecánico; se rechaza, no se acota.
            Aquí irá la colisión pulgar-índice si algún día se modela.
        EN: With the factory origin it always is if it passed the range stage.
            Only after an ``X`` with a flexed hand can a command ask for a
            position beyond mechanical travel; it is rejected, not clamped.
            The thumb-index collision check belongs here if it is ever modelled.
        """
        for k, a in targets_abs.items():
            lo, hi = self.limits[k]
            if not lo <= a <= hi:
                raise Rejection(
                    "kinematics",
                    "BEYOND_MECHANICAL_TRAVEL",
                    f"{k}: encoder {round(a - self.offset[k])} + calibration offset {self.offset[k]} "
                    f"= {round(a)} counts from the factory origin, outside {lo}-{hi} ({self.profile}).",
                )
        # TODO(colisión pulgar-índice / thumb-index collision)

    def _check_timing(self, cmd: Command, now: float) -> None:
        """Etapa ``timing``: el firmware acepta como mucho un comando cada 50 ms.
        Stage ``timing``: the firmware accepts at most one command every 50 ms.

        ES: Decisión de seguridad: S (parada) nunca se rechaza por cadencia.
        EN: Safety decision: S (stop) is never rejected for arriving too soon.
        """
        if cmd.kind == "special" and cmd.letter == "S":
            return
        if self._last_accepted_at is None:
            return
        elapsed_ms = (now - self._last_accepted_at) * 1000
        if elapsed_ms < spec.MIN_COMMAND_INTERVAL_MS:
            wait = math.ceil(round(spec.MIN_COMMAND_INTERVAL_MS - elapsed_ms, 6))
            raise Rejection(
                "timing",
                "TOO_SOON",
                f"Only {elapsed_ms:.1f} ms since the last accepted command; "
                f"the minimum interval is {spec.MIN_COMMAND_INTERVAL_MS} ms (retry in {wait} ms).",
                retry_after_ms=wait,
            )

    def _retarget(self, k: str, to_norm: float, to_abs: float, duration_ms: int, now: float) -> None:
        # ES: Reorienta desde donde esté. No hay cola.
        # EN: Re-target from wherever it is. There is no queue.
        n, a = self.tracks[k].at(now)
        self.tracks[k] = Track(n, to_norm, a, to_abs, now, duration_ms / 1000)

    # ------------------------------------------------------------------ profile

    def set_profile(self, name: str) -> tuple[dict, list[Event]]:
        if name not in spec.PROFILES:
            raise KeyError(name)
        previous, self.profile = self.profile, name
        # ES: No se mueve la mano ni se reacomoda nada. Solo se informa.
        # EN: The hand does not move and nothing is re-fitted. It is only reported.
        outside = self.out_of_envelope()
        if outside:
            letters = ", ".join(o["actuator"] for o in outside)
            message = (f"Profile changed to {name}. The hand did not move; actuator(s) {letters} "
                       f"are now outside the {name} envelope.")
        else:
            message = f"Profile changed to {name}. The current pose is inside the new envelope."
        response = {"profile": name, "previous": previous, "moved": False,
                    "out_of_envelope": outside, "message": message}
        return response, [{"type": "profile", "profile": name, "out_of_envelope": outside}]

    # ------------------------------------------------------------------ views

    def snapshot(self) -> dict:
        now = self._clock()
        counts, norms = self.current(now)
        tracks = {}
        for k, t in self.tracks.items():
            if t.moving(now):
                tracks[k] = {
                    "from": _r4(t.from_norm), "to": _r4(t.to_norm),
                    "from_counts": round(self._encoder(k, t.from_abs)),
                    "to_counts": round(self._encoder(k, t.to_abs)),
                    "duration_ms": round(t.duration * 1000),
                    "elapsed_ms": round((now - t.start) * 1000),
                }
        moving_letters = sorted(tracks)
        return {
            "profile": self.profile,
            "limits": {k: {"min": lo, "max": hi} for k, (lo, hi) in self.limits.items()},
            "moving": bool(moving_letters),
            "moving_actuators": moving_letters,
            "actuator_positions": counts,
            "actuator_normalised": norms,
            "targets": {
                k: {"position": round(self._encoder(k, t.to_abs)), "normalised": _r4(t.to_norm)}
                for k, t in self.tracks.items()
            },
            "calibration_offset": dict(self.offset),
            "calibrated": any(self.offset.values()),
            "out_of_envelope": self.out_of_envelope(now),
            "last_command": self.last_command,
            "trajectories": tracks,
        }


def _position_duration_ms(max_delta_counts: float) -> int:
    """|Δcuentas| máx / 900 × 1000, acotado a [120, 5000] ms."""
    raw = max_delta_counts / spec.MOTOR_COUNTS_PER_SECOND * 1000
    return int(min(spec.MAX_DURATION_MS, max(spec.MIN_DURATION_MS, round(raw))))


def _pose_response(frame: str, counts: dict, norms: dict, duration_ms: int) -> dict:
    return {
        "accepted": True,
        "frame": frame,
        "pose": {
            "actuator_positions": counts,
            "actuator_normalised": {k: _r4(v) for k, v in norms.items()},
            "duration_ms": duration_ms,
        },
    }


def _pose_event(frame: str, norms: dict, counts: dict, duration_ms: int, gesture: str | None = None) -> Event:
    event = {"type": "pose", "target": {k: _r4(v) for k, v in norms.items()},
             "target_counts": counts, "duration_ms": duration_ms, "frame": frame}
    if gesture:
        event["gesture"] = gesture
    return event


def _summary(response: dict) -> dict:
    out = {}
    if "action" in response:
        out["action"] = response["action"]
    if "gesture" in response:
        out["gesture"] = response["gesture"]["name"]
    if "pose" in response:
        out["duration_ms"] = response["pose"]["duration_ms"]
    return out
