"""Pruebas del parser (etapas protocol y exclusivity).
Parser tests (protocol and exclusivity stages)."""

import pytest

from app.protocol import Rejection, parse


def reject(line):
    with pytest.raises(Rejection) as exc:
        parse(line)
    return exc.value


def test_c_alone_is_close_gesture():
    cmd = parse("C")
    assert cmd.kind == "gesture" and cmd.letter == "C"


def test_c_with_suffix_is_middle_actuator():
    cmd = parse("C400")
    assert cmd.kind == "positions" and cmd.positions == {"C": 400}


def test_positions():
    assert parse("A320,B120,E45").positions == {"A": 320, "B": 120, "E": 45}


def test_terminator_is_dropped():
    cmd = parse("A320,D180\n")
    assert cmd.frame == "A320,D180" and cmd.positions == {"A": 320, "D": 180}


@pytest.mark.parametrize("line", ["a320", "A 320", "A-5", "A3.5", "A320;B1", "A320,\n", "A²"])
def test_malformed_or_empty_tokens(line):
    r = reject(line)
    assert r.stage == "protocol"
    assert r.code in {"MALFORMED_TOKEN", "EMPTY_TOKEN"}


def test_double_terminator_rejected():
    assert reject("A320\n\n").stage == "protocol"


def test_empty():
    assert reject("").code == "EMPTY_COMMAND"
    assert reject("\n").code == "EMPTY_COMMAND"


def test_line_too_long():
    assert reject("A" + "0" * 128).code == "LINE_TOO_LONG"
    parse("A" + "0" * 127)  # 128 exactos / exactly 128


def test_missing_position():
    assert reject("A").code == "MISSING_POSITION"
    assert reject("A320,D").code == "MISSING_POSITION"


def test_suffix_on_gesture_or_special():
    assert reject("P20").code == "UNEXPECTED_POSITION"
    assert reject("S1").code == "UNEXPECTED_POSITION"


def test_unknown_letter():
    assert reject("Z").code == "UNKNOWN_LETTER"
    assert reject("Q10").code == "UNKNOWN_LETTER"


def test_duplicate_is_error_not_last_wins():
    assert reject("A320,A100").code == "DUPLICATE_LETTER"
    assert reject("C,C400").code == "DUPLICATE_LETTER"


def test_too_many_position_tokens():
    assert reject("A1,B1,C1,D1,E1,F1,A2").code == "TOO_MANY_TOKENS"
    parse("A1,B1,C1,D1,E1,F1")


@pytest.mark.parametrize("line", ["S,A320", "A320,S", "X,I", "I,O"])
def test_specials_are_exclusive(line):
    r = reject(line)
    assert (r.stage, r.code) == ("exclusivity", "EXCLUSIVE_COMMAND")


@pytest.mark.parametrize("line", ["P,A320", "O,C", "A100,G"])
def test_gestures_are_alone(line):
    r = reject(line)
    assert (r.stage, r.code) == ("exclusivity", "GESTURE_NOT_ALONE")


@pytest.mark.parametrize("letter", list("SXI"))
def test_specials_alone_ok(letter):
    cmd = parse(letter)
    assert cmd.kind == "special" and cmd.letter == letter
