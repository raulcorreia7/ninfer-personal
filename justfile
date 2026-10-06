# Local Qwen3.8-27B server lifecycle. Runtime tuning belongs in
# run.sh (+ run-qwen38-27b*.sh wrappers); this file owns only
# process management and checks. NINFER_QUANT selects the artifact:
# nvfp4 (default, port 8181) or groupwise-int (port 8182).
quant := env("NINFER_QUANT", "nvfp4")
port := if quant == "groupwise-int" { "8182" } else { env("NINFER_PORT", "8181") }
host := "127.0.0.1"
base := "http://" + host + ":" + port + "/v1"
root := justfile_directory()
server := if quant == "groupwise-int" { root + "/run-qwen38-27b-groupwise.sh" } else { root + "/run-qwen38-27b-nvfp4.sh" }
binary := root + "/build/apps/ninfer-serve"
model := if quant == "groupwise-int" { root + "/models/qwen3_8_27b.ninfer" } else { root + "/models/qwen3_8_27b_nvfp4.ninfer" }
model_id := if quant == "groupwise-int" { "qwen3.8-27b-groupwise" } else { "qwen3.8-27b" }
model_bytes := if quant == "groupwise-int" { "20437521664" } else { "21492938224" }
pidfile := root + "/.ninfer-" + quant + ".pid"
logfile := root + "/server-" + quant + ".log"
startup_attempts := "60"

default:
    @just --list

# Start the server detached. Writes server.log and .ninfer.pid.
start:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ root }}"
    if [ -f "{{ pidfile }}" ]; then
        pid="$(cat "{{ pidfile }}")"
        if kill -0 "$pid" 2>/dev/null; then
            if curl -sf -m 3 "{{ base }}/models" | grep -q '"id":"{{ model_id }}"'; then
                echo "already running (pid $pid)"
                exit 0
            fi
            echo "pid $pid is alive but {{ model_id }} is unavailable; inspect it before starting another server" >&2
            exit 1
        fi
        rm -f "{{ pidfile }}"
    fi
    if curl -sf -m 3 "{{ base }}/models" >/dev/null 2>&1; then
        echo "port {{ port }} is already serving (not managed by this justfile)" >&2
        exit 1
    fi
    PORT="{{ port }}" nohup "{{ server }}" > "{{ logfile }}" 2>&1 &
    echo $! > "{{ pidfile }}"
    for _ in $(seq 1 "{{ startup_attempts }}"); do
        sleep 2
        curl -sf -m 3 "{{ base }}/models" | grep -q '"id":"{{ model_id }}"' && break
    done
    curl -sf -m 3 "{{ base }}/models" | grep -q '"id":"{{ model_id }}"'
    echo "up (pid $(cat "{{ pidfile }}"))"

# Stop the server started by `just start`.
stop:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ root }}"
    if [ ! -f "{{ pidfile }}" ]; then
        echo "no pidfile; nothing managed here"
        if curl -sf -m 3 "{{ base }}/models" >/dev/null 2>&1; then
            echo "note: port {{ port }} is serving (started outside just)"
        fi
        exit 0
    fi
    pid="$(cat "{{ pidfile }}")"
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    fi
    rm -f "{{ pidfile }}"
    echo "stopped"

# Bounce the server.
restart: stop start

# Process, endpoint, and VRAM at a glance.
status:
    #!/usr/bin/env bash
    cd "{{ root }}"
    if [ -f "{{ pidfile }}" ] && kill -0 "$(cat "{{ pidfile }}")" 2>/dev/null; then
        echo "process: alive (pid $(cat "{{ pidfile }}"))"
    else
        echo "process: not managed here"
    fi
    curl -s -m 10 "{{ base }}/models" && echo
    nvidia-smi --query-gpu=memory.used,memory.free --format=csv

# Follow the server log.
logs:
    tail -n 50 -f "{{ logfile }}"

# One short completion; fails loudly when the server is down or wrong.
smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    curl -s -m 120 "{{ base }}/chat/completions" -H 'Content-Type: application/json' \
        -d '{"model":"{{ model_id }}","messages":[{"role":"user","content":"Reply with one short sentence."}],"max_tokens":64,"reasoning_effort":"none"}' \
        | python3 -c "import json,sys; r=json.load(sys.stdin); m=r['choices'][0]['message']; assert m.get('content'), 'empty content'; print('smoke OK:', m['content'][:80])"

# Preflight: toolchain, binary, model, port, GPU, endpoint. Nonzero exit on FAIL.
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ root }}"
    fail=0
    ok() { echo "ok: $1"; }
    bad() { echo "FAIL: $1"; fail=1; }
    [ -x "{{ binary }}" ] && ok "binary build/apps/ninfer-serve" || bad "binary missing (run cmake build)"
    if [ -f "{{ model }}" ]; then
        [ "$(stat -c%s "{{ model }}")" = "{{ model_bytes }}" ] \
            && ok "model size {{ model_bytes }}" || bad "model size mismatch"
    else
        bad "model file missing"
    fi
    nvidia-smi --query-gpu=name,memory.free --format=csv,noheader 2>/dev/null \
        && ok "gpu visible" || bad "nvidia-smi failed"
    if curl -sf -m 5 "{{ base }}/models" 2>/dev/null | grep -q '"id":"{{ model_id }}"'; then
        ok "endpoint {{ base }} serving {{ model_id }}"
    else
        bad "endpoint {{ base }} not serving (just start)"
    fi
    exit $fail

# Fetch upstream and fast-forward; rebuild when the pin moved. Never force-pushes or rebases.
update:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ root }}"
    before="$(git rev-parse HEAD)"
    git fetch --all --prune
    git pull --ff-only
    after="$(git rev-parse HEAD)"
    [ "$before" = "$after" ] && echo "already latest ($after)" && exit 0
    echo "updated $before -> $after"
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j"$(nproc)"
