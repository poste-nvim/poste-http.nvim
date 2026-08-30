# poste-http × poste-ai Integration Design

Register an `http` context on [poste-ai.nvim](https://github.com/beyondlex/poste-ai.nvim)
so the generic AI chat understands `.http` files, can answer questions about
requests/responses with real context attached, and can **execute `http` code
blocks it generates** through poste-http's regular pipeline.

Mirrors the existing poste-db integration (`lua/poste-db/ai/` in poste-db.nvim);
read that first if the poste-ai context contract is unfamiliar
(`lua/poste-ai/context_api.lua` in poste-ai.nvim is the contract authority).

## Goals

- Ask the AI about the **request under the cursor** and the **last response /
  assertion / error results** with real content prefilled (`a` keymap).
- Execute AI-generated ```http blocks directly from chat (```sql-equivalent
  loop: describe → generate → run → inspect → refine).
- `@req/<Name>` mentions inject the raw request block (placeholders intact).
- Auto-inject the focused request block + its dependency chain per request.
- Slash commands: `/requests` (focus a request), `/env` (bind environment).
- Zero hard dependency: everything lives behind `pcall(require, "poste-ai")`.

## Non-goals (v1)

- No chat-side model/provider changes (poste-ai owns all of that).
- No streaming of AI output into the response panel.
- No automatic secret redaction of response bodies (see Security policy for
  what we do instead — raw placeholders, never resolved credentials).
- No changes to the poste-ai context contract (none needed).

## Dependency direction

```
poste-ai.nvim (zero-dep base)   ←  optional dep  ←   poste-http.nvim (this repo)
```

- This repo must never be required by poste-ai. All integration code lives in
  `lua/poste-http/ai/` here.
- Registration is attempted in `setup()` (pcall) and retried on
  `:PosteHttpChat`, so both install orders work (poste-ai loaded after us, or
  not at all — everything degrades to no-ops with a one-line notify).
- Contract coupling: if the poste-ai context contract changes shape, this
  directory and poste-db's `lua/poste-db/ai/` need the same change set.

## Module layout

| File | Role |
|------|------|
| `lua/poste-http/ai/init.lua` | `available()` / `register()` / `open_chat()` / `ask_view()` / `ask_request()` — the only entry points other modules call |
| `lua/poste-http/ai/system_prompt.lua` | static knowledge + dynamic scope section |
| `lua/poste-http/ai/blocks.lua` | pure block helpers: request list from content, block text slicing, block title, method of a block, body truncation (primary test target) |
| `lua/poste-http/ai/mentions.lua` | `@req/<Name>` match/complete/resolve |
| `lua/poste-http/ai/auto_context.lua` | implicit "focused request + deps" block per chat request |
| `lua/poste-http/ai/commands.lua` | `/requests`, `/env` |
| `lua/poste-http/ai/actions.lua` | codeblock `confirm` / `execute` / `append_header` |

Shared infra used (not modified): `describe.lua`, `request_deps.collect_requests_from_content`,
`env.lua`, `state.lua`, `event.lua`, `buffer_setup.lua` (keymap application),
`http/buffer.lua` (response keymaps), `commands.lua` (`:PosteHttpChat`).

## Focus resolution (shared by mentions / auto_context / prefill)

"The request we are talking about" resolves in this order:

1. Chat scope key `request` (bound via `/requests`), resolved inside scope `file`.
2. `state.last_request` (`{ buf, line }` — the block the user last ran, also
   the source of the response panel). Falls through when the buffer is gone.
