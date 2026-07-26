# Poste Architecture Overview

> Overall architecture of the multi-protocol request executor

---

## Core Design Principles

1. **Protocol isolation** — HTTP and SQL are fully isolated at the implementation layer, sharing only infrastructure
2. **File-driven** — All requests originate from `.http` / `.sql` files
3. **Keyboard-first** — Neovim plugin uses keyboard as primary interaction mode
4. **Lua + curl** — HTTP uses pure Lua for parsing, resolving, and execution; curl is the only subprocess

---

## Layered Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Neovim Plugin Layer (Lua)                   │
│  ┌────────────────────┐  ┌──────────────┐                    │
│  │  lua/poste/http/   │  │  lua/poste/  │                    │
│  │  (HTTP-specific)   │  │  (shared)    │                    │
│  │                    │  │              │                    │
│  │ run.lua            │  │ state.lua    │                    │
│  │ buffer.lua         │  │ select.lua   │                    │
│  │ completion.lua     │  │ indicators   │                    │
│  │ format.lua         │  │ constants    │                    │
│  │ highlights.lua     │  │ error.lua    │                    │
│  │ assertions.lua     │  │ help.lua     │                    │
│  │ scripts.lua        │  │              │                    │
│  │ curl.lua           │  │              │                    │
│  │ copy.lua           │  │              │                    │
│  │ nav.lua            │  │              │                    │
│  │ history.lua        │  │              │                    │
│  │ describe.lua       │  │              │                    │
│  │ view.lua           │  │              │                    │
│  │ json.lua           │  │              │                    │
│  │ vars.lua           │  │              │                    │
│  │ curl_exec.lua      │  │              │                    │
│  │ response_parser.lua│  │              │                    │
│  │ file_include.lua   │  │              │                    │
│  │ format_file.lua    │  │              │                    │
│  │ import*.lua        │  │              │                    │
│  └────────────────────┘  └──────────────┘                    │
│                          ↓                                  │
│              init.lua: filetype dispatch                    │
│              poste_http → http.init.run_request()           │
│                              │                              │
│                              ↓                              │
│                    curl subprocess                          │
│              (vim.fn.jobstart)                              │
└─────────────────────────────────────────────────────────────┘
```

The Rust CLI (`poste`) is no longer used for HTTP. All parsing, variable resolution,
formatting, and import parsing are done in pure Lua. The only subprocess is `curl`,
spawned via `vim.fn.jobstart`.

---

## Protocol Implementation Comparison

| Dimension | HTTP | SQL |
|-----------|------|-----|
| File extension | `.http`, `.rest` | `.sql`, `.mysql`, `.sqlite` |
| Parser | tree-sitter (`describe.lua`) + `vars.lua` | `sql_parser.rs` (Rust) |
| Executor | `curl_exec.lua` → curl | `sql_executor.rs` (sqlx) |
| Result panel | Right vertical split | Bottom horizontal split |
| Navigation | Normal text cursor | Cell (hjkl) navigation |
| Completion | `http/completion.lua` | `sql/completion.lua` |
| Syntax highlighting | `syntax/poste_http.vim` | `syntax/poste_sql.vim` |
| Formatter | `format_file.lua` (Lua) | N/A |

---

## Shared vs Isolated

### Shared Files (poste-http.nvim infra)

| File | Purpose |
|------|---------|
| `lua/poste/state.lua` | Shared state (env, current connection, etc.) |
| `lua/poste/select.lua` | Generic Picker UI |
| `lua/poste/indicators.lua` | Generic spinner/✓/✘ |
| `ftdetect/poste.vim` | Filetype detection |

### Isolated Files (HTTP-Specific, in poste-http.nvim)

| Group | Files |
|-------|-------|
| **Execution** | `run.lua`, `curl_exec.lua`, `response_parser.lua`, `file_include.lua` |
| **Parsing** | `describe.lua` (tree-sitter), `vars.lua` (VarResolver), `cache.lua` (UI index) |
| **UI** | `buffer.lua`, `view.lua`, `format.lua`, `format/`, `highlights.lua`, `json.lua` |
| **Scripts** | `scripts.lua`, `assertions.lua`, `session.lua` |
| **Navigation** | `nav.lua`, `symbols.lua`, `outline.lua`, `textobj.lua`, `folding.lua` |
| **Completion** | `completion.lua`, `context_detector.lua`, `item_builder.lua`, `var_collector.lua`, `data.lua` |
| **Import** | `import.lua`, `import_openapi.lua`, `import_swagger.lua`, `import_postman.lua`, `import_parser.lua` |
| **Misc** | `copy.lua`, `curl.lua`, `history.lua`, `env.lua`, `boundary_indicator.lua`, `diagnostics.lua`, `format_file.lua`, `treesitter.lua`, `ts_query.lua`, `lua_docs.lua`, `md5.lua`, `script_snippet.lua`, `highlights.lua` |

---

## Key Dispatch Points

### Lua-side dispatch

`lua/poste/init.lua`'s `run_request()`:

```lua
function M.run_request()
  -- HTTP only — SQL handled by poste-sql.nvim plugin
