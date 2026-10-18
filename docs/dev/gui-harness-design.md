# Test harness design for GUI-coupled modules

## 1. Problem

The 12 modules listed in `tests/http/zero_coverage_smoke_spec.lua:1-14` are
too deeply bound to the Neovim GUI to be covered by pure unit tests:

| Module | Path | Why it is bound |
|------|------|----------|
| `buffer_setup` | `lua/poste-http/buffer_setup.lua` | registers keymaps, autocmds, namespaces |
| `commands` | `lua/poste-http/commands.lua` | registers `:Poste*` user commands |
| `help` | `lua/poste-http/help.lua` | opens a floating window |
| `install` | `lua/poste-http/install.lua` | runs shell commands, edits files |
| `highlights` | `lua/poste-http/http/highlights.lua` | calls `nvim_set_hl` |
| `outline` | `lua/poste-http/http/outline.lua` | manages floating windows and buffers |
| `textobj` | `lua/poste-http/http/textobj.lua` | registers text objects |
| `lua_docs` | `lua/poste-http/http/lua_docs.lua` | opens a floating window |
| `script_snippet` | `lua/poste-http/http/script_snippet.lua` | edits buffers |
| `curl` | `lua/poste-http/http/curl.lua` | pastes into a register |
| `copy` | `lua/poste-http/http/copy.lua` | uses `vim.fn.setreg` |
| `folding` | `lua/poste-http/http/folding.lua` | registers `foldexpr` |

The existing `mock_nvim.lua` (`tests/helpers/mock_nvim.lua`) provides stubs
for the Neovim API, but:

- stub functions only record calls; no real state is maintained (buffer
  contents, window tree, option values, …)
- no window traversal such as `nvim_list_wins`/`nvim_win_get_buf`
- no `vim.o`/`vim.wo`/`vim.bo` emulation
- no mechanism for firing autocmds
- no full coverage of `vim.fn` functions (`setreg`, `systemlist`, …)

## 2. Goals

1. Maintainable, isolated unit tests for the 12 GUI-coupled modules
2. Compatibility with the existing `mock_nvim.lua` (existing tests keep passing)
3. Minimal mock effort — only mock the APIs the modules actually use
4. Tests run in headless Neovim (plenary busted), no extra dependencies

## 3. Non-goals

- Not a full Neovim emulator (no UI rendering, no event loop, …)
- Not a replacement for integration tests (integration tests verify real
  Neovim behavior; harness tests verify logic correctness)
- Not chasing 100% line coverage — core logic paths and error handling come
  first

## 4. Architecture

### 4.1 Layering

```
tests/helpers/
├── mock_nvim.lua          # existing: basic API stubs (call recording)
├── gui_harness.lua        # new: high-level test harness
│   ├── injects mock_nvim automatically
│   ├── Buffer emulation (contents, options, filetype)
│   ├── Window emulation (parent/child relations, size, options)
│   ├── Autocmd firing (manually fire registered autocmds)
│   ├── Keymap recording (capture registered keymaps)
│   └── rollback (cleanup on teardown)
```

### 4.2 Core abstractions

#### Buffer model

```lua
-- buffer state maintained inside gui_harness
local _buffers = {
  [1001] = {
    lines = { "line1", "line2" },
    options = { filetype = "poste_http", modifiable = true, buftype = "" },
    valid = true,
    ns_extmarks = { [42] = { { line = 0, col = 0, ... } } },
  },
}
```

- All `nvim_create_buf`/`nvim_buf_set_lines`-style operations read and write
  this state
- `nvim_get_current_buf()` returns the last-touched buffer

#### Window model

```lua
local _windows = {
  [2001] = {
    buf = 1001,
    options = { winbar = "", foldmethod = "manual", foldlevel = 99 },
    width = 80,
    height = 24,
    cursor = { 1, 0 },
    valid = true,
  },
}
```

- `nvim_get_current_win()` returns the last-touched window
- `nvim_list_wins()` returns the list of all windows

#### Autocmd firing

