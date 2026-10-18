# Testing Guide

> How to run and verify Poste at each layer.

## Quick Start

```bash
# Run all tests (tree-sitter grammar + injection + Lua)
tests/run.sh

# Run Lua tests only against a specific plenary install
tests/run.sh /path/to/plenary.nvim

# Run contract tests only
nvim --headless \
  -c "set rtp+=$HOME/.local/share/nvim/lazy/plenary.nvim" \
  -c "set rtp+=." \
  -c "runtime plugin/poste.lua" \
  -c "PlenaryBustedDirectory tests/contract/ {minimal_init = 'tests/minimal_init.lua'}" \
  -c "qa"
```

## Test Layers

| Layer | Tool | Command | Location |
|-------|------|---------|----------|
| Tree-sitter grammar | `tree-sitter parse` | `tests/grammar_spec.sh` | `tests/` |
| Tree-sitter injection | nvim + treesitter | `tests/injection_spec.sh` | `tests/` |
| Lua unit | busted | `tests/run.sh` | `tests/*.lua` |
| Contract | busted | `tests/run.sh` | `tests/contract/` |

CI runs `tests/run.sh` on GitHub Actions (`.github/workflows/ci.yml`): tree-sitter CLI, Neovim 0.10, and plenary.nvim are provisioned automatically.

## Lua Tests

```bash
# Run all Lua tests
tests/run.sh

# Run specific test file
busted tests/http/resolve_spec.lua
```

## Manual Testing

```bash
# Start the playground backends behind one compose file
# (HTTP :8888 + graphql :8890 / grpc :8891 / websocket :8892)
cd playground
docker compose up -d --build

# Open a .http file and run requests from Neovim
nvim http/scenarios/test_server.http
```

Start a single service with `docker compose up -d http` (or `graphql grpc
websocket`). See `playground/README.md` for the full layout and scenarios.

## Troubleshooting

- **"Could not determine request URL"** — Make sure `{{var}}` references have corresponding `@var` definitions in the file or `env.json` entries.
- **Request doesn't execute** — Make sure cursor is on a request line (not on `###` separator) and `env.json` exists.
- **Response doesn't appear** — Check `:messages` for errors. Verify curl is in PATH.
- **Tree-sitter parser not found** — Run `tree-sitter build` in `tree-sitter-poste-http/` and copy the `.so` file to Neovim's parser directory.

---

*Testing guide — Last updated: 2026-07-26*