# Poste File Index

> Quick reference to key files across the project

---

## Lua Plugin

### Shared (`lua/poste-http/`)

| File | Description |
|------|-------------|
| `init.lua` | Entry point, `setup()` |
| `state.lua` | Shared state management |
| `select.lua` | Generic Picker UI |
| `indicators.lua` | Spinner/✓/✘ indicators |
| `buffer_setup.lua` | Buffer boilerplate creation |
| `constants.lua` | Shared constants |
| `help.lua` | Help window |
| `commands.lua` | `:PosteHttp*` command registration (`M.status()` backs `:PosteHttpInfo` in plugin/poste.lua) |
| `event.lua` | In-process pub/sub bus (`on`/`once`/`emit`/`clear`), pcall-guarded handlers |
| `health.lua` | `:checkhealth poste-http` |
| `install.lua` | Parser build/install helpers (`ensure_parsers`, `force_build`) |
| `util.lua` | Shared helpers — PRNG seeding, credential redaction (`redact_url_*`, `redacted_cmd`, `SENSITIVE_HEADERS`), shell escaping, job-output line reassembly, doc-preview float |

`lua/poste.lua` (outside this directory) is the family root module: it just
delegates to `poste-http` so `require("poste")` resolves without this repo
claiming `lua/poste/`-style paths.

### AI integration (`lua/poste-http/ai/`, optional poste-ai.nvim extension)

| File | Description |
|------|-------------|
| `ai/init.lua` | Context registration on poste-ai.nvim, `:PosteHttpChat`, `a`/`ga` ask prefill |
| `ai/blocks.lua` | Pure `.http` block helpers (list/slice/refs/truncate) + `focus()` seam |
| `ai/system_prompt.lua` | `http` context system prompt (poste-http dialect knowledge) |
| `ai/mentions.lua` | `@req/<Name>` mention match/complete/resolve |
| `ai/auto_context.lua` | Implicit focused-request + dependency-chain context block |
| `ai/commands.lua` | `/requests`, `/env` slash commands |
| `ai/actions.lua` | ```http codeblock confirm/execute (regular pipeline) + `ga` header |

### UI Components (`lua/poste-http/ui/`)

Reusable rendering components — the seed of a standalone Neovim UI component
library. Pure functions, unit-tested without windows (`float.lua` is the one
thin window primitive; its geometry helper is unit-tested and its `open()`
adds the guards — failure cleanup, close-keymaps, `WinClosed`/`on_close` —
that hand-rolled floats used to apply unevenly).

| File | Description |
|------|-------------|
| `columns.lua` | Column-aligned list layout: `render(rows, cols, opts)` → aligned lines + per-cell byte ranges for extmarks. Per-column align (left/right), fixed/max/flex widths, ellipsis truncation, display-width aware (CJK-safe) |
| `text.lua` | Display-width aware truncation: `truncate(s, max)` (end `…`) and `middle(s, max)` (middle `…`). Single source replacing the byte/char-based copies |
| `semantics.lua` | HTTP semantics → highlight groups: `method_hl(method)`, `status_hl(status)`. Single mapping source (groups defined in `http/highlights.lua`) |
| `winbar.lua` | Winbar tab rows: `render_tabs(tabs, active_id)` and tab cycling `cycle(tabs, current_id, direction)` |
| `render.lua` | Scratch-buffer line writer: `set_lines(buf, lines, opts)` — modifiable toggle + optional filetype |
| `float.lua` | Centered floating window: `open(opts)` (scratch buffer, border/title, close keys, `on_close`, failure cleanup) and pure `center(w, h)` |
| `picker.lua` | Floating list picker with incremental search — snacks-less fallback used by `select.lua`; every close path resolves `on_select` exactly once |
| `keymaps.lua` | Config-driven keymap registration: `register(buf, section, action, default, handler)` / `register_all(buf, section, specs, base_opts)`; `false` in config disables an action |
| `notify.lua` | Single entry point for user notifications: `notify(msg, level, opts)` — plugin title (`constants.NOTIFY_TITLE`), 200-column cap, NUL-strip, fast-event-safe, mirrors every message into `state.log`. Direct `vim.notify` elsewhere is a guardrail violation (§5.1) |

### HTTP Module (`lua/poste-http/http/`)

#### Execution Pipeline

| File | Description |
|------|-------------|
| `run.lua` | Request execution orchestration (entry point) |
| `executors/init.lua` | Protocol executor dispatch — request-line method → executor; unknown methods fall back to HTTP |
| `executors/http.lua` | HTTP executor — thin wrapper over `curl_exec` |
| `executors/graphql.lua` | GraphQL executor — lowers `GRAPHQL` blocks to HTTP POST via curl |
| `executors/grpc.lua` | gRPC executor — wraps `grpcurl`, maps gRPC status codes onto the canonical response |
| `executors/websocket.lua` | WebSocket executor — batch session over `websocat`, frames into `metadata.frames` |
| `ws_session.lua` | Interactive WebSocket session — live frames, send/close keymaps, `state.live_session` |
| `format/messages.lua` | Messages view formatter — WebSocket frame transcript to lines |
| `block_operators.lua` | Extract `# @name value` operator comments from a request block |
| `response.lua` | Canonical response helpers — protocol-aware `ok` flag and `is_error` |
| `curl_exec.lua` | Build curl args, spawn via `jobstart`, temp file management; single JSON body normalization point before the body file is written |
| `response_parser.lua` | Parse curl `-D` headers, status, cookies, stderr verbose |
| `file_include.lua` | Expand `< path` directives in body |
| `request_deps.lua` | Cross-request dependency resolution → wire-shaped injection (strings as-is, tables as JSON) |
| `global_headers.lua` | Global header merge — per-request headers override by name (case-insensitive) |