3. The current buffer when it is a `poste_http` buffer (cursor's block).

The file for scope-less operations (env.json discovery, mention lookup):

1. Chat scope key `file` (absolute path, bound automatically by `open_chat()`
   from the buffer the chat was opened from).
2. `state.last_request.buf`'s name.
3. Any open buffer with `filetype == "poste_http"`.
4. `vim.fn.getcwd()` (blocks.lua then only finds unsaved/scratch content).

`blocks.lua` exposes `focus()` implementing the above; async-free (buffers and
`readfile` only). Every consumer funnels through it, so tests can stub one seam.

### Mention: `@req/<Name>`

- `match(token)` — pure shape check: `^req/([%w%-_%.]+)$` →
  `{ request = name }`. No file I/O (resolution validates later); non-matches
  return nil so the generic chat falls back to file mentions.
- `complete(prefix, cb)` — request names from `blocks.focus()`'s file(s):
  `{ label = "req/Login", description = "POST /api/login" }`. The `req/`
  prefix comes from the user; candidates are full tokens.
- `resolve(ref, cb)` — locate the named block in the focus file (or any open
  poste_http buffer), then return the **raw block text** (separated by its
  `### name` header, `{{var}}` placeholders untouched) as a fenced ```http
  block with a `File path:LINE` caption. cb(nil, err) when not found.

### auto_context: focused request + dependency chain

Called per chat request by poste-ai. Skipped (cb(nil)) when no focus resolves
and no scope is bound; otherwise renders:

```
## Request context (auto)
File `requests/api.http` env `dev`:

### Login
```http
<raw block>
```

### GetProfile          ← only blocks referenced by the focused block
```http
<raw block>
```
```

Dependency extraction: `{{Name.response...}}` / `{{Name.request...}}` refs in
the focused block's text → include those named blocks (≤ 3, only ones found in
the same file). Hard cap ~8 000 chars total before truncation. Everything stays
in raw-placeholder form — the resolver is never invoked for prompt content.

### Slash commands

| Command | Behavior |
|---------|----------|
| `/requests` | pick a request (same candidates as mention completion); `run` binds `api.set_scope("request", name)` |
| `/env` | environments from the scope file's `env.json` (walk-up, same lookup as `env.pick_env`); `run` calls `env.set_env(label)` (execution env is global in poste-http) **and** `api.set_scope("env", label)` so the prompt shows it |

`open_chat()` pre-binds `file` (and nothing else) from the current buffer when
it is a `poste_http` buffer — mirrors poste-db's `scope_chat_target`.

### Codeblock execution (`langs = { "http" }`)

`confirm(text)` — heuristic gate (same shape as poste-db's):
`GET`/`HEAD`/`OPTIONS` pass silently; `SCRIPT` and everything else (POST/PUT/
PATCH/DELETE/…) ask via `vim.fn.confirm`. Lua patterns can't alternate →
lookup table.

`execute(text, refs, cb)` flow:

1. **Target dir**: mention ref `data.file` → scope `file` → cwd (env.json
   walk-up discovers envs relative to this).
2. Create a named scratch buffer `poste://ai_request` (`nofile`,
   `bufhidden=hide`), write the block text raw (placeholders intact so the
   resolver/env pipeline runs exactly like a hand-written block), set
   `filetype = "poste_http"`, open it in a split, cursor on the request line.
3. Call `run.run_request()` — the whole regular pipeline (prompt vars, deps,
   scripts, assertions, response panel, history, indicators) applies unchanged.
4. **Complete detection**: the pipeline has terminal paths that emit no event
   (pre-request errors, silent bail), so poll state every 250 ms —
   `state._busy` false plus `last_response` / `last_errors` decide the note —
   with a hard timeout (`config.timeout + 10 s`) so `cb` always fires exactly
   once.
5. Report: transport error (status 0 / protocol `error`) → `cb(msg, nil)`;
   pre-request errors → `cb(err, nil)`; otherwise `cb(nil, "✓ ran METHOD url →
   status — details in the response panel")`. The scratch buffer stays open
   for editing/saving.

Notes: `state._busy` guards re-entry; `session.begin` inside the pipeline
clears request-scoped state so repeated executions don't bleed. AI blocks with
`<<prompt` vars will open the normal interactive prompts — acceptable, the user
can cancel and re-ask.

`append_header(scope, text)` — `ga` appends the block to the origin buffer
(poste-ai owns placement, we own the directive lines). Only meaningful when the
origin is a `.http` buffer: read `require("poste-ai.state").origin_buf` and
return `nil` unless its filetype is `poste_http`. Otherwise return one
separator line `### <title>` (title = block's first request line
`"METHOD /path"`, or `AI request`), suppressed when the block text already
starts with `###` (the model emitted its own header). A missing separator would
merge the appended block into the previous request, hence the header.

## Ask entry points (prefill)

Both build their prefill text from **raw source**, never resolved values:

