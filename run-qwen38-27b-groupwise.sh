#!/usr/bin/env bash
# Qwen3.8-27B groupwise-int server. Thin wrapper; shared launch logic lives
# in run.sh. Groupwise-int weights are ~3 GiB lighter than NVFP4, so
# the full 262,144-token native context fits (docs/performance/qwen3.8-27b.md).
# MTP3 is the default: DFlash2 K=7 decodes faster on code/structured but its
# +1.65 GiB resident cost OOMs at 262k context on 32 GiB (verified 2026-10-06).
# For decode-heavy work at shorter context: SPEC=dflash2 DRAFT_TOKENS=7
# ./run-qwen38-27b-groupwise.sh --max-context 131072.
# Usage: ./run-qwen38-27b-groupwise.sh [--help] [extra ninfer-serve args...]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT=qwen3_8_27b QUANT=groupwise-int \
  PORT="${PORT:-8182}" MODEL_ID="${MODEL_ID:-qwen3.8-27b-groupwise}" \
  MAX_CONTEXT="${MAX_CONTEXT:-262144}" SPEC="${SPEC:-mtp}" DRAFT_TOKENS="${DRAFT_TOKENS:-3}" \
  exec "$ROOT/run.sh" "$@"
