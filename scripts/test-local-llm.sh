#!/usr/bin/env bash
# Smoke-test the local-llm compose stack (agent + ollama + litellm).
#
# Usage:
#   scripts/test-local-llm.sh             # full test: connectivity + tiny-model e2e
#   scripts/test-local-llm.sh --quick     # connectivity only, skips ~640MB model pull
#   scripts/test-local-llm.sh --model X   # use a specific Ollama model (default: tinyllama)
#
# Exit codes:
#   0  all checks passed
#   1  a check failed (look at the printed step that failed)
#   2  the stack isn't running — run `make compose-up-local-llm` first
#
# Designed to run against an already-up stack. The script does NOT start
# anything itself; pair with `make compose-up-local-llm` if you want
# one-command boot + test.

set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
AGENT_URL="${AGENT_URL:-http://localhost:8080}"
MODEL="${MODEL:-tinyllama}"
QUICK=0
for arg in "$@"; do
  case "$arg" in
    --quick)        QUICK=1 ;;
    --model)        shift; MODEL="$1" ;;
    --model=*)      MODEL="${arg#*=}" ;;
    -h|--help)
      sed -n '2,/^set -/p' "$0" | sed -n 's/^# \?//p'
      exit 0
      ;;
  esac
done

# ── pretty output ─────────────────────────────────────────────────────────────
RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
step()  { printf "${CYN}==>${RST} %s\n" "$1"; }
ok()    { printf "${GRN}✓${RST}   %s\n" "$1"; }
warn()  { printf "${YLW}!${RST}   %s\n" "$1"; }
fail()  { printf "${RED}✗${RST}   %s\n" "$1"; exit 1; }

# ── 1. connectivity ──────────────────────────────────────────────────────────
step "Checking Ollama at $OLLAMA_URL"
VERSION=$(curl -sf --max-time 5 "$OLLAMA_URL/api/version" | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])" 2>/dev/null) \
  || fail "Ollama not reachable. Run: make compose-up-local-llm"
ok   "Ollama responds — version $VERSION"

step "Checking LiteLLM at $LITELLM_URL"
LIVENESS=$(curl -sf --max-time 5 "$LITELLM_URL/health/liveliness" 2>/dev/null) \
  || fail "LiteLLM not reachable"
ok   "LiteLLM responds — $LIVENESS"

step "Checking agent at $AGENT_URL"
AGENT_STATUS=$(curl -sf --max-time 5 "$AGENT_URL/readyz" | python3 -c "import json,sys; print(json.load(sys.stdin)['ready'])" 2>/dev/null) \
  || fail "Agent not reachable"
[ "$AGENT_STATUS" = "True" ] && ok "Agent /readyz returns ready=true" || fail "Agent not ready"

if [ "$QUICK" = "1" ]; then
  printf "\n${GRN}OK — quick smoke test passed${RST} (connectivity only; pass without --quick for e2e)\n"
  exit 0
fi

# ── 2. ensure a model is pulled ──────────────────────────────────────────────
step "Checking if model '$MODEL' is pulled"
MODELS=$(curl -sf "$OLLAMA_URL/api/tags" | python3 -c "import json,sys; print('\n'.join(m['name'] for m in json.load(sys.stdin).get('models', [])))" 2>/dev/null || true)
if echo "$MODELS" | grep -qE "^${MODEL}(:|$)"; then
  ok "Model $MODEL already present"
else
  warn "Model $MODEL not present — pulling (~640MB for tinyllama, may take a few minutes)…"
  curl -sf -X POST "$OLLAMA_URL/api/pull" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"stream\":false}" >/dev/null \
    || fail "Model pull failed"
  ok "Model pulled"
fi

# ── 3. generate via ollama directly ──────────────────────────────────────────
step "Generating via Ollama native API"
RESPONSE=$(curl -sf -X POST "$OLLAMA_URL/api/generate" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"prompt\":\"Reply with exactly the word: pong\",\"stream\":false}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null) \
  || fail "Ollama generation failed"
[ -n "$RESPONSE" ] || fail "Ollama returned empty response"
ok "Ollama generated: $(printf '%s' "$RESPONSE" | head -c 80)…"

# ── 4. generate via LiteLLM (OpenAI-compatible /v1/chat/completions) ─────────
step "Generating via LiteLLM /v1 (proves LiteLLM ↔ Ollama wiring)"
LITELLM_RESPONSE=$(curl -sf -X POST "$LITELLM_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-litellm-local" \
  -d "{\"model\":\"ollama_chat/$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly the word: pong\"}]}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'].strip())" 2>/dev/null) \
  || fail "LiteLLM generation failed — check 'docker compose logs litellm'"
ok "LiteLLM generated: $(printf '%s' "$LITELLM_RESPONSE" | head -c 80)…"

# ── 5. summary ───────────────────────────────────────────────────────────────
printf "\n${GRN}OK — local-llm stack is fully functional${RST}\n"
printf "  Ollama version:    %s\n" "$VERSION"
printf "  Model in use:      %s\n" "$MODEL"
printf "  Ollama response:   %s\n" "$(printf '%s' "$RESPONSE" | head -c 60)"
printf "  LiteLLM response:  %s\n" "$(printf '%s' "$LITELLM_RESPONSE" | head -c 60)"
