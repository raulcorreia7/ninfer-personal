#!/usr/bin/env bash
# Qwen3.8-27B NVFP4 server. Thin wrapper; shared launch logic lives in
# run.sh. `just start` wraps this script and passes PORT through.
# Usage: ./run-qwen38-27b-nvfp4.sh [--help] [extra ninfer-serve args...]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT=qwen3_8_27b_nvfp4 QUANT=nvfp4 SPEC="${SPEC:-mtp}" DRAFT_TOKENS="${DRAFT_TOKENS:-3}" exec "$ROOT/run.sh" "$@"
