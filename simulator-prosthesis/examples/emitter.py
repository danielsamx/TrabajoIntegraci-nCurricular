#!/usr/bin/env python3
"""Emisor de ejemplo: envía líneas al simulador en tiempo real. Solo biblioteca estándar.
Example emitter: sends lines to the simulator in real time. Standard library only.

Uso / Usage:
    python emitter.py "A320,D180"                  # una línea / one line
    python emitter.py --interactive                # escribe líneas y Enter / type lines + Enter
    python emitter.py --demo                       # secuencia de ejemplo / sample sequence
    python emitter.py --url http://192.168.1.50:8000 P

ES: Mantiene UNA conexión HTTP abierta (keep-alive) para no pagar el
    establecimiento de conexión en cada comando. Respeta el intervalo mínimo
    de 50 ms que exige el firmware (y el simulador).
EN: Keeps ONE HTTP connection open (keep-alive) so each command does not pay
    for connection setup. Respects the 50 ms minimum interval that the firmware
    (and the simulator) enforce.
"""

from __future__ import annotations

import argparse
import http.client
import json
import sys
import time
from urllib.parse import urlsplit


class Emitter:
    def __init__(self, base_url: str, min_interval_ms: int = 50):
        parts = urlsplit(base_url)
        self.https = parts.scheme == "https"
        self.host = parts.hostname or "localhost"
        self.port = parts.port or (443 if self.https else 80)
        self.min_interval = min_interval_ms / 1000
        self._last = 0.0
        self._conn: http.client.HTTPConnection | None = None

    def _connection(self) -> http.client.HTTPConnection:
        if self._conn is None:
            cls = http.client.HTTPSConnection if self.https else http.client.HTTPConnection
            self._conn = cls(self.host, self.port, timeout=5)
        return self._conn

    def _request(self, method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
        payload = None if body is None else json.dumps(body).encode()
        headers = {"Content-Type": "application/json"} if body is not None else {}
        for attempt in (1, 2):
            conn = self._connection()
            try:
                conn.request(method, path, body=payload, headers=headers)
                resp = conn.getresponse()
                return resp.status, json.loads(resp.read() or b"{}")
            except (http.client.HTTPException, OSError):
                # ES: reconecta una vez / EN: reconnect once
                conn.close()
                self._conn = None
                if attempt == 2:
                    raise
        raise AssertionError("unreachable")

    def send(self, line: str) -> tuple[int, dict]:
        wait = self.min_interval - (time.monotonic() - self._last)
        if wait > 0 and line != "S":  # S nunca espera / S never waits
            time.sleep(wait)
        status, data = self._request("POST", "/api/command", {"command": line})
        if data.get("accepted"):
            self._last = time.monotonic()
        return status, data

    def state(self) -> dict:
        return self._request("GET", "/api/state")[1]

    def spec(self) -> dict:
        return self._request("GET", "/api/spec")[1]

    def set_profile(self, name: str) -> tuple[int, dict]:
        return self._request("POST", "/api/profile", {"profile": name})


def show(line: str, status: int, data: dict) -> None:
    if data.get("accepted"):
        pose = data.get("pose", {})
        extra = data.get("gesture", {}).get("name") or data.get("action") or ""
        print(f"OK   {line:<24} {extra:<14} {pose.get('duration_ms', 0):>5} ms  {pose.get('actuator_positions', '')}")
    else:
        print(f"FAIL {line:<24} [{status}] {data.get('stage')}/{data.get('code')}: {data.get('message')}")


DEMO = [
    ("O", 0.9), ("C", 1.0), ("O", 0.9), ("P", 1.0), ("Y", 1.0), ("G", 1.0), ("L", 1.0),
    ("O", 0.9), ("A320,D180", 0.5), ("C400", 0.7),
    ("A900", 0.3),            # rechazado: fuera de rango / rejected: out of range
    ("S,A320", 0.3),          # rechazado: S va sola / rejected: S must be alone
    ("C", 0.4), ("S", 0.8),   # para a mitad / stops mid-way
    ("A600,B550", 0.05), ("A0,B0", 0.8),  # reorienta sin esperar / re-targets without waiting
    ("O", 1.0),
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("line", nargs="?", help='línea de comando / command line, e.g. "A320,D180"')
    ap.add_argument("--url", default="http://localhost:8000")
    ap.add_argument("--interactive", "-i", action="store_true")
    ap.add_argument("--demo", action="store_true")
    ap.add_argument("--profile", choices=["TABLE_5_V3", "ANNEX_A_V3", "INTERSECTION"])
    args = ap.parse_args()

    em = Emitter(args.url)
    if args.profile:
        print(json.dumps(em.set_profile(args.profile)[1], indent=2, ensure_ascii=False))
    if args.line:
        status, data = em.send(args.line)
        show(args.line, status, data)
        return 0 if data.get("accepted") else 1
    if args.demo:
        for line, pause in DEMO:
            show(line, *em.send(line))
            time.sleep(pause)
        return 0
    if args.interactive:
        print("Escribe una línea y Enter (Ctrl+C para salir) / Type a line and Enter (Ctrl+C to quit)")
        try:
            for raw in sys.stdin:
                line = raw.rstrip("\r\n")
                if line:
                    show(line, *em.send(line))
        except KeyboardInterrupt:
            pass
        return 0
    if not args.profile:
        ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
