# Poste HTTP

File-driven HTTP request executor (Lua + curl). `.http` → execute → results in editable buffer.

## Design Principles

- **Extensibility over speed** — no shortcuts for quick wins
- **Vim ergonomics first** — keyboard-driven, no modal dialogs
- **TDD first** — write test before implementation
- **Bug fix → test** — every bug fix must include a test that would have caught it, to prevent regressions

## Code Conventions

- Lua: `local M = {} ... return M`, `vim.api.*` conventions
- HTTP code in `lua/poste_http/http/`, shared infra in `lua/poste_http/`
- No `require("poste.sql.*")` — SQL is a separate repo
- **Module name ownership**: `poste-http.nvim` comes before `poste-sql.nvim` in rtp.
  Never create files under `lua/poste/sql/` — they would shadow `poste-sql.nvim`'s
  modules silently.
- **HTTP grammar ↔ tree-sitter sync**: Any change to HTTP grammar (parser, syntax)
  must be mirrored in the tree-sitter grammar (`tree-sitter-http/grammar.js`) and
  its query files (`highlights.scm`, `injections.scm`, `locals.scm`).

## Lua Patterns ≠ Regex

**Never import regex habits.** Lua patterns are a different, simpler language.
Check [Lua 5.1 Patterns](https://www.lua.org/manual/5.1/manual.html#5.4.1) or
load the `lua-patterns` skill before writing any `string.match`/`gmatch`/`gsub`.

## References

| Want | Go to |
|------|-------|
| **Shared infra (state, cli, select, install, indicators, buffer_setup, help, etc.)** | `lua/poste_http/` — edit there |
| File index | `docs/dev/file-index.md` |
| Architecture | `docs/dev/architecture-overview.md` |
| Build & test | `docs/dev/testing.md` |
| User syntax | `docs/user/http/syntax.md` |
| TDD guide | `docs/dev/http/tdd-guide.md` |
| Agent learnings | `LEARNINGS.md` |