#### Parsing & Variable Resolution

| File | Description |
|------|-------------|
| `describe.lua` | Single parse authority — tree-sitter based block metadata |
| `json_body.lua` | Request-body JSON normalization — strip `//` `/* */` `#` `--` comments and blank lines, repair the dangling comma, but only when the result parses |
| `vars.lua` | `VarResolver` — 7-layer priority chain for `{{var}}` substitution |
| `cache.lua` | UI-level buffer index (line types, block bounds) |
| `var_collector.lua` | Variable collection/rollup for completion |
| `resolve.lua` | Shared async resolution pipeline for prompts/deps |
| `request_vars.lua` | Cross-request variable chaining (`{{Name.response.body.X}}`), prompt vars, form data |
| `nested_access.lua` | Dot/bracket path walker (`data.items[0].x`, `grid[][0]` fallback) shared by completion and jq |
| `jq_mapping.lua` | `<<` prompt jq-lite mapping — parse structured/dynamic option strings, apply dot-path mappings |
| `prompt_vars.lua` | Prompt variable (`<<name [opts]`) collection + interactive resolution, prompt-line stripping |
| `form_data.lua` | Multipart form-data processing + magic-var substitution |

#### UI & Rendering

| File | Description |
|------|-------------|
| `buffer.lua` | Right vertical split result panel |
| `view.lua` | Response tab management (Body/Verbose/Assertions) |
| `format.lua` | JSON formatting (dispatches to `format/`) |
| `format/body.lua` | HTTP response body formatting |
| `format/verbose.lua` | Verbose response rendering. Owns the `as_text` / `as_number` / `as_header_pair` coercion layer: a response re-rendered from persisted history can carry any JSON type in any field, and the formatter degrades a drifted field instead of raising |
| `format/util.lua` | Formatter primitives shared by the `format/` layer — line splitting, `human_size`, `json_pretty`/`json_escape`, url decoding, and the content-type → filetype / text-vs-binary / extension tables. Every helper is total: non-string/non-number input degrades instead of raising (response fields are re-rendered from persisted history) |
| `format/image.lua` | Inline image preview adapters (snacks.image, image.nvim) in the response buffer; float preview delegated to `http/image_view.lua` |
| `format/image_meta.lua` | Pure image metadata (dimensions, size, JPEG EXIF) |
| `format/multipart.lua` | Multipart body parsing |
| `highlights.lua` | HTTP syntax highlighting (extmarks) |
| `json.lua` | JSON folding, jq filter, outline |
| `session.lua` | Per-request HTTP session lifecycle |
| `boundary_indicator.lua` | Block boundary indicators (extmark rectangle; `:PosteHttpBoundary` toggle, per-buffer scope) |
| `variable_inspector.lua` | Variable inspector — buffer/cursor-scoped variable entries for UI |

#### Completion

