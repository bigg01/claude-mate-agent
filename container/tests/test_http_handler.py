"""HTTP handler tests — spin up a real ThreadingHTTPServer on an ephemeral
port and hit /healthz, /readyz, /metrics, and an unknown path via urllib."""
import json
import threading
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer

import pytest

import app


@pytest.fixture
def server(monkeypatch):
    monkeypatch.setattr(app, "SHUTTING_DOWN", False)
    monkeypatch.setattr(app, "REQUEST_COUNT", 0)
    srv = ThreadingHTTPServer(("127.0.0.1", 0), app.Handler)
    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{srv.server_address[1]}"
    yield base
    srv.shutdown()
    srv.server_close()


def _get(base, path):
    return urllib.request.urlopen(f"{base}{path}", timeout=2)


def test_healthz_returns_ok(server):
    resp = _get(server, "/healthz")
    assert resp.status == 200
    body = json.loads(resp.read())
    assert body == {"status": "ok"}


def test_livez_aliases_healthz(server):
    resp = _get(server, "/livez")
    assert resp.status == 200
    assert json.loads(resp.read()) == {"status": "ok"}


def test_readyz_returns_200_when_not_shutting_down(server):
    resp = _get(server, "/readyz")
    assert resp.status == 200
    assert json.loads(resp.read()) == {"ready": True}


def test_readyz_returns_503_when_shutting_down(server, monkeypatch):
    monkeypatch.setattr(app, "SHUTTING_DOWN", True)
    with pytest.raises(urllib.error.HTTPError) as exc:
        _get(server, "/readyz")
    assert exc.value.code == 503
    assert json.loads(exc.value.read()) == {"ready": False}


def test_unknown_path_returns_404(server):
    with pytest.raises(urllib.error.HTTPError) as exc:
        _get(server, "/nope")
    assert exc.value.code == 404
    assert json.loads(exc.value.read()) == {"error": "not_found"}


def test_metrics_returns_prometheus_exposition(server, monkeypatch):
    monkeypatch.setenv("POD_NAMESPACE", "ns-x")
    monkeypatch.setenv("POD_NAME", "pod-x")
    monkeypatch.setenv("TEAM_MATE_ROLE", "sre")
    resp = _get(server, "/metrics")
    assert resp.status == 200
    assert resp.headers["Content-Type"].startswith("text/plain")
    body = resp.read().decode("utf-8")
    # Required metrics are present with HELP+TYPE headers
    for metric in (
        "claude_mate_agent_up",
        "claude_mate_agent_start_timestamp_seconds",
        "claude_mate_agent_uptime_seconds",
        "claude_mate_agent_http_requests_total",
        "claude_mate_agent_task_executions_total",
        "claude_mate_agent_task_cost_usd_total",
        "claude_mate_agent_task_last_duration_seconds",
    ):
        assert f"# HELP {metric}" in body
        assert f"# TYPE {metric}" in body
    # Labels propagate from env vars
    assert 'namespace="ns-x"' in body
    assert 'pod="pod-x"' in body
    assert 'role="sre"' in body
    # All three task-result series are exposed (ok / error / timeout)
    for result in ("ok", "error", "timeout"):
        assert f'result="{result}"' in body


def test_request_counter_increments(server):
    _get(server, "/healthz")
    _get(server, "/healthz")
    _get(server, "/healthz")
    # Three /healthz calls + one /metrics call = 4
    body = _get(server, "/metrics").read().decode("utf-8")
    # The counter line: claude_mate_agent_http_requests_total{...} N
    for line in body.splitlines():
        if line.startswith("claude_mate_agent_http_requests_total{"):
            count = int(line.rsplit(" ", 1)[1])
            assert count == 4
            return
    pytest.fail("http_requests_total metric not found in /metrics output")
