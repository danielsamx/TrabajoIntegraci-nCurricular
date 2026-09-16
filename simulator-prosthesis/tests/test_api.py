"""Pruebas de la API, el movimiento y el WebSocket con un reloj falso.
API, motion and WebSocket tests with a fake clock."""

import pytest
from fastapi.testclient import TestClient

from app import spec
from app.main import create_app


class FakeClock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t

    def advance(self, ms):
        self.t += ms / 1000


@pytest.fixture
def clock():
    return FakeClock()


@pytest.fixture
def client(clock):
    with TestClient(create_app(clock)) as c:
        yield c


def send(client, clock, line, wait_ms=60):
    clock.advance(wait_ms)
    return client.post("/api/command", json={"command": line})


def test_example_from_the_brief(client, clock):
    r = send(client, clock, "A320,D180")
    assert r.status_code == 200
    assert r.json() == {
        "accepted": True,
        "frame": "A320,D180",
        "pose": {
            "actuator_positions": {"A": 320, "D": 180},
            "actuator_normalised": {"A": 0.5333, "D": 0.3273},
            "duration_ms": 356,
        },
    }


def test_out_of_range_is_rejected_not_clamped(client, clock):
    r = send(client, clock, "A900")
    assert r.status_code == 422
    assert r.json() == {
        "accepted": False,
        "stage": "range",
        "code": "OUT_OF_RANGE",
        "message": "A=900 is outside 0-600 for profile TABLE_5_V3.",
    }
    state = client.get("/api/state").json()
    assert state["actuator_positions"]["A"] == 0
    assert state["last_command"]["accepted"] is False


def test_rejection_leaves_hand_untouched_mid_motion(client, clock):
    send(client, clock, "A600")
    clock.advance(300)
    before = client.get("/api/state").json()
    r = client.post("/api/command", json={"command": "A320,B999"})
    assert r.status_code == 422
    after = client.get("/api/state").json()
    assert after["targets"]["A"]["position"] == 600
    assert after["actuator_normalised"] == before["actuator_normalised"]


def test_close_gesture_vs_middle_actuator(client, clock):
    r = send(client, clock, "C").json()
    assert r["gesture"]["name"] == "CLOSE"
    assert r["pose"]["actuator_positions"] == {"A": 600, "B": 550, "C": 600, "D": 550, "E": 130, "F": 400}
    assert r["pose"]["duration_ms"] == 900
    r = send(client, clock, "C400", wait_ms=1000).json()
    assert r["pose"]["actuator_positions"] == {"C": 400}


def test_duration_clamped(client, clock):
    assert send(client, clock, "A1").json()["pose"]["duration_ms"] == 120
    # 0 -> 600 y luego 600 -> 0 no pasa de 5000 / never above 5000
    assert spec.MAX_DURATION_MS == 5000


def test_duration_uses_current_position(client, clock):
    send(client, clock, "A600")  # 667 ms
    clock.advance(10_000)
    assert send(client, clock, "A300").json()["pose"]["duration_ms"] == 333


def test_timing_rejects_fast_commands_but_not_stop(client, clock):
    assert send(client, clock, "A100").status_code == 200
    r = send(client, clock, "A200", wait_ms=20)
    assert r.status_code == 422
    assert r.json()["stage"] == "timing" and r.json()["code"] == "TOO_SOON"
    assert r.json()["retry_after_ms"] == 30
    assert "Retry-After" in r.headers
    assert send(client, clock, "S", wait_ms=1).status_code == 200


def test_protocol_error_wins_over_timing(client, clock):
    send(client, clock, "A100")
    r = send(client, clock, "a100", wait_ms=1)
    assert r.json()["stage"] == "protocol"


def test_stop_freezes_mid_trajectory(client, clock):
    send(client, clock, "A600")  # 667 ms
    clock.advance(333)
    r = send(client, clock, "S", wait_ms=0).json()
    frozen = r["pose"]["actuator_normalised"]["A"]
    assert 0.3 < frozen < 0.7
    clock.advance(5000)
    state = client.get("/api/state").json()
    assert state["moving"] is False
    assert state["actuator_normalised"]["A"] == frozen  # no vuelve a abierto / does not reopen


def test_retarget_from_current_pose(client, clock):
    send(client, clock, "A600")
    clock.advance(333)
    mid = client.get("/api/state").json()["actuator_positions"]["A"]
    r = send(client, clock, "A0", wait_ms=0).json()
    assert r["pose"]["duration_ms"] == round(mid / 900 * 1000)
    state = client.get("/api/state").json()
    assert state["actuator_positions"]["A"] == mid
    assert state["targets"]["A"]["position"] == 0


