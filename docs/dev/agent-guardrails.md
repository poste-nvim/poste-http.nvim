# Agent Guardrails — hard constraints and incident log

> Written for AI agents working in this repository (equally true for human
> contributors). Every rule below comes from a real incident, with the source
> noted. Read `AGENTS.md` and `LEARNINGS.md` before starting, and read this
> file **before writing any UI code or any tests**.
> Maintenance convention: a newly stepped-on pit goes into `LEARNINGS.md`
> first; if it reflects "a process that keeps inviting the same mistake"
> rather than a one-off slip, promote it to a rule here.

Rule levels:

- **MUST (hard rule)**: violating one is an implementation error; review
  rejects it outright. The §5 greps make part of this machine-checkable.
- **SHOULD (default rule)**: deviating requires stating the reason in the
  commit message.

---

## 1. UI rendering MUST go through the `lua/poste-http/ui/` primitives — no hand-rolling

**Incident (2026-08-30)**: when `ui/` consisted only of `columns.lua`, nine
copies of float boilerplate had three different levels of guard completeness —
`help.lua` leaked the buffer when opening failed, `image.lua` had no `pcall`
at all, and only `select.lua` had a WinClosed fallback; truncation had 5
implementations with 3 different semantics (outline/inspector truncated by
byte, splitting CJK characters in half); the method→highlight mapping existed
4 times and had already drifted (outline/symbols did not recognize
OPTIONS/SCRIPT). **Copied boilerplate always misses guards; copied mappings
always drift.**

| Task | Must use | Never hand-write |
|---|---|---|
| Float window | `ui/float.open` | `nvim_open_win` + hand-written centering / `q` key / failure cleanup / WinClosed |
| Writing lines into a buffer | `ui/render.set_lines` | the modifiable trio (past bug: a partial miss → empty branch rendered nothing) |
| Display truncation | `ui/text.truncate` / `ui/text.middle` | `#s` byte truncation, `strchars` char truncation |
| method/status highlight | `ui/semantics.method_hl` / `status_hl` | in-place mapping tables (already drifted across 4 copies) |
| winbar tab row | `ui/winbar.render_tabs` / `cycle` | hand-concatenated `TabLineSel` strings |
| keymap registration | `ui/keymaps.register(_all)` | `get_keymap + if k then keymap.set` written per entry |
| column alignment | `ui/columns.render` | `string.format("%-8s")` column gluing |
| fallback picker | `ui/picker.open` | copying the search/nav/close fallback logic a second time |
| user messages | `ui/notify.notify` | calling `vim.notify` directly (§5.1 is machine-checked) |

```lua
-- ❌ Forbidden: hand-rolled float (guards WILL be missed — 9 historical
-- copies missed 3 different kinds)
local ok, win = pcall(vim.api.nvim_open_win, buf, true, {
  relative = "editor", width = w, height = h,
  row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
  style = "minimal", border = "rounded", title = t, title_pos = "center",
})

-- ✅ Correct: the guards (failure cleanup, close keymap, on_close, no-title
-- fallback) live inside the primitive
local buf, win = float.open({ width = w, height = h, title = t, on_close = cleanup })
```

When you need a capability the primitive lacks, **extend the primitive and add
tests** (that is exactly how `close_keys = {}`, `win_opts` and `base_opts`
were added) instead of bypassing it.

### 1.1 Message copy style (the `ui/notify` contract, converged 2026-09-30)

**Incident (2026-09-30 review)**: 113 direct `vim.notify` calls had settled
into 7 prefixes (`[Poste]`/`Poste:`/`poste:`/`poste-http`/`PosteHttp`/
`[poste]`/none) × 4 title styles; `run.lua` alone mixed two. Attribution
flickered in and out, and noice/fidget users could not filter by plugin.

- **Attribution is carried by the title** (`constants.NOTIFY_TITLE`); the
  message body is a bare sentence with no prefix of any kind. When a
  sub-scenario truly needs distinguishing, override with `opts.title`.
- **The wrapper never rewrites the body** (except NUL cleanup and 200-column
  truncation): sentence capitalization is the caller's job; leading tool
  names/placeholders (`jq error`, `{{var}}`) stay as-is — auto-capitalizing
  would turn "jq error" into "Jq error".
- **Level choice**: status reports / success receipts = INFO; unmet
  preconditions, user cancellation, recoverable degradation = WARN; an
  operation that failed to execute (request, import, script, external
  command) = ERROR.
- **notify and state.log never duplicate each other**: `ui/notify` already
  mirrors into the log sink, so call sites must not hand-write `state.log`
  for the same message; the other way round, purely diagnostic info the user
  does not need to see goes to `state.log` directly, not to notify.
- **No silent failures**: any failure branch that reaches
  `callback(false/nil)` must already have a call-site notify (per-item notify
  inside a batch path counts as covered); an error indicator alone does not
  count as telling the user.

---

## 2. Layering MUST: `format/` only turns "response body → line data"

