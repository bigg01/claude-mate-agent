"""Tests for _ci_audit_context() — selects GitHub vs GitLab fields based on
the GITHUB_ACTIONS marker env var."""
import pytest

import app


@pytest.fixture(autouse=True)
def clear_ci_env(monkeypatch):
    """Strip all CI env vars so tests start from a known empty baseline."""
    for var in (
        "GITHUB_ACTIONS", "GITHUB_REPOSITORY", "GITHUB_RUN_ID", "GITHUB_JOB",
        "GITHUB_SHA", "GITHUB_REF_NAME", "RUNNER_NAME", "GITHUB_ACTOR",
        "GITHUB_WORKFLOW",
        "CI_PROJECT_PATH", "CI_PIPELINE_ID", "CI_JOB_ID", "CI_COMMIT_SHA",
        "CI_COMMIT_REF_NAME", "CI_RUNNER_ID", "GITLAB_USER_LOGIN",
        "TEAM_MATE_ROLE",
    ):
        monkeypatch.delenv(var, raising=False)


def test_github_branch_when_actions_true(monkeypatch):
    monkeypatch.setenv("GITHUB_ACTIONS", "true")
    monkeypatch.setenv("GITHUB_REPOSITORY", "acme/widgets")
    monkeypatch.setenv("GITHUB_RUN_ID", "12345")
    monkeypatch.setenv("GITHUB_JOB", "build")
    monkeypatch.setenv("GITHUB_SHA", "abc1234")
    monkeypatch.setenv("GITHUB_REF_NAME", "main")
    monkeypatch.setenv("RUNNER_NAME", "ubuntu-latest")
    monkeypatch.setenv("GITHUB_ACTOR", "alice")
    monkeypatch.setenv("GITHUB_WORKFLOW", "CI")
    monkeypatch.setenv("TEAM_MATE_ROLE", "devops")

    ctx = app._ci_audit_context()
    assert ctx["ci_system"] == "github_actions"
    assert ctx["ci_project"] == "acme/widgets"
    assert ctx["ci_run"] == "12345"
    assert ctx["ci_job"] == "build"
    assert ctx["ci_commit"] == "abc1234"
    assert ctx["ci_branch"] == "main"
    assert ctx["ci_runner"] == "ubuntu-latest"
    assert ctx["ci_user"] == "alice"
    assert ctx["ci_workflow"] == "CI"
    assert ctx["teammate_role"] == "devops"


def test_gitlab_branch_when_github_actions_unset():
    # No GITHUB_ACTIONS env var — default to GitLab branch
    ctx = app._ci_audit_context()
    assert ctx["ci_system"] == "gitlab_ci"
    # All GitLab fields default to empty strings when env is empty
    assert ctx["ci_project"] == ""
    assert ctx["ci_workflow"] == ""
    # Role defaults to "unknown" when TEAM_MATE_ROLE is unset
    assert ctx["teammate_role"] == "unknown"


def test_gitlab_branch_populates_fields_from_env(monkeypatch):
    monkeypatch.setenv("CI_PROJECT_PATH", "acme/widgets")
    monkeypatch.setenv("CI_PIPELINE_ID", "999")
    monkeypatch.setenv("CI_JOB_ID", "8")
    monkeypatch.setenv("CI_COMMIT_SHA", "deadbeef")
    monkeypatch.setenv("CI_COMMIT_REF_NAME", "feat/x")
    monkeypatch.setenv("CI_RUNNER_ID", "42")
    monkeypatch.setenv("GITLAB_USER_LOGIN", "bob")
    monkeypatch.setenv("TEAM_MATE_ROLE", "sre")

    ctx = app._ci_audit_context()
    assert ctx["ci_system"] == "gitlab_ci"
    assert ctx["ci_project"] == "acme/widgets"
    assert ctx["ci_run"] == "999"
    assert ctx["ci_job"] == "8"
    assert ctx["ci_commit"] == "deadbeef"
    assert ctx["ci_branch"] == "feat/x"
    assert ctx["ci_runner"] == "42"
    assert ctx["ci_user"] == "bob"
    assert ctx["teammate_role"] == "sre"


def test_github_actions_false_falls_through_to_gitlab(monkeypatch):
    # Only the literal string "true" triggers the GitHub branch
    monkeypatch.setenv("GITHUB_ACTIONS", "false")
    ctx = app._ci_audit_context()
    assert ctx["ci_system"] == "gitlab_ci"
