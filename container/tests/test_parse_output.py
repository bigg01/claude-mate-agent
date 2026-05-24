"""Tests for _parse_claude_output() — extracts cost and duration from the
Claude CLI JSON response."""
import json

import app


def test_parses_valid_response():
    payload = json.dumps({"cost_usd": 0.1234, "duration_ms": 4567})
    cost, duration = app._parse_claude_output(payload)
    assert cost == 0.1234
    assert duration == 4567


def test_uses_total_cost_usd_fallback():
    payload = json.dumps({"total_cost_usd": 0.99, "duration_ms": 100})
    cost, _ = app._parse_claude_output(payload)
    assert cost == 0.99


def test_prefers_cost_usd_over_total():
    payload = json.dumps(
        {"cost_usd": 0.5, "total_cost_usd": 0.9, "duration_ms": 0}
    )
    cost, _ = app._parse_claude_output(payload)
    assert cost == 0.5


def test_empty_stdout_returns_zeros():
    assert app._parse_claude_output("") == (0.0, 0)
    assert app._parse_claude_output(None) == (0.0, 0)


def test_invalid_json_returns_zeros():
    assert app._parse_claude_output("not json at all") == (0.0, 0)


def test_missing_fields_returns_zeros():
    assert app._parse_claude_output(json.dumps({})) == (0.0, 0)


def test_handles_whitespace_around_payload():
    payload = "\n  " + json.dumps({"cost_usd": 1.0, "duration_ms": 50}) + "  \n"
    cost, duration = app._parse_claude_output(payload)
    assert cost == 1.0
    assert duration == 50


def test_handles_non_numeric_cost_gracefully():
    payload = json.dumps({"cost_usd": "expensive", "duration_ms": 100})
    cost, duration = app._parse_claude_output(payload)
    assert cost == 0.0
    assert duration == 0
