"""Tests for persona loading and Claude CLI command construction."""
import os
from pathlib import Path

import pytest

import app


@pytest.fixture
def personas_dir(tmp_path, monkeypatch):
    """Point PERSONAS_DIR at a fresh tmp directory for each test."""
    monkeypatch.setattr(app, "PERSONAS_DIR", str(tmp_path))
    return tmp_path


def test_load_persona_returns_file_content(personas_dir):
    (personas_dir / "architect.md").write_text("You are an architect.\n")
    assert app._load_persona_prompt("architect") == "You are an architect."


def test_load_persona_returns_none_when_missing(personas_dir):
    assert app._load_persona_prompt("nonexistent") is None


def test_load_persona_returns_none_for_empty_file(personas_dir):
    (personas_dir / "empty.md").write_text("   \n  \n")
    assert app._load_persona_prompt("empty") is None


def test_load_persona_strips_whitespace(personas_dir):
    (personas_dir / "sre.md").write_text("\n\n  Reliable.  \n\n")
    assert app._load_persona_prompt("sre") == "Reliable."


def test_build_cmd_includes_base_flags(personas_dir):
    cmd = app._build_claude_cmd("hello", "operations")
    assert cmd[0] == "claude"
    assert "--print" in cmd
    assert "--output-format" in cmd
    assert "json" in cmd
    # operations has no persona file and no tool restriction
    assert "--system-prompt" not in cmd
    assert "--allowedTools" not in cmd
    # Task is the final argument
    assert cmd[-1] == "hello"


def test_build_cmd_injects_system_prompt(personas_dir):
    (personas_dir / "architect.md").write_text("You are an architect.")
    cmd = app._build_claude_cmd("review", "architect")
    idx = cmd.index("--system-prompt")
    assert cmd[idx + 1] == "You are an architect."


def test_build_cmd_injects_allowed_tools(personas_dir):
    cmd = app._build_claude_cmd("scan", "security")
    idx = cmd.index("--allowedTools")
    # Security persona is read-only + Bash
    tools = cmd[idx + 1].split(",")
    assert "Read" in tools
    assert "Bash" in tools
    assert "Write" not in tools
    assert "Edit" not in tools


def test_build_cmd_operations_has_no_tool_restriction(personas_dir):
    cmd = app._build_claude_cmd("any", "operations")
    assert "--allowedTools" not in cmd


def test_build_cmd_unknown_role_has_no_tool_restriction(personas_dir):
    cmd = app._build_claude_cmd("any", "unknown-role")
    assert "--allowedTools" not in cmd


def test_persona_tools_table_covers_documented_roles():
    expected = {"architect", "software-architect", "security", "devops", "sre", "operations"}
    assert set(app._PERSONA_TOOLS.keys()) == expected


def test_software_architect_persona_has_write_access():
    # Code-level architect needs Edit to apply refactorings and Write to author ADRs.
    tools = app._PERSONA_TOOLS["software-architect"].split(",")
    for required in ("Read", "Write", "Edit"):
        assert required in tools


def test_security_persona_is_read_only():
    tools = app._PERSONA_TOOLS["security"].split(",")
    for forbidden in ("Write", "Edit", "MultilineEdit"):
        assert forbidden not in tools