```lua
-- the harness offers manual autocmd firing
harness.fire_autocmd("BufDelete", { buf = 1001 })
harness.fire_autocmd("TextChanged", { buf = 1001 })
```

- Internally it walks the callbacks registered via `nvim_create_autocmd`,
  matches the conditions, then runs them
- No dependence on the Neovim event loop

#### Keymap recording

```lua
-- the harness captures keymap registrations for assertions
local kms = harness.get_keymaps(buf)
assert.equals("run_request", kms["n"]["<CR>"])
```

### 4.3 Per-module test strategy

Analyze every module along these dimensions:

| Dimension | Approach |
|------|------|
| Neovim APIs depended on | mock in `gui_harness.lua` |
| poste-http modules depended on | require directly; the harness guarantees clean state |
| Side effects (files, clipboard, …) | mock or stub |
| Test style | pure-function paths + state assertions + call-recording assertions |

### 4.4 Per-module analysis

#### `buffer_setup.lua`

**APIs depended on**: `nvim_create_namespace`, `nvim_create_augroup`, `nvim_create_autocmd`, `nvim_buf_clear_namespace`, `nvim_buf_set_extmark`, `nvim_buf_get_lines`, `nvim_buf_is_valid`, `vim.keymap.set`, `vim.defer_fn`

**poste modules depended on**: `state`, `indicators`, `nav`, `run`, `curl`, `copy`, `symbols`, `env`, `history`, `help`

**Test strategy**: create a mock buffer, call `setup_buffer_keymaps(buf)`, assert keymaps registered, autocmds created, fileref extmark placed.

**Key scenarios**:
- keymap entries correct after `setup_buffer_keymaps`
- `TextChanged` clears the indicator namespace
- `BufDelete` removes the augroup
- fileref marks placed on file lines and skipped on script lines

#### `commands.lua`

**APIs depended on**: `nvim_create_user_command`

**poste modules depended on**: several (`run`, `history`, `env`, `jq`, `curl`, `session`, `boundary_indicator`)

**Test strategy**: record `nvim_create_user_command` calls, assert command names and callbacks registered correctly.

**Key scenarios**:
- all `:Poste*` commands registered
- command descriptions non-empty

#### `help.lua`

**APIs depended on**: `nvim_open_win`, `nvim_buf_set_lines`, `nvim_win_set_buf`, `nvim_buf_set_name`, `nvim_buf_set_option`, `nvim_win_set_option`

**Test strategy**: create a mock window, call `open()`, assert window/buffer creation and content.

**Key scenarios**:
- buffer content correct after opening the help window
- closing the help window cleans up resources

#### `install.lua`

**APIs depended on**: `vim.fn.systemlist`, `vim.fn.executable`, `vim.fn.stdpath`, `io.open`, `os.execute`

**poste modules depended on**: none

**Test strategy**: mock `vim.fn.systemlist`/`executable`, assert the detection logic.

**Key scenarios**:
- curl presence detection
- C compiler detection
- directory creation

#### `highlights.lua`

**APIs depended on**: `nvim_set_hl`, `nvim_get_hl`

**poste modules depended on**: none

**Test strategy**: record `nvim_set_hl` calls, assert every highlight group defined.

**Key scenarios**:
- all `Poste*` highlight groups defined
- color values correct

#### `outline.lua`

**APIs depended on**: `nvim_open_win`, `nvim_win_set_buf`, `nvim_buf_set_lines`, `nvim_buf_set_keymap`, `nvim_win_set_cursor`, `nvim_list_wins`, `nvim_win_get_width`

**poste modules depended on**: `tree-sitter`, `describe`, `symbols`

**Test strategy**: mock window/buffer creation, call `show_symbols()`, assert the float opened with the right content.

**Key scenarios**:
- window created after opening the outline
- window cleaned up after closing
- key bindings (j/k/ESC/Enter)

#### `textobj.lua`

**APIs depended on**: none (pure Neovim textobj registration)

**poste modules depended on**: none

**Test strategy**: call the functions directly, assert the returned ranges.

