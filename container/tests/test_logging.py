"""Tests for the structured-JSON `log()` helper."""
import io
import json

import app


def test_log_writes_valid_json(monkeypatch):
    buf = io.StringIO()
    monkeypatch.setattr("sys.stdout", buf)
    app.log("INFO", "test_event", key="value")
    line = buf.getvalue().strip()
    record = json.loads(line)
    assert record["severity"] == "INFO"
    assert record["message"] == "test_event"
    assert record["key"] == "value"


def test_log_emits_error_to_stderr(monkeypatch):
    out_buf, err_buf = io.StringIO(), io.StringIO()
    monkeypatch.setattr("sys.stdout", out_buf)
    monkeypatch.setattr("sys.stderr", err_buf)
    app.log("ERROR", "bad_thing", reason="x")
    assert out_buf.getvalue() == ""
    assert "bad_thing" in err_buf.getvalue()


def test_log_includes_pod_identifiers(monkeypatch):
    monkeypatch.setenv("POD_NAMESPACE", "ns-test")
    monkeypatch.setenv("POD_NAME", "agent-abc")
    buf = io.StringIO()
    monkeypatch.setattr("sys.stdout", buf)
    app.log("INFO", "msg")
    record = json.loads(buf.getvalue().strip())
    assert record["namespace"] == "ns-test"
    assert record["pod"] == "agent-abc"
