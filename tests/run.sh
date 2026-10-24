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

# Guardrail greps (docs/dev/agent-guardrails.md §5.1): each gate bans a
# hand-rolled copy of a ui/ primitive outside its allowlist. A hit means the
# copied-boilerplate drift those primitives exist to prevent is re-entering
# the codebase — extend the primitive instead, or extend the allowlist here
# AND in §5.1 in the same change. Line-comment mentions of an API name
# (e.g. history.lua's "nvim_open_win rejects width < 1") are filtered out;
# only executable code counts.
#
# Why raw nvim_buf_set_lines is allowed where it is:
#   ui/float.lua, ui/picker.lua  ui/ primitives filling a fresh buffer
#   http/script_snippet.lua      single-line splice inside the user's buffer
#   http/curl.lua                insert-at-cursor into the user's file
#   http/lua_docs.lua            invisible LSP analysis buffer
#   http/import.lua              invisible import-resolution context buffer
#   ai/actions.lua               scratch buffer the user keeps editing
#   http/format_file.lua         rewrites the user's still-editable .http file
# (Full-replace writes into display buffers must go through
# ui/render.set_lines, which owns the modifiable trio.)
echo "--- guardrail greps ---"
guardrail_grep() {
    local label="$1"
    local pattern="$2"
    local allowlist="$3"
    local dirs="${4:-lua/}"
    local hits
    hits=$(grep -rnE "$pattern" $dirs --include="*.lua" \
        | grep -vE "$allowlist" \
        | grep -vE ':[0-9]+:[[:space:]]*(---?|--)' || true)
    if [ -n "$hits" ]; then
        echo "FAIL: $label (docs/dev/agent-guardrails.md §5.1):"
        echo "$hits"
        exit 1
    fi
    echo "PASS: $label"
}

guardrail_grep "floats only via ui/float.lua" \
    "nvim_open_win" \
    "lua/poste-http/ui/float\.lua"
guardrail_grep "modifiable toggling only in ui/render.lua, ui/float.lua, http/buffer.lua" \
    'nvim_set_option_value\("modifiable"|\.modifiable[[:space:]]*=[^=]' \
    "ui/render\.lua|ui/float\.lua|http/buffer\.lua"
guardrail_grep "method/status highlight tables only in ui/semantics.lua and http/highlights.lua" \
    "PosteMethodGET|PosteStatus2xx" \
    "ui/semantics\.lua|http/highlights\.lua"
guardrail_grep "winbar tab concatenation only in ui/winbar.lua" \
    "TabLineSel" \
    "ui/winbar\.lua"
guardrail_grep "char-level truncation only in ui/text.lua and ui/columns.lua" \
    "strcharpart|strchars\(" \
    "ui/text\.lua|ui/columns\.lua"
guardrail_grep "buffer line writes only via ui/render.set_lines or the §5.1 allowlist" \
    "nvim_buf_set_lines" \
    "ui/render\.lua|ui/float\.lua|ui/picker\.lua|http/script_snippet\.lua|http/curl\.lua|http/lua_docs\.lua|http/import\.lua|ai/actions\.lua|http/format_file\.lua"
# User messages reach vim.notify only from ui/notify.lua. Scans plugin/ as
# well as lua/: the two :PosteHttp*Info/Status panels in plugin/poste.lua sat
# outside the original lua/-only grep and kept calling vim.notify directly
# (the seven-prefix/three-title dialect drift of 2026-09-30).
guardrail_grep "vim.notify only in ui/notify.lua" \
    "vim\.notify" \
    "lua/poste-http/ui/notify\.lua" \
    "lua/ plugin/"

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
    if output=$(XDG_DATA_HOME="$scratch/data" XDG_CACHE_HOME="$scratch/cache" XDG_STATE_HOME="$scratch/state" \
        nvim --headless -u tests/minimal_init.lua \
        -c "set rtp+=$PLENARY_PATH" \
        -c "set rtp+=." \
        -c "runtime plugin/plenary.vim" \
        -c "runtime plugin/poste.lua" \
        -c "lua require('plenary.busted').run('$spec')" \
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
