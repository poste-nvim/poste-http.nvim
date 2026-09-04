# Multi-Protocol Design: GraphQL, gRPC, WebSocket

> Design for extending `.http` files beyond plain HTTP — GraphQL, gRPC, and WebSocket
> requests in the same file, executed through a per-protocol executor abstraction.

---

## Summary

The three protocols differ wildly in execution model, so the design hangs everything
on one shared refactor plus three protocol-specific executors:

| Protocol | Execution model | Backend | Difficulty |
|----------|----------------|---------|------------|
| GraphQL | Plain HTTP POST with a query body | curl (existing) | Small |
| gRPC | Request/response (unary + streaming) over HTTP/2 | `grpcurl` (new subprocess) | Medium |
| WebSocket | Long-lived, bidirectional, streaming session | `websocat` (new subprocess) | Large |

Difficulty order: **GraphQL ≪ gRPC < WebSocket**. GraphQL needs no new dependency at
all — it lowers to a normal curl request, so variables, assertions, cross-request
references, and jq filtering all work for free.

### Principle revisions required

This design consciously revises two published principles:

- `docs/dev/architecture-overview.md`: "Protocol isolation — HTTP is fully isolated
  from other protocols; this repo is HTTP-only"
- Same file: "curl is the only subprocess"

Replacement framing: protocols are isolated from each other behind a common executor
contract; each protocol owns exactly one subprocess backend (HTTP → curl,
gRPC → grpcurl, WebSocket → websocat). Both docs must be updated in Phase 1/2/3.

---

## Existing Extension Points

The architecture already contains everything needed to bolt protocols on:

1. **The `SCRIPT` method precedent.** `lua/poste-http/http/run.lua` already dispatches
   a non-HTTP request line: `SCRIPT` blocks route to `orchestration.run_script` and
   return a synthetic response. `GRPC` / `WEBSOCKET` / `GRAPHQL` request lines follow
   the same pattern — syntactically they are just new `method_*` tokens in the grammar.
2. **`protocol` field in the canonical response.** Responses already carry a
   `protocol` key (`make_script_response` sets `protocol = "script"`). If every
   executor produces the same canonical response shape, history, assertions, the
   multi-response chain, and winbar tabs work unchanged.
3. **Streaming precedents.** `view.lua`'s `start_verbose_timer` (200 ms poll re-render
   for pending requests) and `jobstart`'s incremental `on_stdout` callbacks are the
   only mechanisms needed to stream WebSocket frames into the response buffer —
   provided writes go through `ui/render.set_lines` (UI guardrail).

## Syntax Design (kulala-compatible)

Existing variable machinery (`@var`, `{{}}`, magic vars, prompt vars, pre-scripts)
applies to all protocols unchanged: it operates on the text layer before describe,
which is protocol-agnostic. That is the main payoff of attaching protocol syntax to
the existing request-line model instead of inventing a new block form.

### GraphQL

Query body, blank line, optional variables JSON — same shape as kulala:

```
### GraphQL
GRAPHQL {{base_url}}/graphql
Authorization: Bearer {{token}}

query User($id: ID!) {
  user(id: $id) { name email }
}

{
  "id": "42"
}
```

### gRPC

`GRPC <host:port>/<package.Service/Method>`. Headers are gRPC metadata. Defaults to
server reflection; `# @grpc-*` comment operators carry proto resolution and raw
grpcurl flags (kulala-compatible escape hatch):

```
### gRPC unary
# @grpc-import-path ./protos
# @grpc-proto echo.proto
GRPC {{grpc_host}}/grpc.examples.echo.EchoService/Echo
X-Trace-Id: {{trace_id}}

{
  "message": "hello {{name}}"
}
```

`GRPC {{host}}` with no method path means "list services via reflection"
(`grpcurl list`).

### WebSocket

Body lines are messages to send, one frame per line:

```
### WebSocket
WEBSOCKET wss://stream.example.com/v1/feed
Sec-WebSocket-Protocol: chat.v1

{"type": "subscribe", "channel": "news"}
{"type": "ping"}
```

v1 semantics: connect → send all lines → collect inbound frames until a deadline or
server close → render. See the WebSocket section for interactive (v2) semantics.

---

## Shared Infrastructure (Phase 0)

### Executor contract

New directory `lua/poste-http/http/executors/`:

```lua
-- Each executor implements:
-- M.run(req, callback)
--   req = { method, url, headers, body, buf_dir, timeout, name }
--   callback(canonical_response)
-- canonical_response = {
--   protocol, status, status_text, latency_ms, url,
--   content_type, headers, body, cookies, metadata,
--   ok,                      -- NEW: protocol-aware success flag
-- }
```

`run.lua`'s `start_curl_exec` becomes executor selection by method:
`GRAPHQL` → lowers internally and calls `curl_exec`; `GRPC` / `WEBSOCKET` → their own
modules. `curl_exec.lua` stays as-is behind a thin `executors/http.lua` wrapper to
minimize churn. `response_parser` is curl-specific (`-D` headers file + `-v` stderr);
the gRPC/WS executors construct the canonical response directly and skip it.

### Protocol-aware success semantics

`run.lua` hard-codes HTTP status logic in two places:

- `set_result_indicator`: `parsed.status >= 400` → error indicator
- `choose_view_tab`: `parsed.status >= 400` → verbose tab

gRPC status codes are 0–16 (`UNAVAILABLE` = 14 would read as "success"). Executors
set `ok` on the canonical response (`is_error(r)` helper), and both call sites
switch to it.

### Dependency checks

`health.lua` + `install.lua` gain `grpcurl` / `websocat` executability checks, like
curl. A missing binary produces a clear entry in the errors view (existing pattern),
never a silent failure.

### Log redaction

`curl_exec.lua`'s `redacted_curl_cmd` / `SENSITIVE_HEADERS` move to a shared util so
gRPC/WS command logs get the same redaction (Authorization metadata, cookies).

---

## Per-Protocol Design

### GraphQL (Phase 1)

The executor is a pure lowering step:

1. Split the body on the blank line: query text, then optional variables JSON
   (Lua patterns only — no regex habits).
2. Synthesize `{"query": ..., "variables": ..., "operationName": ...}`.
3. Force `Content-Type: application/json` unless the user set one.
4. Route to `curl_exec` as a POST.

Everything downstream works unchanged: assertions see the HTTP response,
`{{Login.response.body.data.login.token}}` cross-request refs work because GraphQL
responses are JSON, jq filtering works.

Later enhancements (not Phase 1):

- Auto-surface the GraphQL `errors` array in the Assertions tab
- Query highlighting via `injections.scm` (inject graphql syntax)

### gRPC (Phase 2)

Executor translation:

| Block element | grpcurl flag |
|---------------|--------------|
| Request line target | positional `host:port/pkg.Svc/Method` |
| Body | `-d @` (JSON from temp file, like curl's body file) |
| Header lines | `-H` (metadata) |
| `# @grpc-import-path` | `-import-path` |
| `# @grpc-proto` | `-proto` |
| `# @grpc-flags` | appended verbatim (escape hatch) |
| No method path | `list` invocation via reflection |
| `state.config.timeout` | `-max-time` (seconds, like curl) |

Output mapping: stdout = response message JSON → `body`; response headers/trailers
from `-v` stderr → `headers`; `Grpc-Status` → `status`, `Grpc-Message` →
`status_text`, `protocol = "grpc"`.

Phasing by call type:

1. **Unary** — Phase 2 core
2. **Server-streaming** — frames append to the body view (streaming render)
3. **Client-streaming / bidi** — needs interactive stdin; explicitly unsupported,
   documented as such

Assertions need no changes: `response.status == 0` is OK, `response.body` is the
message JSON. A separate `GRPC {{host}}` list invocation is cheap and useful for
discovering reflection-enabled servers.

### WebSocket (Phase 3–4)

**Tool choice: websocat.** Rust single binary; stdin line = one text frame, which
maps exactly onto the jobstart pipe model. A pure-Lua implementation is rejected:
wss needs TLS and libuv does not do TLS; hand-rolled handshake + framing + masking
is ~300 lines of fragile code ("extensibility over speed").

**v1 — declarative batch (Phase 3).** Connect → send all body lines → collect
inbound frames until a `ws_wait_ms` deadline (config, default ~3 s) or server close
→ `jobstop` → render. The whole lifecycle is still one "request" and fits the
existing `state._busy` model unchanged.

**v2 — interactive session (Phase 4).** The job stays alive:

- Response-buffer keymaps (via `ui/keymaps`): `s` send a message (input through the
  prompt_vars/select precedent), `c` close.
- Inbound frames stream in via `on_stdout` + `vim.schedule` +
  `ui/render.set_lines` append.
- **`state._busy` semantics break:** `run_request` holds `_busy` for the whole
  request; an interactive session would hold it forever. Interactive mode releases
  `_busy` once the connection is established and tracks the session in
  `state.live_session` (single live connection in v1). Buffer wipe auto-closes.
- Keepalive/ping handled by websocat flags.

**Response shape:** `{ protocol = "websocket", status = close code (1000 = normal),
metadata.frames = [{direction, opcode, data, ts}] }`.

**Rendering:** new winbar tab `messages` — one entry each in `buffer.lua`'s tabs
table, `format.format_view`, and the response-buffer keymap list. Text frames that
parse as JSON reuse the existing JSON highlighting. Direction arrows (→ sent /
← recv) plus per-frame timestamps.

---

## Pitfalls / Guardrails

- **Grammar ↔ data sync (AGENTS.md):** adding `method_grpc`, `method_websocket`,
  `method_graphql` touches four places — `grammar.js`, `data.lua` `http_methods`,
  `completion.lua`, `highlights.scm`. `tests/http/methods_spec.lua` fails on drift,
  which doubles as the checklist. Regenerate the parser (`tree-sitter generate`;
  `install.lua`'s compile machinery covers the .so).
- **Variable pre-check reuse:** `errors.find_unresolved_vars` guards url/body/headers
  and is protocol-agnostic — executors must not bypass it.
- **Timeout units:** curl `-max-time` and grpcurl `-max-time` are seconds;
  websocat has no total-time flag — batch mode uses a uv timer + `jobstop`.
- **UI guardrails:** messages-tab drawing goes through `ui/render` / `ui/semantics`;
  gRPC body rendering lives in `http/format/` (pure, no IO); command assembly and
  subprocesses stay in executor modules.
- **Lua patterns ≠ regex** for the GraphQL body splitter and the `# @grpc-*` operator
  parser.
- **Module naming:** nothing under `lua/poste/sql/`-style shadow paths — protocol
  modules live under `lua/poste-http/http/executors/`.

## Roadmap

| Phase | Scope | Depends on | Size | Status |
|-------|-------|------------|------|--------|
| 0 | Executor abstraction + `ok` semantics + redaction sink, pure refactor, all tests green | — | Small | ✅ Done |
| 1 | GraphQL (method token + lowering executor + docs) | Phase 0 | Small | ✅ Done |
| 2 | gRPC (grpcurl executor + `# @grpc-*` operators + unary/server-streaming + health checks) | Phase 0 | Medium | |
| 3 | WebSocket v1 batch + messages tab | Phase 0, websocat | Med-Large | |
| 4 | WebSocket v2 interactive session (live_session, keymaps, streaming append) | Phase 3 | Large | |

## Test Strategy (TDD first)

- **Grammar:** tree-sitter corpus cases for each new request line
  (`tree-sitter-poste-http/test/corpus/`); `methods_spec.lua` covers the
  grammar ↔ data.lua drift.
- **Executors:** pure unit tests over argv construction (block → grpcurl/websocat
  argv) and stdout/stderr fixture → canonical response mapping. No network in tests,
  mirroring how `response_parser` is tested.
- **Pipeline:** contract-test style for executor selection and indicator/view
  behavior with `ok`-based responses.
- **Done criterion unchanged:** `./tests/run.sh` exit 0 + no new luacheck warnings.

## References

- Prior art: [kulala.nvim](https://github.com/mistweaverco/kulala.nvim)
  (HTTP/GraphQL/gRPC/WebSocket client for Neovim) —
  [gRPC syntax](https://kulala.app/usage/grpc),
  [GraphQL syntax](https://kulala.app/usage/graphql),
  [HTTP file format](https://kulala.app/usage/http-file-format)
- Backends: [grpcurl](https://github.com/fullstorydev/grpcurl),
  [websocat](https://github.com/nickelc/websocat) (aka vi/websocat)
- Related docs: [Architecture Overview](./architecture-overview.md),
  [Agent Guardrails](./agent-guardrails.md),
  [User Syntax](../user/syntax.md)

---

*Multi-protocol design — Created: 2026-09-04; Phases 0-1 implemented*
