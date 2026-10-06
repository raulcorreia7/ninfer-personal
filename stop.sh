#!/usr/bin/env bash
set -euo pipefail
NINFER_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec "${NINFER_PYTHON:-$(command -v python3)}" "$NINFER_ROOT/stop.py" "$@"
