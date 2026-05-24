#!/usr/bin/env bash
# Emit a DORA-metric event to a Prometheus Pushgateway.
#
# Usage:
#   dora-emit.sh deploy   --env <name> --status ok|failed [--lead-time-seconds N] [--commit <sha>]
#   dora-emit.sh failure  --env <name> --service <name>   [--commit <sha>]
#   dora-emit.sh restore  --env <name> --service <name>   --restore-seconds N
#
# Env vars:
#   PUSHGATEWAY_URL    Pushgateway base URL. Default: http://prometheus-pushgateway:9091
#   CI_SYSTEM          Free-form ("github_actions", "gitlab_ci", "local")
#
# Metrics emitted:
#   dora_deployments_total{env,status,ci_system,commit}
#   dora_lead_time_seconds{env,commit,ci_system}                      (deploy only)
#   dora_change_failures_total{env,service,ci_system,commit}          (failure only)
#   dora_restore_seconds{env,service,ci_system}                       (restore only)
set -euo pipefail

PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://prometheus-pushgateway:9091}"
CI_SYSTEM="${CI_SYSTEM:-local}"

EVENT="${1:-}"; shift || true
if [[ -z "$EVENT" ]]; then
  echo "ERROR: event type required (deploy|failure|restore)" >&2
  exit 2
fi

ENV_NAME=""
STATUS=""
SERVICE=""
COMMIT="${GITHUB_SHA:-${CI_COMMIT_SHA:-}}"
LEAD_TIME_SECONDS=""
RESTORE_SECONDS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)                 ENV_NAME="$2"; shift 2 ;;
    --status)              STATUS="$2"; shift 2 ;;
    --service)             SERVICE="$2"; shift 2 ;;
    --commit)              COMMIT="$2"; shift 2 ;;
    --lead-time-seconds)   LEAD_TIME_SECONDS="$2"; shift 2 ;;
    --restore-seconds)     RESTORE_SECONDS="$2"; shift 2 ;;
    *) echo "ERROR: unknown flag $1" >&2; exit 2 ;;
  esac
done

[[ -z "$ENV_NAME" ]] && { echo "ERROR: --env required" >&2; exit 2; }

# Slug-safe values for use in Pushgateway grouping path
slug() { printf '%s' "$1" | tr -c '[:alnum:]_-' '_'; }
SAFE_ENV=$(slug "$ENV_NAME")
SAFE_COMMIT=$(slug "${COMMIT:-unknown}")
SAFE_SERVICE=$(slug "${SERVICE:-claude-mate-agent}")
GROUP="job/dora/env/${SAFE_ENV}/commit/${SAFE_COMMIT}/service/${SAFE_SERVICE}"

emit() {
  local body="$1"
  curl --fail --silent --show-error \
    --request POST \
    --data-binary "$body" \
    "${PUSHGATEWAY_URL}/metrics/${GROUP}" >&2
}

case "$EVENT" in
  deploy)
    [[ -z "$STATUS" ]] && { echo "ERROR: --status required for deploy" >&2; exit 2; }
    body=$(cat <<EOF
# TYPE dora_deployments_total counter
dora_deployments_total{env="${ENV_NAME}",status="${STATUS}",ci_system="${CI_SYSTEM}",commit="${COMMIT}"} 1
EOF
)
    if [[ -n "$LEAD_TIME_SECONDS" ]]; then
      body+=$'\n'
      body+=$(cat <<EOF
# TYPE dora_lead_time_seconds gauge
dora_lead_time_seconds{env="${ENV_NAME}",commit="${COMMIT}",ci_system="${CI_SYSTEM}"} ${LEAD_TIME_SECONDS}
EOF
)
    fi
    emit "$body"
    echo "Emitted deploy event: env=$ENV_NAME status=$STATUS lead=${LEAD_TIME_SECONDS:-n/a}s"
    ;;

  failure)
    body=$(cat <<EOF
# TYPE dora_change_failures_total counter
dora_change_failures_total{env="${ENV_NAME}",service="${SERVICE:-claude-mate-agent}",ci_system="${CI_SYSTEM}",commit="${COMMIT}"} 1
EOF
)
    emit "$body"
    echo "Emitted change-failure event: env=$ENV_NAME service=${SERVICE:-claude-mate-agent}"
    ;;

  restore)
    [[ -z "$RESTORE_SECONDS" ]] && { echo "ERROR: --restore-seconds required for restore" >&2; exit 2; }
    body=$(cat <<EOF
# TYPE dora_restore_seconds gauge
dora_restore_seconds{env="${ENV_NAME}",service="${SERVICE:-claude-mate-agent}",ci_system="${CI_SYSTEM}"} ${RESTORE_SECONDS}
EOF
)
    emit "$body"
    echo "Emitted restore event: env=$ENV_NAME restore=${RESTORE_SECONDS}s"
    ;;

  *)
    echo "ERROR: unknown event type '$EVENT' (use deploy|failure|restore)" >&2
    exit 2
    ;;
esac
