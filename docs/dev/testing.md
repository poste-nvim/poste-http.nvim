# Testing Guide

> How to run and verify Poste at each layer.

## Quick Start

```bash
# Run all Lua tests
tests/run.sh

# Run contract tests only
nvim --headless \
  -c "set rtp+=$HOME/.local/share/nvim/lazy/plenary.nvim" \
  -c "set rtp+=." \
  -c "set rtp+=../poste.nvim" \
  -c "runtime plugin/poste.lua" \
  -c "PlenaryBustedDirectory tests/contract/ {minimal_init = 'tests/minimal_init.lua'}" \
  -c "qa"
```

## Test Layers

| Layer | Tool | Command | Location |
|-------|------|---------|----------|
| Tree-sitter grammar | `tree-sitter parse` | `tests/grammar_spec.sh` | `tests/` |
| Lua unit | busted | `tests/run.sh` | `tests/*.lua` |
| Contract | busted | `tests/run.sh` | `tests/contract/` |

## Lua Tests

```bash
# Run all Lua tests
tests/run.sh

# Run specific test file
busted tests/http/resolve_spec.lua
```

## Manual Testing

```bash
# Create a playground environment
cd playground/http

# Open a .http file and run requests from Neovim
nvim examples/http/basic.http
```

## Troubleshooting

- **"Could not determine request URL"** — Make sure `{{var}}` references have corresponding `@var` definitions in the file or `env.json` entries.
- **Request doesn't execute** — Make sure cursor is on a request line (not on `###` separator) and `env.json` exists.
- **Response doesn't appear** — Check `:messages` for errors. Verify curl is in PATH.
- **Tree-sitter parser not found** — Run `tree-sitter build` in `tree-sitter-poste-http/` and copy the `.so` file to Neovim's parser directory.

---

*Testing guide — Last updated: 2026-07-26*