def test_profile_switch_does_not_move_and_reports(client, clock):
    send(client, clock, "A500")
    clock.advance(2000)
    r = client.post("/api/profile", json={"profile": "INTERSECTION"}).json()
    assert r["moved"] is False
    assert [o["actuator"] for o in r["out_of_envelope"]] == ["A"]
    state = client.get("/api/state").json()
    assert state["actuator_positions"]["A"] == 500
    assert state["profile"] == "INTERSECTION"
    assert send(client, clock, "A500").json()["code"] == "OUT_OF_RANGE"


def test_unknown_profile(client):
    r = client.post("/api/profile", json={"profile": "NOPE"})
    assert r.status_code == 422 and r.json()["code"] == "UNKNOWN_PROFILE"


def test_calibrate_moves_nothing_and_shifts_zero(client, clock):
    send(client, clock, "A300")
    clock.advance(2000)
    before = client.get("/api/state").json()["actuator_normalised"]
    r = send(client, clock, "X").json()
    assert r["action"] == "CALIBRATE"
    state = client.get("/api/state").json()
    assert state["actuator_normalised"] == before
    assert state["actuator_positions"]["A"] == 0
    assert state["calibration_offset"]["A"] == 300
    assert state["calibrated"] is True
    # 300 (encóder) + 300 (offset) = 600: todavía dentro / still inside
    assert send(client, clock, "A300").status_code == 200
    r = send(client, clock, "A301")
    assert r.json()["stage"] == "kinematics"


def test_calibrate_while_moving_rejected(client, clock):
    send(client, clock, "A600")
    r = send(client, clock, "X", wait_ms=100)
    assert r.json()["code"] == "CALIBRATE_WHILE_MOVING"


def test_init_shields_moves_nothing(client, clock):
    r = send(client, clock, "I")
    assert r.json() == {"accepted": True, "frame": "I", "action": "INIT_SHIELDS"}
    assert client.get("/api/state").json()["moving"] is False


def test_request_errors(client):
    assert client.post("/api/command", content="A1", headers={"content-type": "text/plain"}).status_code == 415
    assert client.post("/api/command", json={"cmd": "A1"}).status_code == 422
    assert client.post("/api/command", json={"command": 5}).status_code == 422
    assert client.post("/api/command", content="{", headers={"content-type": "application/json"}).status_code == 400


def test_origin_guard(client, clock):
    ok = client.post("/api/command", json={"command": "O"}, headers={"origin": "http://testserver"})
    assert ok.status_code == 200
    bad = client.post("/api/command", json={"command": "O"}, headers={"origin": "http://evil.example"})
    assert bad.status_code == 403
    assert "access-control-allow-origin" not in bad.headers


def test_spec_endpoint(client):
    s = client.get("/api/spec").json()
    assert len(s["joints"]) == 15
    assert [j["id"] for j in s["joints"] if j["finger"] == "thumb"] == ["D0", "D1_P", "D1_D"]
    assert next(j for j in s["joints"] if j["id"] == "D0")["axis"] == "Y"
    assert set(s["gestures"]) == set("OCPRWYLMHUG")


def test_index_served(client):
    r = client.get("/")
    assert r.status_code == 200 and "three" in r.text.lower()
    assert r.headers["cache-control"] == "no-cache"


def test_static_files_are_revalidated(client):
    # Evita mezclar HTML nuevo con JS/CSS viejo tras actualizar.
    # Avoids mixing new HTML with stale JS/CSS after an update.
    for path in ("/static/js/app.js", "/static/js/hand.js", "/static/js/sdf.js", "/static/css/style.css"):
        r = client.get(path)
        assert r.status_code == 200, path
        assert r.headers["cache-control"] == "no-cache", path
        etag = r.headers["etag"]
        again = client.get(path, headers={"if-none-match": etag})
        assert again.status_code == 304, path


def test_websocket_push(client, clock):
    with client.websocket_connect("/ws") as ws:
        assert ws.receive_json()["type"] == "snapshot"
        send(client, clock, "A320,D180")
        pose = ws.receive_json()
        assert pose["type"] == "pose"
        assert pose["target"] == {"A": 0.5333, "D": 0.3273}
        assert pose["duration_ms"] == 356
        assert ws.receive_json()["type"] == "command"
        send(client, clock, "S")
        assert ws.receive_json()["type"] == "stop"
        assert ws.receive_json()["type"] == "command"
        send(client, clock, "X", wait_ms=1000)
        assert ws.receive_json()["type"] == "calibrated"
        assert ws.receive_json()["type"] == "command"
        send(client, clock, "A9999")
        msg = ws.receive_json()
        assert msg["type"] == "command" and msg["accepted"] is False


def test_websocket_foreign_origin_refused(client):
    from starlette.websockets import WebSocketDisconnect

    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ws", headers={"origin": "http://evil.example"}) as ws:
            ws.receive_json()
