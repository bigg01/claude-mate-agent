"""Tests for the guardrails module."""
import os

import pytest

import guardrails


@pytest.fixture(autouse=True)
def _reset_cost_window():
    """Each test starts with an empty cost ledger."""
    guardrails._COST_WINDOW = guardrails._CostWindow()
    yield


# ── Master switch + helpers ──────────────────────────────────────────────────

def test_enabled_default_false(monkeypatch):
    monkeypatch.delenv("GUARDRAILS_ENABLED", raising=False)
    assert guardrails.enabled() is False


def test_enabled_true_only_when_string_matches(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_ENABLED", "true")
    assert guardrails.enabled() is True
    monkeypatch.setenv("GUARDRAILS_ENABLED", "TRUE")
    assert guardrails.enabled() is True
    monkeypatch.setenv("GUARDRAILS_ENABLED", "1")
    assert guardrails.enabled() is False  # explicit string match


def test_compile_patterns_ignores_invalid_regex():
    out = guardrails._compile_patterns([], ["[unclosed"])
    assert out == []


def test_compile_patterns_includes_extras():
    out = guardrails._compile_patterns([], ["foo"])
    assert len(out) == 1
    assert out[0].pattern == "foo"


# ── Cost guardrail ───────────────────────────────────────────────────────────

def test_cost_disabled_always_allows(monkeypatch):
    monkeypatch.delenv("GUARDRAILS_COST_ENABLED", raising=False)
    ok, _ = guardrails.check_cost_budget()
    assert ok is True


def test_cost_enabled_no_cap_allows(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_COST_ENABLED", "true")
    monkeypatch.delenv("GUARDRAILS_COST_MAX_USD_PER_HOUR", raising=False)
    ok, _ = guardrails.check_cost_budget()
    assert ok is True


def test_cost_blocks_when_ledger_at_cap(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_COST_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_COST_MAX_USD_PER_HOUR", "1.00")
    guardrails._COST_WINDOW.add(1.50)
    ok, reason = guardrails.check_cost_budget()
    assert ok is False
    assert "hourly cost cap" in reason


def test_cost_record_emits_per_task_event(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_COST_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_COST_MAX_USD_PER_TASK", "0.50")
    events = guardrails.record_cost(0.75)
    assert "per_task_exceeded" in events
    assert events["per_task_exceeded"]["limit_usd"] == 0.50
    assert events["per_task_exceeded"]["actual_usd"] == 0.75


def test_cost_record_emits_hourly_event(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_COST_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_COST_MAX_USD_PER_HOUR", "1.00")
    events = guardrails.record_cost(1.10)
    assert "hourly_exceeded" in events


def test_cost_record_no_events_within_limits(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_COST_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_COST_MAX_USD_PER_TASK", "10.00")
    monkeypatch.setenv("GUARDRAILS_COST_MAX_USD_PER_HOUR", "100.00")
    events = guardrails.record_cost(0.05)
    assert events == {}


def test_cost_ledger_prunes_old_entries():
    win = guardrails._CostWindow()
    import time as _t
    now = _t.time()
    win.add(0.10, now=now - 4000)  # > 1 h ago
    win.add(0.20, now=now - 100)    # < 1 h ago
    total = win.total(now=now)
    assert total == pytest.approx(0.20)


# ── Input / output scrubbing ─────────────────────────────────────────────────

def test_input_disabled_returns_unchanged(monkeypatch):
    monkeypatch.delenv("GUARDRAILS_INPUT_ENABLED", raising=False)
    text, hits, blocked = guardrails.scrub_input("sk-ant-abcdefghijklmnopqrstuv")
    assert text == "sk-ant-abcdefghijklmnopqrstuv"
    assert hits == []
    assert blocked is False


def test_input_redacts_anthropic_key(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_INPUT_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_INPUT_PATTERNS", "api-keys")
    monkeypatch.setenv("GUARDRAILS_INPUT_ACTION", "redact")
    text, hits, blocked = guardrails.scrub_input(
        "the key is sk-ant-abcdefghijklmnopqrstuv1234 and that's it"
    )
    assert "sk-ant-" not in text
    assert "[REDACTED]" in text
    assert len(hits) == 1
    assert blocked is False


def test_input_blocks_on_aws_key(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_INPUT_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_INPUT_PATTERNS", "api-keys")
    monkeypatch.setenv("GUARDRAILS_INPUT_ACTION", "block")
    _, hits, blocked = guardrails.scrub_input("creds: AKIAIOSFODNN7EXAMPLE")
    assert blocked is True
    assert hits


def test_input_extra_patterns_apply(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_INPUT_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_INPUT_PATTERNS", "")
    monkeypatch.setenv("GUARDRAILS_INPUT_EXTRA_PATTERNS", r"secret-[a-z]+")
    monkeypatch.setenv("GUARDRAILS_INPUT_ACTION", "redact")
    text, hits, _ = guardrails.scrub_input("here is secret-token to remove")
    assert "secret-token" not in text
    assert hits == [r"secret-[a-z]+"]


def test_input_pii_ssn(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_INPUT_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_INPUT_PATTERNS", "pii")
    monkeypatch.setenv("GUARDRAILS_INPUT_ACTION", "redact")
    text, hits, _ = guardrails.scrub_input("My SSN is 123-45-6789 thanks")
    assert "123-45-6789" not in text
    assert len(hits) == 1


def test_input_no_match_returns_unchanged(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_INPUT_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_INPUT_PATTERNS", "api-keys")
    text, hits, _ = guardrails.scrub_input("just a normal sentence")
    assert text == "just a normal sentence"
    assert hits == []


def test_output_scrubbing_uses_separate_env(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_OUTPUT_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_OUTPUT_PATTERNS", "api-keys")
    text, hits, _ = guardrails.scrub_output(
        "leaked sk-ant-abcdefghijklmnopqrstuv1234 in response"
    )
    assert "sk-ant-" not in text
    assert len(hits) == 1


# ── Intent guardrail ─────────────────────────────────────────────────────────

def test_intent_disabled_allows_everything(monkeypatch):
    monkeypatch.delenv("GUARDRAILS_INTENT_ENABLED", raising=False)
    ok, hits = guardrails.check_intent("deploy to prod", "security")
    assert ok is True
    assert hits == []


def test_intent_no_deny_for_role_allows(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_INTENT_ENABLED", "true")
    monkeypatch.delenv("GUARDRAILS_INTENT_DENY_SECURITY", raising=False)
    ok, _ = guardrails.check_intent("review the auth code", "security")
    assert ok is True


def test_intent_block_on_match(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_INTENT_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_INTENT_DENY_SECURITY", r"\bdeploy\b,\bdestroy\b")
    monkeypatch.setenv("GUARDRAILS_INTENT_ACTION", "block")
    ok, hits = guardrails.check_intent("please DEPLOY this", "security")
    assert ok is False
    assert hits


def test_intent_warn_mode_returns_allowed_with_hits(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_INTENT_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_INTENT_DENY_SECURITY", r"\bdeploy\b")
    monkeypatch.setenv("GUARDRAILS_INTENT_ACTION", "warn")
    ok, hits = guardrails.check_intent("deploy now", "security")
    assert ok is True
    assert hits


def test_intent_invalid_regex_skipped(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_INTENT_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_INTENT_DENY_OPERATIONS", "[unclosed,validpat")
    ok, hits = guardrails.check_intent("validpat is here", "operations")
    # Only the valid pattern fires; invalid one is silently skipped
    assert hits == ["validpat"]


# ── Workspace guardrail ──────────────────────────────────────────────────────

def test_workspace_disabled_writes_nothing(tmp_path, monkeypatch):
    monkeypatch.delenv("GUARDRAILS_WORKSPACE_ENABLED", raising=False)
    n = guardrails.write_claudeignore(str(tmp_path))
    assert n == 0
    assert not (tmp_path / ".claudeignore").exists()


def test_workspace_writes_file_with_patterns(tmp_path, monkeypatch):
    monkeypatch.setenv("GUARDRAILS_WORKSPACE_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_WORKSPACE_IGNORE_PATTERNS",
                       "**/.env,**/secrets/**,**/*.pem")
    n = guardrails.write_claudeignore(str(tmp_path))
    assert n == 3
    content = (tmp_path / ".claudeignore").read_text()
    assert "**/.env" in content
    assert "**/secrets/**" in content
    assert "**/*.pem" in content
    assert content.startswith("# Auto-generated")


def test_workspace_empty_patterns_no_op(tmp_path, monkeypatch):
    monkeypatch.setenv("GUARDRAILS_WORKSPACE_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_WORKSPACE_IGNORE_PATTERNS", "")
    n = guardrails.write_claudeignore(str(tmp_path))
    assert n == 0
    assert not (tmp_path / ".claudeignore").exists()


def test_workspace_unwritable_dir_returns_zero(monkeypatch):
    monkeypatch.setenv("GUARDRAILS_WORKSPACE_ENABLED", "true")
    monkeypatch.setenv("GUARDRAILS_WORKSPACE_IGNORE_PATTERNS", "**/.env")
    n = guardrails.write_claudeignore("/nonexistent-path-for-test-xyz")
    assert n == 0