- `ask_view()` — `a` in the response panel (default keymap `a`, section
  `http_response`). Includes whatever exists: formatted error list
  (`errors.format_errors`) when `state.last_errors` is non-empty, then the
  response summary (status line, response headers, body truncated at 4 096
  chars), plus a failed-assertion summary when
  `last_assertion_results.failed > 0`.
  - Never includes `metadata.request_headers` (resolved credentials) — the
    request block with `{{placeholders}}` carries the same information safely.
  - Scope bound: `file` + `env` from `state.last_request` / `current_env`.
- `ask_request()` — `ga` in a `.http` buffer (section `http_source`): block
  under cursor (or visual selection lines) prefilled as an ```http block plus
  the file/env line; chat opens focused on the input.

Notify (WARN, title `PosteHttp`) when poste-ai is not installed, matching the
poste-db copy.

## Config / surface additions

```lua
keymaps = {
  http_source   = { ask_ai = "ga" },   -- ask about request under cursor
  http_response = { ask_ai = "a"  },   -- ask about the shown response/errors
}
```

- `state.config.keymaps` gains the two `ask_ai` defaults (`false` disables);
  wired in `buffer_setup.lua` / `http/buffer.lua` via lazy
  `require("poste-http.ai")` inside the callback — no load-time poste-ai dep.
- `:PosteHttpChat` in `commands.lua` → `ai.open_chat()`.
- `init.lua` `setup()` → `pcall(require("poste-http.ai").register)`.
- `help.lua` gets `ask_ai` descriptions (it iterates configured keymaps).
- README + `docs/user/keymaps.md` tables gain the two keys and the command.

## System prompt content

Static `KNOWLEDGE` block: what `.http` files are (blocks, `### name` headers),
`{{var}}` env resolution + `env.json`, request chaining `{{Name.response.body.X}}`,
`< {% %}`/`> {% %}` script blocks and the client API, `SCRIPT` + `client.run()`
orchestration, key surfaces (`<CR>`, response tabs), and **how to answer**:

- When the user wants a runnable request: emit exactly one ```http block,
  complete and executable (no `?` placeholders, no prose inside the block).
- Reference environment values as `{{var}}` — never invent or inline literal
  secrets/tokens; if a value is unknown, add it to env.json instead.
- A `### Title` first line names the generated block (helps `ga` append).
- Assertion answers come as a `> {% ... %}` block (can be part of the http block).

Dynamic section (per request): scope snapshot — bound `file`/`env`/`request`
and the current global env when it differs.

## Security policy

- Prompt context carries **raw placeholders** (`{{api_token}}`), never env
  values. We never call the resolver for prompt-bound text, and never include
  `pending_request`/verbose request headers (those hold resolved credentials).
- Response bodies are truncated (4 KB ask / pass-through for chat-visible
  notes); response headers are included (server-controlled, low risk).
- poste-ai owns API keys and chat session storage; nothing is duplicated here.
- `confirm` gates mutating methods; GET/HEAD/OPTIONS run without asking since
  the user explicitly triggered execution of the block.

## Testing plan

Specs under `tests/http/ai_*_spec.lua`, **conditional** on poste-ai being on
rtp (`tests/minimal_init.lua` appends `../poste-ai.nvim` when present, same as
poste-db's init) so the suite still passes standalone:

- `blocks_spec.lua` (pure): request list/slicing from fixture content, title,
  method extraction, truncation, focus fallback order with stubbed state.
- `mentions_spec.lua`: match shape; resolve from fixture content via an
  injectable content provider (`resolve_from_content`); not-found error path.
- `auto_context_spec.lua`: focused block rendering; dep-chain inclusion and
  caps; nil when no focus.
- `actions_spec.lua`: confirm heuristics; append_header rules (own-header
  suppression, non-.http origin → nil).
- `system_prompt_spec.lua`: contains contract instructions; scope section.
- `register_spec.lua` (needs poste-ai): `ai.register()` fills
  `context_api.get("http")` with the full spec shape; unregisters after.
- Execution wiring (`execute`) is exercised only through the pure seams
  (target-dir resolution, confirm); the real pipeline is already covered by
  run-pipeline specs — matching the repo's split of pure vs wiring tests.

## Rollout

1. This design doc.
2. `blocks.lua` + tests (pure foundation).
3. `system_prompt.lua`, `mentions.lua`, `auto_context.lua` + tests.
4. `commands.lua`, `actions.lua` + tests.
5. `init.lua` + surface wiring (keymaps, `:PosteHttpChat`, help, docs).
6. `register_spec` + suite green + luacheck/stylua clean.