**Incident (U6)**: `format/image.lua` grew to 682 lines mixing four
responsibilities: content-type tables, third-party render adapters, URL
download + caching (network I/O), and float-window UI.

- Inside `http/format/` there must be none of: network requests, disk caches,
  `nvim_open_win`, temp-file management. That infrastructure goes into
  dedicated modules (see `http/image_cache.lua`).
- Window code stays out of `http/` business modules (a pre-existing AGENTS.md
  convention; `ui/float.lua` is the single exception).
- When a new file passes ~500 lines, or a single file shows ≥3 countable
  responsibilities, split it before adding more features.

---

## 3. Lua language traps (all hit for real — must read)

### 3.1 A local name shadowing a required module

**Incident**: `outline.lua` had a local function `render`; a newly added
`local render = require("poste-http.ui.render")` was shadowed by it and blew
up at runtime with `attempt to index upvalue 'render' (a function value)` —
only the tests exposed it.

- **MUST**: before requiring a module, check the file for an existing local
  of the same name (function or variable); on conflict use an alias
  (`local ui_render = require(...)`) and comment why.

### 3.2 pcall truncates multiple return values

**Incident**: `pcall(function() return float.open(...) end)` captured only
the first return value (buf); the code then treated the buf id as a window id
and closed the wrong thing — the window would not close and the test failed.

```lua
-- ❌ only the buf comes through
local ok, out_win = pcall(function() return float.open(opts) end)
-- ✅ narrow explicitly to the values you need
local ok, out_win = pcall(function()
  local _, w = float.open(opts)
  return w
end)
```

- **MUST**: when wrapping a multi-value-returning function in pcall, write
  out explicitly the values you need.

### 3.3 Only functions called through `M.` can be stubbed by tests

**Incident (avoided during the U6 migration)**: `http_image_preview_spec`
stubbed `image_mod.download_image_url` directly; had the caller bound
`local download = image_cache.download_image_url` at module load time, the
stub would have had no effect.

- **MUST**: when a module calls one of its own replaceable (stub-able)
  functions, dispatch through `M.fn(...)` — never pre-bind to a local.

### 3.4 Collections registered by identity must be keyed by that identity, and must reject non-string keys

**Incident (2026-10-16)**: `image_cache`'s in-flight download registry was an
array, and every completion callback called `table.remove(temp_files)` —
that means "remove the last one", not "remove mine". An async downloader
exists precisely so several previews can be in flight at once, so two
concurrent downloads each unregistered the other's path, and
`cleanup_url_preview` (called on every response re-render) could delete a
target file that was still downloading. Switching to
`temp_files[path] = true` + unregister-by-path is what wrote the invariant
"one completion unregisters exactly its own file" into the code. Same round:
`temp_files[nil] = nil` raises `table index is nil`, so register/unregister
both reject non-strings — caught by the newly written spec, not derived on
paper.

### 3.5 Helpers whose contract is "return a string/number" must type-guard at the entrance

**Incident (2026-10-16)**: `format/util.human_size` called `math.abs` on its
input, which comes from persisted history (`"file_size": "big"` is legal
JSON), and the whole Verbose page died with `bad argument #1 to 'abs'`. Every
public helper whose contract is "returns a string/number" must reject
unexpected types at the entrance (`human_size`, `mime_of`, `url_decode`,
`split_lines`, `pretty_body` were all hardened in that round) instead of
hoping every call site remembers to type-check.

---

## 4. Testing MUSTs (headless incidents, hit first-hand)

| # | Rule | Incident |
|---|---|---|
| T1 | **Feed keys one per feedkeys**: a single `feedkeys("jj<CR>", "mx")` races the queued `startinsert!` and the second key gets swallowed. One feedkeys per key + `vim.wait` | picker spec failed on its first run |
| T2 | **Headless never really enters insert mode**. To test the TextChangedI search path, edit the search line directly and drive the real callback with `doautocmd TextChangedI` | filter assertions saw 3 instead of 1 |
| T3 | **`PlenaryBustedFile` does not load `minimal_init`**; specs depending on `helpers.*` can only be validated through `tests/run.sh` (directory mode); a lone-file run reporting `module 'helpers.mock_nvim' not found` is not the code under test's fault | misjudged during U6 verification |
| T4 | **`vim.v.shell_error` is read-only**. To simulate command failure, run the real `false` command via `saved_system({ "false" })` | image_cache spec broke |
| T5 | **API shapes**: `nvim_buf_get_keymap` lhs is the literal `"<Esc>"`, not `"\27"`; `nvim_win_get_config().title` is a chunk table `{{text}}`; `relative="editor"` `row/col` are numbers. Probe the shape before asserting | 3 misjudgments in the ui_float spec |
| T6 | **Assert the implemented contract; do not invent expected values**. Read the function's doc comment before writing assertions (e.g. `ui/text.truncate` is "fill the budget" semantics: `max-1` width of content + ellipsis) | 2 wrong truncate expectations |
| T7 | **`helpers.gui_harness`'s `strdisplaywidth` stub is the byte version** (`#s`). Do not assert exact display-width values under the harness; use real-nvim specs (the `tests/ui_*_spec.lua` style) | avoided during migration |

