"""Servidor HTTP + WebSocket del simulador.
Simulator HTTP + WebSocket server.

ES: Sin sesiones, sin usuarios, sin almacenamiento, sin registro de comandos.
    El único estado es la pose actual, en memoria. Debe correr con UN solo
    proceso (``--workers 1``): con varios, cada uno tendría su propia mano.
EN: No sessions, no users, no storage, no command logging. The only state is
    the current pose, in memory. Must run as ONE process (``--workers 1``):
    with several, each would have its own hand.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import math
import os
import time
from collections.abc import Callable
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.types import ASGIApp, Receive, Scope, Send

from . import spec
from .motion import HandSimulator

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
MAX_BODY_BYTES = 4096
WS_QUEUE_SIZE = 256
WS_SEND_TIMEOUT_S = 2.0


def _extra_origins() -> list[str]:
    """``SIM_ALLOWED_ORIGINS``: orígenes adicionales, separados por comas.
    Extra browser origins, comma-separated. Empty by default."""
    raw = os.environ.get("SIM_ALLOWED_ORIGINS", "")
    return [o.strip().rstrip("/") for o in raw.split(",") if o.strip()]


# ---------------------------------------------------------------------------
# Guardia de origen / Origin guard
# ---------------------------------------------------------------------------


class OriginGuard:
    """Rechaza peticiones de navegador cuyo ``Origin`` no es el que sirve la página.
    Rejects browser requests whose ``Origin`` is not the one serving the page.

    ES: CORS solo impide *leer* la respuesta; un POST de otro sitio llegaría
        igual. Por eso, además de no abrir CORS, se corta aquí cualquier
        petición (HTTP o WebSocket) con un ``Origin`` ajeno. Los clientes que
        no son navegadores (curl, Python, un microcontrolador) no envían
        ``Origin`` y pasan: son el caso de uso del emisor.
    EN: CORS only stops a page from *reading* the response; a cross-site POST
        would still arrive. So besides keeping CORS closed, any request (HTTP or
        WebSocket) carrying a foreign ``Origin`` is cut here. Non-browser
        clients (curl, Python, a microcontroller) send no ``Origin`` and pass:
        they are the emitter use case.
    """

    def __init__(self, app: ASGIApp, extra_origins: list[str]):
        self.app = app
        self.extra = set(extra_origins)

    def _allowed(self, scope: Scope) -> bool:
        headers = {k.decode("latin-1"): v.decode("latin-1") for k, v in scope.get("headers", [])}
        origin = headers.get("origin")
        if origin is None:
            return True
        origin = origin.rstrip("/")
        if origin in self.extra:
            return True
        parts = urlsplit(origin)
        host = headers.get("host", "")
        return parts.scheme in ("http", "https") and parts.netloc != "" and parts.netloc.lower() == host.lower()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] in ("http", "websocket") and not self._allowed(scope):
            if scope["type"] == "websocket":
                await send({"type": "websocket.close", "code": 1008, "reason": "origin not allowed"})
                return
            body = json.dumps({"accepted": False, "stage": "request", "code": "ORIGIN_NOT_ALLOWED",
                               "message": "This origin may not use the simulator API."}).encode()
            await send({"type": "http.response.start", "status": 403,
                        "headers": [(b"content-type", b"application/json"),
                                    (b"content-length", str(len(body)).encode())]})
            await send({"type": "http.response.body", "body": body})
            return
        await self.app(scope, receive, send)


class RevalidatingStaticFiles(StaticFiles):
    """Archivos estáticos que el navegador debe revalidar siempre.
    Static files the browser must always revalidate.

    ES: Sin ``Cache-Control`` el navegador aplica caché heurística y, tras una
        actualización, puede mezclar el ``index.html`` nuevo con el JS/CSS
        viejo. ``no-cache`` obliga a preguntar (ETag → 304 si no cambió).
    EN: Without ``Cache-Control`` browsers apply heuristic caching and, after an
        update, may mix the new ``index.html`` with stale JS/CSS. ``no-cache``
        forces a revalidation (ETag → 304 when unchanged).
    """

    def file_response(self, *args, **kwargs):
        response = super().file_response(*args, **kwargs)
        response.headers["Cache-Control"] = "no-cache"
        return response


# ---------------------------------------------------------------------------
# Difusión por WebSocket / WebSocket fan-out
# ---------------------------------------------------------------------------


class Client:
    def __init__(self, ws: WebSocket):
        self.ws = ws
        self.queue: asyncio.Queue[dict | None] = asyncio.Queue(WS_QUEUE_SIZE)
        self.task: asyncio.Task | None = None

    def drop(self) -> None:
        if self.task is not None:
            self.task.cancel()

    async def pump(self) -> None:
        while (message := await self.queue.get()) is not None:
            await asyncio.wait_for(self.ws.send_json(message), WS_SEND_TIMEOUT_S)


class Hub:
    """Cada cliente tiene su cola: un navegador lento no frena a la API.
    Each client has its own queue: a slow browser never stalls the API."""

    def __init__(self) -> None:
        self.clients: set[Client] = set()

    def publish(self, events: list[dict]) -> None:
        for client in list(self.clients):
            for event in events:
                try:
                    client.queue.put_nowait(event)
                except asyncio.QueueFull:
                    # ES: Un cliente que no consume se desconecta; al volver recibe un snapshot.
                    # EN: A client that does not drain is dropped; on reconnect it gets a snapshot.
                    self.clients.discard(client)
                    client.drop()
                    break


# ---------------------------------------------------------------------------
# Aplicación / Application
# ---------------------------------------------------------------------------


def _reject(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse({"accepted": False, "stage": "request", "code": code, "message": message}, status)


async def _read_json(request: Request) -> tuple[dict | None, JSONResponse | None]:
    """Exige ``application/json``. Así un POST "simple" de otro sitio no pasa sin preflight.
    Requires ``application/json``, so a cross-site "simple" POST cannot skip preflight."""
    ctype = request.headers.get("content-type", "").split(";")[0].strip().lower()
    if ctype != "application/json":
        return None, _reject(415, "UNSUPPORTED_MEDIA_TYPE", "Send the body as application/json.")
    body = await request.body()
    if len(body) > MAX_BODY_BYTES:
        return None, _reject(413, "BODY_TOO_LARGE", f"The body exceeds {MAX_BODY_BYTES} bytes.")
    try:
        data = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        return None, _reject(400, "INVALID_JSON", "The body is not valid JSON.")
    if not isinstance(data, dict):
        return None, _reject(422, "BAD_REQUEST", "The body must be a JSON object.")
    return data, None


def create_app(clock: Callable[[], float] = time.monotonic) -> FastAPI:
    app = FastAPI(
        title="Prosthetic hand simulator",
        description=(
            "Simulador de mano protésica de seis actuadores. / Six-actuator prosthetic hand simulator.\n\n"
            "Send the same line the SPP link carries: `{\"command\": \"A320,D180\"}`."
        ),
        version="1.0.0",
    )
    hand = HandSimulator(clock)
    hub = Hub()
    lock = asyncio.Lock()
    app.state.hand = hand
    app.state.hub = hub

    extra = _extra_origins()
    if extra:
        # ES: CORS solo para orígenes declarados explícitamente. Nunca "*".
        # EN: CORS only for explicitly declared origins. Never "*".
        app.add_middleware(CORSMiddleware, allow_origins=extra, allow_methods=["GET", "POST"],
                           allow_headers=["Content-Type"], allow_credentials=False)
    app.add_middleware(OriginGuard, extra_origins=extra)

    @app.post("/api/command", summary="Enviar una línea de comando / Send one command line")
    async def post_command(request: Request):
        data, error = await _read_json(request)
        if error:
            return error
        command = data.get("command")
        if not isinstance(command, str):
            return _reject(422, "BAD_REQUEST", 'The body must be {"command": "<line>"} with a string value.')
        async with lock:
            response, events = hand.handle(command)
            hub.publish(events)
        if response["accepted"]:
            return JSONResponse(response)
        headers = {}
        if "retry_after_ms" in response:
            headers["Retry-After"] = str(max(1, math.ceil(response["retry_after_ms"] / 1000)))
        return JSONResponse(response, status_code=422, headers=headers)

    @app.get("/api/state", summary="Pose actual / Current pose")
    async def get_state():
        return hand.snapshot()

    @app.get("/api/spec", summary="Tablas de la mano / Hand tables")
    async def get_spec():
        return spec.as_dict()

    @app.post("/api/profile", summary="Cambiar perfil de límites / Change limit profile")
    async def post_profile(request: Request):
        data, error = await _read_json(request)
        if error:
            return error
        name = data.get("profile")
        if not isinstance(name, str) or name not in spec.PROFILES:
            return _reject(422, "UNKNOWN_PROFILE",
                           f"'profile' must be one of: {', '.join(spec.PROFILES)}.")
        async with lock:
            response, events = hand.set_profile(name)
            hub.publish(events)
        return response

    @app.websocket("/ws")
    async def ws_endpoint(ws: WebSocket):
        await ws.accept()
        client = Client(ws)
        # ES: Sin await entre el snapshot y el registro: ningún evento se cuela ni se pierde.
        # EN: No await between snapshot and registration: no event slips in or is lost.
        client.queue.put_nowait({"type": "snapshot", "state": hand.snapshot()})
        hub.clients.add(client)
        pump = client.task = asyncio.create_task(client.pump())
        reader = asyncio.create_task(_drain(ws))
        try:
            await asyncio.wait({pump, reader}, return_when=asyncio.FIRST_COMPLETED)
        finally:
            hub.clients.discard(client)
            for task in (pump, reader):
                task.cancel()
            for task in (pump, reader):
                with contextlib.suppress(BaseException):
                    await task
            with contextlib.suppress(Exception):
                await ws.close()

    @app.get("/", include_in_schema=False)
    async def index():
        return FileResponse(STATIC_DIR / "index.html", headers={"Cache-Control": "no-cache"})

    app.mount("/static", RevalidatingStaticFiles(directory=STATIC_DIR), name="static")
    return app


async def _drain(ws: WebSocket) -> None:
    """El navegador no pregunta: se ignora lo que envíe, solo se detecta el cierre.
    The browser does not ask: anything it sends is ignored; only closing matters."""
    try:
        while True:
            await ws.receive_text()
    except (WebSocketDisconnect, RuntimeError):
        return


app = create_app()
