# Poste File Index

> Quick reference to key files across the project

---

## Rust Core (poste.nvim — SQL only, no longer used for HTTP)

HTTP has been fully migrated from Rust to Lua. See [Rust Retirement Plan](./rust-retirement-plan.md).
The Rust crates in `poste.nvim` are still used for SQL execution.

| Function | File | Description |
|----------|------|-------------|
| SQL parsing | `crates/poste-core/src/sql_parser.rs` | @connection extraction, statement splitting |
| SQL context | `crates/poste-core/src/sql_context/` | Tokenizer, scope resolver, context detection |
| SQL execution | `crates/poste-exec/src/sql_executor.rs` | PG/MySQL/SQLite executor |
| Connection management | `crates/poste-exec/src/sql_connection.rs` | connections.json read/write, test |
| Dialect abstraction | `crates/poste-exec/src/sql_dialect.rs` | Dialect trait + 3 implementations |
| Introspection | `crates/poste-exec/src/sql_introspect.rs` | Schema/table/column/index queries |
| DDL generation | `crates/poste-exec/src/sql_ddl.rs` | DDL statement generator |
| Response structure | `crates/poste-exec/src/response.rs` | Unified response format |
| Cookie management | `crates/poste-exec/src/cookie_jar.rs` | Cookie persistence |
| CLI entry | `crates/poste-cli/src/main.rs` | run/connection/introspect/fmt/context |

---

## Lua Plugin

### Shared (`lua/poste/` — from poste.nvim)

| File | Description |
|------|-------------|
| `init.lua` | Entry point, filetype dispatch |
| `state.lua` | Shared state management |
| `select.lua` | Generic Picker UI |
| `indicators.lua` | Spinner/✓/✘ indicators |
| `buffer_setup.lua` | Buffer boilerplate creation |
| `constants.lua` | Shared constants |
| `error.lua` | Error handling |
| `help.lua` | Help window |

### HTTP Module (`lua/poste/http/`)

#### Execution Pipeline

| File | Description |
|------|-------------|
| `run.lua` | Request execution orchestration (entry point) |
| `curl_exec.lua` | Build curl args, spawn via `jobstart`, temp file management |
| `response_parser.lua` | Parse curl `-D` headers, status, cookies, stderr verbose |
| `file_include.lua` | Expand `< path` directives in body |

#### Parsing & Variable Resolution

| File | Description |
|------|-------------|
| `describe.lua` | Single parse authority — tree-sitter based block metadata (with CLI fallback) |
| `vars.lua` | `VarResolver` — 7-layer priority chain for `{{var}}` substitution |
| `cache.lua` | UI-level buffer index (line types, block bounds) |
| `var_collector.lua` | Variable collection/rollup for completion |
| `resolve.lua` | Shared async resolution pipeline for prompts/deps |
| `request_vars.lua` | Cross-request variable chaining (`{{Name.res.body.X}}`), prompt vars, form data |

#### UI & Rendering

| File | Description |
|------|-------------|
| `buffer.lua` | Right vertical split result panel |
| `view.lua` | Response tab management (Body/Verbose/Assertions) |
| `format.lua` | JSON formatting (dispatches to `format/`) |
| `format/body.lua` | HTTP response body formatting |
| `format/verbose.lua` | Verbose response rendering |
| `format/image.lua` | Image preview |
| `format/multipart.lua` | Multipart body parsing |
| `highlights.lua` | HTTP syntax highlighting (extmarks) |
| `json.lua` | JSON folding, jq filter, outline |
| `session.lua` | Per-request HTTP session lifecycle |
| `boundary_indicator.lua` | Block boundary indicators |

#### Completion

| File | Description |
|------|-------------|
| `completion.lua` | HTTP smart completion (blink.cmp + nvim-cmp) |
| `context_detector.lua` | Context detection for completion |
| `item_builder.lua` | Completion item builder |
| `data.lua` | HTTP history data format helpers, keyword definitions |

#### Scripts & Assertions

| File | Description |
|------|-------------|
| `scripts.lua` | Pre-request script execution (`< {% %}`) |
| `assertions.lua` | Post-request assertion execution (`> {% %}`) |
| `lua_docs.lua` | Lua API documentation helpers |
| `md5.lua` | MD5 helper |
| `script_snippet.lua` | Script snippet insertion |

#### Navigation & Editing

| File | Description |
|------|-------------|
| `nav.lua` | Block navigation, variable lookup, go-to-definition |
| `symbols.lua` | Document symbol outline |
| `outline.lua` | Sidebar outline |
| `textobj.lua` | Text object support |
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
| `copy.lua` | Curl command export |
| `curl.lua` | Paste curl command as `.http` format |

#### Other

| File | Description |
|------|-------------|
| `env.lua` | Environment switching UI |
| `history.lua` | HTTP request history UI + persistence |
| `format_file.lua` | `.http` file formatter (pure Lua, tree-sitter based) |

### SQL Module

SQL Lua code moved to [poste-sql.nvim](https://github.com/beyondlex/poste-sql.nvim) (separate repo).

---

## VimScript

| File | Description |
|------|-------------|
| `syntax/poste_http.vim` | HTTP syntax highlighting |
| `syntax/poste_sql.vim` | SQL syntax highlighting |
| `syntax/poste_dataset.vim` | Dataset buffer syntax |
| `ftdetect/poste.vim` | Filetype detection (.http/.sql/.sqlite) |
| `ftplugin/poste_sql.vim` | SQL filetype plugin settings |

---

## Tests

| Type | Location | Description |
|------|----------|-------------|
| Lua tests | `tests/*.lua` | busted framework |
| Contract tests | `tests/contract/` | Golden fixtures for response shapes |
| Tree-sitter grammar | `tree-sitter-poste-http/` | Grammar tests |

---

## Examples

| Type | Location | Description |
|------|----------|-------------|
| HTTP examples | `examples/http/` | HTTP request examples |
| HTTP playground | `playground/http/` | Test scenarios |

---

## Config Files

| File | Description |
|------|-------------|
| `env.json` | Environment variables ({{var}} substitution) |

---

*File index — Last updated: 2026-07-26*
