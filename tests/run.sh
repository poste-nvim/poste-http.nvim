#!/bin/bash
# Run tests with plenary
# Usage: ./tests/run.sh [plenary_path]

set -e

cd "$(dirname "$0")/.."

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

echo "--- Lua unit tests ---"
nvim --headless -u NONE \
  -c "set rtp+=$PLENARY_PATH" \
  -c "set rtp+=." \
  -c "runtime plugin/plenary.vim" \
  -c "runtime plugin/poste.lua" \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}" \
  -c "qa"
