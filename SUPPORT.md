# Troubleshooting & Support

**Before opening an issue, work through this page.** Most reports come down to
one of a few causes, and the diagnosis path below pinpoints each in under a
minute. Issues that arrive without `:checkhealth poste-http` output will be
asked to provide it before triage.

---

## 1. Run `:checkhealth poste-http`

This is the single most useful diagnostic. It checks:

- **curl** — required; every request goes through it.
- **grpcurl / websocat** — optional backends for `GRPC` and `WEBSOCKET`
  requests (warnings if missing, errors only if you use those protocols).
- **C compiler** — needed to compile the bundled tree-sitter grammars.
- **Grammars** — for each of `poste_http`, `poste_json`, `poste_graphql`:
  the grammar directory, the parser source, the compiled parser, and whether
  the compiled parser is **stale** (older than the source).

```vim
:checkhealth poste-http
```

To copy the output to the clipboard for pasting into an issue:

```vim
:redir @+ | checkhealth poste-http | redir END
```

## 2. Common causes

### "No parser" errors, broken highlighting, or misparsed bodies

The parsers are compiled, not downloaded. A missing or **stale** parser (one
compiled before the current grammar source) silently serves outdated results.

1. Install a C compiler (`cc` or `gcc`).
2. Run `:PosteHttpBuildParsers`.
3. **Restart Neovim** — a running session keeps the previously loaded parser.

### GRPC or WEBSOCKET requests fail while plain HTTP works

These protocols use external backends the plugin does not bundle:

- `GRPC` → [grpcurl](https://github.com/fullstorydev/grpcurl) must be on `PATH`.
- `WEBSOCKET` → [websocat](https://github.com/nickelc/websocat) must be on `PATH`.

`:checkhealth poste-http` reports both.

### Request does nothing on `<CR>`

- The file must be detected as filetype `poste_http` (`:set ft?` to confirm).
  `.http` and `.rest` files are detected automatically; a nonstandard
  extension needs an ftdetect line of your own.
- The cursor must be inside a request block (between `###` separators).

### `{{variable}}` is sent literally

- Variables resolve from the environment selected for that file
  (`:PosteHttpEnv` to inspect/switch). The file must be inside the project
  that owns the `env.json` — check which environment the statusline/boundary
  indicator reports.

### Import (OpenAPI / Swagger / Postman) unavailable

Import uses the optional [beyondlex/finder](https://github.com/beyondlex/finder)
plugin for file selection. Install it, or check that it loads
(`:messages` after startup).

## 3. Before you open an issue

1. `:checkhealth poste-http` — paste the full output (required by the bug
   template).
2. The smallest `.http` file that reproduces the problem. Replace any real
   tokens/credentials with placeholders.
3. Your Neovim version (`nvim --version | head -1`) and OS.

For questions, usage tips, and config sharing, use
[Discussions](https://github.com/poste-nvim/poste-http.nvim/discussions)
instead of Issues.
