#!/usr/bin/env bash
# Shared ninfer-serve launcher. Per-artifact settings belong in run-*.sh;
# this file owns only binary/model checks, help text, and exec.
# Usage: ARTIFACT=<id> QUANT=<groupwise-int|nvfp4> ./run.sh [--help] [extra args...]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$ROOT/build/apps/ninfer-serve"

: "${ARTIFACT:?run.sh needs ARTIFACT (e.g. qwen3_8_27b)}"
: "${QUANT:?run.sh needs QUANT (groupwise-int|nvfp4)}"

# --- Tunables (each overridable via env) ---
MODEL="${MODEL:-$ROOT/models/$ARTIFACT.ninfer}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8181}"
MAX_CONTEXT="${MAX_CONTEXT:-240000}"    # per-request logical ceiling (tokens)
KV_CAPACITY="${KV_CAPACITY:-auto}"      # physical KV pool; auto sizes from free VRAM
MAX_CONCURRENCY="${MAX_CONCURRENCY:-2}" # resident lanes 1..8
DEVICE_STATE_SLOTS="${DEVICE_STATE_SLOTS:-$MAX_CONCURRENCY}"  # extra checkpoint slots beyond lanes
PREFILL_CHUNK="${PREFILL_CHUNK:-1024}"  # server default; all published runs use 1024
KV_DTYPE="${KV_DTYPE:-fp8}"             # server default bf16; fp8 fits 240k on 32 GiB
MODEL_ID="${MODEL_ID:-qwen3.8-27b}"       # both Qwen3.8 artifacts report qwen3.8-27b; override per script
PENDING_TIMEOUT_MS="${PENDING_TIMEOUT_MS:-300000}"  # server default 30s; a 240k prefill alone takes ~60s
MAX_PENDING="${MAX_PENDING:-16}"         # waiters behind active lanes; full -> HTTP 429

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<EOF
Usage: run-<artifact>.sh [--help] [extra ninfer-serve args...]

Artifact: $ARTIFACT ($QUANT)
Resolves to: $BIN <model> --host $HOST --port $PORT --model-id $MODEL_ID
  --max-context $MAX_CONTEXT --kv-capacity $KV_CAPACITY
  --max-concurrency $MAX_CONCURRENCY --device-state-slots $DEVICE_STATE_SLOTS
  --pending-timeout-ms $PENDING_TIMEOUT_MS --max-pending-requests $MAX_PENDING
  --prefill-chunk $PREFILL_CHUNK --kv-dtype $KV_DTYPE
  --spec $SPEC --draft-tokens $DRAFT_TOKENS --lm-head-draft --preserve-thinking

Env overrides: MODEL MODEL_ID HOST PORT MAX_CONTEXT KV_CAPACITY
  MAX_CONCURRENCY DEVICE_STATE_SLOTS PENDING_TIMEOUT_MS MAX_PENDING
  PREFILL_CHUNK KV_DTYPE SPEC DRAFT_TOKENS. Extra args append to the resolved command.
EOF
    exit 0
fi

[[ -x "$BIN" ]] || { echo "error: server binary missing: $BIN (run cmake build)" >&2; exit 1; }
[[ -f "$MODEL" ]] || { echo "error: model artifact missing: $MODEL" >&2; exit 1; }

exec "$BIN" "$MODEL" \
  --host "$HOST" \
  --port "$PORT" \
  --model-id "$MODEL_ID" \
  --max-context "$MAX_CONTEXT" \
  --kv-capacity "$KV_CAPACITY" \
  --max-concurrency "$MAX_CONCURRENCY" \
  --device-state-slots "$DEVICE_STATE_SLOTS" \
  --pending-timeout-ms "$PENDING_TIMEOUT_MS" \
  --max-pending-requests "$MAX_PENDING" \
  --prefill-chunk "$PREFILL_CHUNK" \
  --kv-dtype "$KV_DTYPE" \
  --spec "$SPEC" \
  --draft-tokens "$DRAFT_TOKENS" \
  --lm-head-draft \
  --preserve-thinking \
  "$@"
