# Poste Architecture Overview

> Overall architecture of the HTTP request executor plugin

---

## Core Design Principles

1. **Protocol isolation behind executors** — each protocol (HTTP, GraphQL, gRPC,
   WebSocket) is isolated behind a common executor contract
   (`lua/poste-http/http/executors/`); HTTP is the fallback executor. See
   [Multi-Protocol Design](./multi-protocol-design.md)
2. **File-driven** — All requests originate from `.http` / `.rest` files
3. **Keyboard-first** — Neovim plugin uses keyboard as primary interaction mode
4. **Lua + one subprocess per protocol** — HTTP uses pure Lua for parsing,
   resolving, and formatting; curl is the HTTP backend, grpcurl backs `GRPC`,
   and websocat backs `WEBSOCKET` (`:checkhealth poste-http` verifies them).
   GraphQL lowers to plain HTTP POST — no extra tooling

---

## Layered Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Neovim Plugin Layer (Lua)                   │
│  ┌──────────────────────────────────────────┐                 │
│  │  lua/poste-http/                         │                 │
│  │  (shared infra + HTTP-specific)          │                 │
│  │                                          │                 │
│  │  Shared: state.lua, select.lua,          │                 │
│  │          indicators.lua, buffer_setup     │                 │
│  │                                          │                 │
│  │  HTTP: run.lua, buffer.lua, view.lua,    │                 │
│  │        completion.lua, format.lua,        │                 │
│  │        highlights.lua, json.lua,          │                 │
│  │        session.lua, describe.lua,         │                 │
│  │        vars.lua, cache.lua, resolve.lua   │                 │
│  └──────────────────────────────────────────┘                 │
│                          │                                  │
│              init.lua: filetype dispatch                    │
│              poste_http → http.init.run_request()           │
│                              │                              │
│                              ↓                              │
│              protocol executor (by request line)            │
│    HTTP → curl   GRAPHQL → curl (POST)   GRPC → grpcurl     │
│                  WEBSOCKET → websocat                       │
│              (vim.fn.jobstart)                              │
└─────────────────────────────────────────────────────────────┘
```

The Rust CLI (`poste`) is no longer used. All parsing, variable resolution,
formatting, and import parsing are done in pure Lua. `run.lua` dispatches to a
protocol executor (`http/executors/`), which owns the one subprocess for its
protocol, spawned via `vim.fn.jobstart`; every executor returns the same
canonical response shape (with the protocol-aware `ok` flag).

---

## Key Dispatch Points

### Lua-side dispatch

`lua/poste-http/init.lua`'s `run_request()`:

```lua
function M.run_request()
  -- HTTP-only: parse .http file, resolve vars, execute curl
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
  ├── lua/poste-http/ (shared infra: state, select, indicators)
  │
  ├── curl (HTTP + GraphQL execution)
  ├── grpcurl (optional, GRPC)
  └── websocat (optional, WEBSOCKET)

No Rust dependency.
```

---

## Testing Strategy

| Layer | Tool | Location |
|-------|------|----------|
| Lua unit tests | busted (`tests/run.sh`) | `tests/http/*_spec.lua` |
| Contract tests | busted | `tests/contract/` |
| Tree-sitter grammar | `tree-sitter test` | `tree-sitter-poste-http/` |

---

## Related Documents

- [HTTP Developer Docs](./http/README.md)
- [HTTP TDD Guide](./http/tdd-guide.md)
- [File Index](./file-index.md)
- [Testing Guide](./testing.md)

---

*Architecture overview — Last updated: 2026-09-04*