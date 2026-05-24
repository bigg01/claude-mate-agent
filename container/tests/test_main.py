"""Tests for the main() entry point — argparse + dispatch to serve/run_once."""
import pytest

import app


def test_main_serve_path(monkeypatch):
    called = []
    monkeypatch.setattr(app, "serve", lambda: called.append("serve"))
    monkeypatch.setattr("sys.argv", ["agent"])
    rc = app.main()
    assert rc == 0
    assert called == ["serve"]


def test_main_once_path_success(monkeypatch):
    called = []
    monkeypatch.setattr(app, "run_once", lambda: called.append("run_once"))
    monkeypatch.setattr("sys.argv", ["agent", "--once"])
    rc = app.main()
    assert rc == 0
    assert called == ["run_once"]


def test_main_once_path_failure_returns_1(monkeypatch):
    def boom():
        raise RuntimeError("task failed")
    monkeypatch.setattr(app, "run_once", boom)
    monkeypatch.setattr("sys.argv", ["agent", "--once"])
    assert app.main() == 1


def test_main_help_exits_cleanly(monkeypatch):
    monkeypatch.setattr("sys.argv", ["agent", "--help"])
    with pytest.raises(SystemExit) as exc:
        app.main()
    assert exc.value.code == 0
