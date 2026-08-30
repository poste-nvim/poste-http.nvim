# Poste HTTP

File-driven HTTP request executor (Lua + curl). `.http` → execute → results in editable buffer.

## Design Principles

- **Extensibility over speed** — no shortcuts for quick wins
- **Vim ergonomics first** — keyboard-driven, no modal dialogs
- **TDD first** — write test before implementation
- **Bug fix → test** — every bug fix must include a test that would have caught it, to prevent regressions

## Code Conventions

- Lua: `local M = {} ... return M`, `vim.api.*` conventions
- HTTP code in `lua/poste-http/http/`, shared infra in `lua/poste-http/`
- No `require("poste.sql.*")` — SQL is a separate repo
- **Module name ownership**: `poste-http.nvim` comes before `poste-sql.nvim` in rtp.
  Never create files under `lua/poste/sql/` — they would shadow `poste-sql.nvim`'s
  modules silently.
- **HTTP grammar ↔ tree-sitter sync**: Any change to HTTP grammar (parser, syntax)
  must be mirrored in the tree-sitter grammar (`tree-sitter-poste-http/grammar.js`) and
  its query files (`highlights.scm`, `injections.scm`, `locals.scm`).
- **HTTP method list sync**: `tree-sitter-poste-http/grammar.js` defines the
  `method_*` tokens and `lua/poste-http/http/data.lua` keeps its own copy of the
  method names. When adding/removing a method in `grammar.js`, update
  `data.lua`'s `http_methods` too — `tests/http/methods_spec.lua` fails if they
  drift.

## Relationship with ../poste-ai.nvim

**Inverted optional dependency — poste-http optionally extends poste-ai.**

- AI integration lives in `lua/poste-http/ai/`: it registers an `http` context
  on poste-ai.nvim via `register_context(id, spec)` (`pcall(require, "poste-ai")`
  in `setup()` and on `:PosteHttpChat`, so both install orders work)
- This repo must never be required by poste-ai; poste-ai knows nothing about HTTP
- The context contract in poste-ai's `lua/poste-ai/context_api.lua` is a
  cross-repo API shared with poste-db.nvim — changing its shape requires
  updating `lua/poste-db/ai/` and this directory in the same change set, and
  running all test suites
- **Prompt hygiene**: prompt context carries raw `{{var}}` placeholders only.
  Never inject resolved env values or resolved request headers (they hold
  credentials); response bodies are truncated before entering the chat
- Design: `docs/dev/ai-integration.md`; tests in `tests/http/ai_*_spec.lua` are
  conditional on poste-ai being on rtp (`tests/minimal_init.lua` appends it)

## Lua Patterns ≠ Regex

**Never import regex habits.** Lua patterns are a different, simpler language.
Check [Lua 5.1 Patterns](https://www.lua.org/manual/5.1/manual.html#5.4.1) or
load the `lua-patterns` skill before writing any `string.match`/`gmatch`/`gsub`.

## References

| Want | Go to |
|------|-------|
|**Shared infra (state, cli, select, install, indicators, buffer_setup, help, etc.)**|`lua/poste-http/` — edit there|
|**UI components (columns, …)**|`lua/poste-http/ui/` — pure, unit-tested, window-free|
| File index | `docs/dev/file-index.md` |
| Architecture | `docs/dev/architecture-overview.md` |
| Build & test | `docs/dev/testing.md` |
| User syntax | `docs/user/http/syntax.md` |
| TDD guide | `docs/dev/http/tdd-guide.md` |
| Agent learnings | `LEARNINGS.md` |