end
```

---

## Data Flow

### HTTP Request Flow

```
.http file
  → run.lua orchestrate
    → resolve.lua: prompts + dependencies
    → scripts.lua: pre-script execution
    → vars.lua: VarResolver {{var}} substitution
    → describe.lua: tree-sitter parse (method/url/headers/body)
    → curl_exec.lua: curl subprocess
    → response_parser.lua: parse -D headers + stdout + stderr
    → buffer.lua render → right vertical split
```

---

## HTTP Request Lifecycle

```
run_request()
  │
  ├─ session.begin()          ← clear request-scoped state
  ├─ resolve_run_at_cursor()  ← check for import/run directives
  │
  ├─ prepare_request()
  │   ├─ resolve prompts (<<var)
  │   └─ resolve dependencies ({{Name.res.body.X}})
  │
  ├─ execute_request()
  │   ├─ extract_pre_script_blocks()
  │   ├─ run_pre_script()       ← sandboxed Lua
  │   ├─ inject_pre_script_vars()
  │   ├─ inject_global_vars()
  │   ├─ process_form_data()
  │   ├─ extract_assertion_blocks()
  │   ├─ describe_content()     ← tree-sitter
  │   └─ resolve_lua_imports()
  │
  ├─ start_curl_exec()
  │   ├─ vars.build_resolver_from_state()
  │   ├─ resolver:substitute()  ← {{var}} resolution
  │   ├─ describe_content()     ← method/url/headers/body
  │   ├─ curl_exec.execute()
  │   │   ├─ file_include.expand()  ← < path
  │   │   ├─ vim.fn.jobstart(curl)
  │   │   └─ response_parser.parse()
  │   └─ build_pending_request()  ← verbose tab
  │
  └─ handle_curl_response()
      ├─ run_and_store_assertions()
      ├─ view.show_view()
      └─ set_result_indicator()
```

---

## Dependency Graph

```
poste-http.nvim (Lua)
  │
  ├── poste.nvim (shared Lua infra: state, select, indicators)
  │
  └── curl (subprocess for HTTP execution)

No Rust dependency for HTTP.
```

---

## Testing Strategy

| Layer | Tool | Location |
|-------|------|----------|
| Lua unit tests | busted (`tests/run.sh`) | `tests/*.lua` |
| Contract tests | busted | `tests/contract/` |
| Tree-sitter grammar | `tree-sitter test` | `tree-sitter-poste-http/` |

---

## Related Documents

- [HTTP Developer Docs](./http/README.md)
- [Rust Retirement Plan](./rust-retirement-plan.md) — migration status
- [HTTP TDD Guide](./http/tdd-guide.md)
- [File Index](./file-index.md)
- [Testing Guide](./testing.md)

---

*Architecture overview — Last updated: 2026-07-26*