**Key scenarios**:
- the `ai` (inner block) text object
- the `ii` (inner indent) text object

#### `lua_docs.lua`

**APIs depended on**: `nvim_open_win`, `nvim_buf_set_lines`, `nvim_win_set_buf`

**poste modules depended on**: `data` (API documentation data)

**Test strategy**: mock window/buffer, call the doc-rendering functions, assert the content.

**Key scenarios**:
- doc window opens
- content includes API signatures and descriptions
- window closes

#### `script_snippet.lua`

**APIs depended on**: `nvim_buf_set_lines`, `nvim_buf_get_lines`, `nvim_buf_is_valid`

**poste modules depended on**: none

**Test strategy**: create a buffer, call the snippet-insertion functions, assert the buffer contents.

**Key scenarios**:
- script template inserted
- assertion template inserted

#### `curl.lua`

**APIs depended on**: `vim.fn.setreg`

**poste modules depended on**: `cache`, `describe`

**Test strategy**: mock `setreg`, assert the copy went to the right register.

**Key scenarios**:
- curl command copied into the register
- IPv6 URL handled correctly

#### `copy.lua`

**APIs depended on**: `vim.fn.setreg`

**poste modules depended on**: `cache`, `describe`, `data`

**Test strategy**: mock `setreg`, assert the copy went to the right register.

**Key scenarios**:
- copy as curl command
- copy as HTTP request

#### `folding.lua`

**APIs depended on**: `nvim_buf_set_option`, `vim.wo`

**poste modules depended on**: `cache`

**Test strategy**: create a buffer, set fold-related options, call `foldexpr`, assert the fold results.

**Key scenarios**:
- fold expression correct
- cache keying correct

## 5. Implementation plan

### Phase 1: `gui_harness.lua` core (~1 day)

- `Buffer` object: create, content read/write, options, namespace, extmarks
- `Window` object: create, buffer association, options, size, cursor
- autocmd registry: store callbacks, support manual firing
- keymap registry: store keymaps, support lookup
- user-command registry: store commands, support lookup
- `vim.o`/`vim.wo`/`vim.bo` emulation: option read/write proxies
- `teardown` integration: wipe all mocked state

### Phase 2: first batch of module tests (~2-3 days)

Ordered by dependency complexity:

1. `highlights` — lightest, only `nvim_set_hl`
2. `textobj` — pure functions, stateless
3. `commands` — only `nvim_create_user_command`
4. `folding` — a few buffer ops
5. `curl` / `copy` — only `vim.fn.setreg`
6. `script_snippet` — a few buffer ops
7. `help` — window + buffer
8. `lua_docs` — window + buffer

### Phase 3: complex module tests (~3-4 days)

1. `buffer_setup` — many dependencies, but core logic already mostly covered (`buffer_setup_spec.lua`)
2. `install` — external command mocks
3. `outline` — multiple windows + buffers + events

### Phase 4: CI integration + update `zero_coverage_smoke_spec.lua` (~0.5 day)

- make the new tests pass in `run.sh`
- update the `zero_coverage_smoke_spec.lua` comments to mark the covered modules

## 6. Success criteria

1. Every GUI-coupled module has at least 1 `describe` block and ≥3 `it` cases
2. All tests pass in headless Neovim (`bash tests/run.sh`)
3. Core logic path coverage ≥ 80% (optimistic estimate, not enforced)
4. Existing tests keep passing
5. `zero_coverage_smoke_spec.lua` comments reflect the real coverage

## 7. Risks and mitigations

| Risk | Mitigation |
|------|------|
| `vim.bo`/`vim.wo`/`vim.o` emulation diverging from real Neovim behavior | keep the mocks simple; cover complex cases with integration tests |
| autocmd condition matching is complex (patterns, buffers, …) | implement exact matching first, add the rest when something is missed |
| dependency chains between modules inflate the mocks | mock dependency modules only when necessary; test pure-function paths first |
| high test maintenance cost | each module's spec is independent; harness changes do not affect existing tests |
