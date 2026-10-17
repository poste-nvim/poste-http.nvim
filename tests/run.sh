#!/bin/bash
# Run tests with plenary
# Usage: ./tests/run.sh [plenary_path]

set -e

cd "$(dirname "$0")/.."

# Isolated XDG dirs so headless runs never touch the user's real cache/state
# (family lesson from poste-mq/poste-redis). Without this, suite runs race
# the user's live nvim on the real ShaDa file and leak tmp shada files.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/poste-http-test-cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/poste-http-test-data}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-/tmp/poste-http-test-state}"

PLENARY_PATH="${1:-$HOME/.local/share/nvim/lazy/plenary.nvim}"
if [ ! -d "$PLENARY_PATH" ]; then
    echo "Error: plenary.nvim not found at $PLENARY_PATH"
    echo "Usage: $0 [path-to-plenary.nvim]"
    exit 1
fi

echo "Running tests (plenary: $PLENARY_PATH)..."

echo "--- tree-sitter grammar tests ---"
bash tests/grammar_spec.sh

echo "--- tree-sitter injection tests ---"
bash tests/injection_spec.sh

# Guardrail grep (docs/dev/agent-guardrails.md §5.1): user-facing messages go
# through ui/notify — direct vim.notify calls are how the seven-prefix/three-
# title dialect drift of 2026-09-30 happened. Scans plugin/ as well as lua/:
# the two :PosteHttp*Info/Status panels in plugin/poste.lua sat outside the
# original lua/-only grep and kept calling vim.notify directly.
echo "--- guardrail greps ---"
NOTIFY_VIOLATIONS=$(grep -rn "vim\.notify" lua/ plugin/ --include="*.lua" | grep -v "lua/poste-http/ui/notify.lua" || true)
if [ -n "$NOTIFY_VIOLATIONS" ]; then
    echo "FAIL: vim.notify outside ui/notify.lua (user messages must go through ui/notify):"
    echo "$NOTIFY_VIOLATIONS"
    exit 1
fi

echo "--- Lua unit tests ---"
# One nvim per spec file (workers in parallel), not one PlenaryBustedDirectory
# sweep. The sweep dies silently between files on the CI runner: exit 1 after
# the last success banner, zero test failures, no repro with any single file
# or with the same sweep on macOS — the file-to-file transition is the
# problem. Per-file runs cannot transition, isolate any real failure to its
# file, and parallel workers keep the wall clock near the sweep's.
run_one_spec() {
    local spec="$1"
    local scratch
    scratch="$(mktemp -d)" # private XDG state: parallel nvims must not share ShaDa
    local output rc
    if output=$(XDG_CACHE_HOME="$scratch/cache" XDG_STATE_HOME="$scratch/state" \
        nvim --headless -u tests/minimal_init.lua \
        -c "set rtp+=$PLENARY_PATH" \
        -c "set rtp+=." \
        -c "runtime plugin/plenary.vim" \
        -c "runtime plugin/poste.lua" \
        -c "PlenaryBustedFile $spec" \
        -c "qa" 2>&1); then
        rc=0
    else
        rc=$?
    fi
    echo "$output"
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: $spec exited with $rc"
    fi
    rm -rf "$scratch"
    return $rc
}
export -f run_one_spec
export PLENARY_PATH

FAILURES=$(find tests -name '*_spec.lua' | sort | \
    xargs -P "$(sysctl -n hw.ncpu 2>/dev/null || nproc)" -I{} bash -c 'run_one_spec "$@" || exit 1' _ {} | \
    tee /dev/stderr | grep -c '^FAIL:' || true)
TOTAL=$(find tests -name '*_spec.lua' | wc -l | tr -d ' ')

if [ "$FAILURES" -ne 0 ]; then
    echo "FAIL: $FAILURES of $TOTAL spec files exited nonzero"
    exit 1
fi
echo "Spec files run: $TOTAL/$TOTAL"