| File | Description |
|------|-------------|
| `completion.lua` | HTTP smart completion (blink.cmp + nvim-cmp) |
| `context_detector.lua` | Context detection for completion |
| `item_builder.lua` | Completion item builder |
| `grpc_proto.lua` | gRPC completion index — `pkg.Service/Method` and JSON body message fields/enums from `# @grpc-proto` files (offline `grpcurl list|describe`, chained into nested types) or server reflection; mtime-keyed cache; `# @grpc-proto` path items |
| `graphql_schema.lua` | GraphQL schema-aware body completion — SDL parsing, `# @graphql-schema` block operator, query-text position walker, field/arg/enum/type items; mtime-keyed cache; `# @graphql-schema` path items |
| `data.lua` | Static completion data tables — the HTTP method list (mirrors `grammar.js`'s `method_*` tokens), header names, MIME types, status codes |

#### Scripts & Assertions

| File | Description |
|------|-------------|
| `scripts.lua` | Pre-request script execution (`< {% %}`) |
| `assertions.lua` | Post-request assertion execution (`> {% %}`) |
| `script_block.lua` | Shared `< {% %}`/`> {% %}` block extraction (used by scripts.lua + assertions.lua) |
| `script_sandbox.lua` | Shared sandbox env builder (whitelisted stdlibs, curated `os` without execute/io, + injected API) |
| `orchestration.lua` | SCRIPT-block orchestration: `client.run()` coroutine scheduler + typed responses |
| `errors.lua` | Structured pre/post-request error collection + Error tab formatting/highlights |
| `lua_docs.lua` | Lua API documentation helpers |
| `md5.lua` | MD5 helper |
| `script_snippet.lua` | Script snippet insertion |

#### Navigation & Editing

| File | Description |
|------|-------------|
| `nav.lua` | Block navigation, variable lookup, go-to-definition (facade over `nav/`) |
| `nav/text.lua` | Line-scan navigation backend (works without tree-sitter) |
| `nav/ts.lua` | Tree-sitter navigation backend |
| `nav/util.lua` | Shared nav helpers (import-keypath walking, node ranges) |
| `symbols.lua` | Document symbol outline |
| `outline.lua` | Sidebar outline |
| `textobj.lua` | Visual-mode text objects (aR/iH/iB/iS over tree nodes) |
| `folding.lua` | Code folding |
| `diagnostics.lua` | Diagnostics (linting) |
| `treesitter.lua` | Tree-sitter integration (highlights, inspect) |
| `ts_query.lua` | Tree-sitter query helpers |

#### Import & Export

| File | Description |
|------|-------------|
| `import.lua` | Import/run across files (`import ./path`, `run #Name`) |
| `import_openapi.lua` | OpenAPI 3.x spec → `.http` files (pure Lua) |
| `import_swagger.lua` | Swagger 2.0 spec → `.http` files (pure Lua) |
| `import_postman.lua` | Postman Collection v2.1 → `.http` files (pure Lua) |
| `import_parser.lua` | Shared import utilities (schema-to-example, `$ref` resolution, `env.json` generation) |
| `image_cache.lua` | Image URL download + disk cache (TTL, stale fallback, temp-file tracking) and the content-type tables shared with `format/image.lua` |
| `image_view.lua` | Image preview float window + the one-live-preview registry shared with `format/image.lua`'s inline adapters |
| `copy.lua` | Curl command export |
| `curl.lua` | Paste curl command as `.http` format |

#### Other

| File | Description |
|------|-------------|
| `env.lua` | Environment switching UI |
| `history.lua` | HTTP request history UI + disk persistence (`stdpath("data")/poste-http/history.json`). `load()` owns a per-entry sanitizer that drops any field the list row or the detail views read with the wrong type (`sanitize_response` / `sanitize_metadata` / `sanitize_assertion_results`) |
| `format_file.lua` | `.http` file formatter (pure Lua, string-based) |
| `block_boundary.lua` | Single source of truth for request-block boundary rules (shared by `describe.lua` and `cache.lua`) |

## VimScript & runtime files

| File | Description |
|------|-------------|
| `plugin/poste.lua` | Plugin entry — sourced on startup, registers commands/autocmds via `poste-http` |
| `syntax/poste_http.vim` | HTTP syntax highlighting (fallback when tree-sitter is unavailable) |
| `ftdetect/poste.vim` | Filetype detection (`.http`, `.rest`) |
| `after/ftdetect/poste.vim` | Late filetype fix-ups (wins over other plugins' `ftdetect`) |
| `queries/poste_http/`, `queries/poste_json/`, `queries/poste_graphql/` | Tree-sitter highlight/injection/locals queries |

---

## Tests

| Type | Location | Description |
|------|----------|-------------|
| Lua tests | `tests/http/*_spec.lua` | Per-module busted specs (HTTP pipeline, parsing, importers, AI integration) |
| Lua tests | `tests/*_spec.lua` | Root-level specs: `ui_*` primitives, `util`, `event_bus`, completion |
| Contract tests | `tests/contract/` | Golden fixtures for response shapes |
| Tree-sitter grammar | `tree-sitter-poste-http/` | Grammar tests |
| Body injection grammars | `tree-sitter-poste-json/`, `tree-sitter-poste-graphql/` | `poste_json` / `poste_graphql` parsers (JSON/GraphQL + `{{var}}`), injected into request bodies; rtp queries under `queries/poste_*` |

---

## Examples

| Type | Location | Description |
|------|----------|-------------|
| HTTP examples | `examples/http/` | HTTP request examples |
| Playground | `playground/` | One compose file (http :8888, graphql :8890, grpc :8891, websocket :8892) + `.http` scenarios |

---

## Config Files

| File | Description |
|------|-------------|
| `env.json` | Environment variables ({{var}} substitution) |

---

*File index — Last updated: 2026-10-16*