The TDD flow (a pre-existing AGENTS.md convention) is unchanged: write the
spec first and watch it go red (usually module not found), implement to
green; every bug fix carries a regression test that would have caught it.

---

## 5. Done checklist (all MUST pass)

### 5.1 UI hard-rule greps (a hit = violation, unless allowlisted)

```bash
# Float windows may only be created by ui/float.lua
grep -rn "nvim_open_win" lua/ | grep -v "lua/poste-http/ui/float.lua"
# The modifiable trio only in ui/render.lua (buffer.lua's get_response_buffer
# locking it once at creation time is legal)
grep -rn 'nvim_set_option_value("modifiable"' lua/ | grep -v "ui/render.lua\|http/buffer.lua"
# method/status → highlight mappings only in the semantics module and the highlight definitions
grep -rln "PosteMethodGET\|PosteStatus2xx" lua/ | grep -v "ui/semantics.lua\|http/highlights.lua"
# winbar concatenation only in ui/winbar.lua
grep -rln "TabLineSel" lua/ | grep -v "ui/winbar.lua"
# Char-level truncation primitives only in ui/text.lua and ui/columns.lua
grep -rln "strcharpart\|strchars(" lua/ | grep -v "ui/text.lua\|ui/columns.lua"
# User messages may only reach vim.notify from ui/notify.lua (tests/run.sh
# already enforces this gate, scanning both lua/ and plugin/ — plugin/ was
# outside the gate for a long time)
grep -rn "vim\.notify" lua/ plugin/ | grep -v "lua/poste-http/ui/notify.lua"
```

This list = the legitimate remainder after the 2026-08-30 convergence. **New
hits must go through the ui/ primitives**; if a second site is genuinely
needed, extend the primitive and update this list first.

### 5.2 The verification trio

1. `./tests/run.sh`'s **exit code must be 0** — do not just read each spec's
   `Failed : 0`: there has been a "every spec shows 0 failures but exit=1"
   case whose real cause was a different spec failing to load.
   `Spec files run: N/M` must show N == M; fewer means some file never ran.
2. `luacheck lua tests` **0 warnings / 0 errors** (baseline since 2026-10-16:
   0; the old "baseline 70 warnings" written in earlier docs is long
   obsolete). Any new warning counts as a regression.
3. For float/view changes, run one headless smoke that really opens it
   (help/outline/history/inspector/body+verbose views).

Before touching code you can run `tools/relation-check.sh` (five views:
set-lines / state / format / pre-render / session; a wrong directory exits 1
instead of silently skipping).

### 5.3 Commit discipline

- One phase (one review entry) per commit — never mix entries; this matches
  the 2026-07 refactor plan's "every Phase independently revertible".
- Update alongside the code: `docs/dev/file-index.md` (new modules),
  `LEARNINGS.md` (new pits), and the entry status in the corresponding review
  report. Doc drift itself was an entire discovery class (D01–D17) of the
  2026-08-13 review.

---

## 6. SHOULDs before writing new code

1. **Grep before you write**: before adding any utility function (truncation,
   centering, keymap reading, time formatting…), grep the whole repo for an
   existing implementation — the five ui/ components exist precisely because
   "write first, discover duplicates later" went wrong.
2. **Copy-pasting more than ~10 lines means a shared module is due** —
   especially guarded boilerplate.
3. When two implementations are "logically identical, differing only in
   parameters" (winbar, tab cycling, importer interaction flows), extract a
   parameterized primitive; do not tolerate a third copy appearing.
4. When adding a primitive to `lua/poste-http/ui/`, follow its conventions:
   pure functions first, no hidden module-level mutable state, geometry and
   parsing unit-testable headless; window primitives (float) stay thin.
5. **When hardening a load boundary, enumerate by "which fields the consumer
   reads", not by "which fields the writer wrote"**. `history.load` tripped
   over this three rounds in a row (10-07 checked only three top-level keys;
   10-16 added the headers entry; scalars like time/latency/url/metadata only
   landed in the same round's follow-up). And **guard both ends**: persisted
   JSON crosses the load boundary, in-memory/stubbed responses do not — so
   the render side must also degrade gracefully (see §3.5). Run the probe
   twice — once across the boundary, once feeding render directly; feeding
   directly over-reports, crossing the boundary under-reports.
6. **Performance changes need numbers**. `boundary_indicator`'s redraw
   memoization (0.196ms → 0.0007ms per call) was measured before it was
   changed; asserting on "call counts" (count `nvim_buf_set_extmark` calls in
   the spec) is steadier than asserting wall-clock time.

---

*Source: the 2026-08-30 UI convergence (U1–U8) and the same-day refactor;
per-round review entries are no longer archived separately — the rules that
landed are this file itself.
Maintainer: after every incident that violates this file, note the entry
number here once it is fixed.*
