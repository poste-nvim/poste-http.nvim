--- Regressions from the 2026-10-28 nav/completion review round: the
--- outline's stale-window crash, the greedy var-ref match in nav/ts, and
--- the alias-column locator shared by all three import-alias sites.
local harness = require("helpers.gui_harness")

describe("outline stale source window (2026-10-28 round)", function()
  before_each(function()
    harness.setup()
  end)

  after_each(function()
    harness.teardown()
  end)

  it("highlight_current bails when the source window closed", function()
    -- `active` outlives a closed source WINDOW (only BufWipeout tears it
    -- down); the buffer-local CursorMoved then read the dead window and
    -- raised "Invalid window id" on every cursor move.
    local outline = require("poste-http.http.outline")
    local src_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(src_buf, 0, -1, false, {
      "### One", "GET http://x/1", "", "### Two", "GET http://x/2",
    })
    local out_buf = vim.api.nvim_create_buf(false, true)
    -- Simulate the post-close state: valid buffers, a DEAD window id.
    outline._set_active_for_test({ src_buf = src_buf, src_win = 99999, out_buf = out_buf, out_win = 99999 })

    local ok, err = pcall(function() outline._highlight_current_for_test() end)
    assert.truthy(ok, "highlight_current must not raise on a stale window, got: " .. tostring(err))
    local ok2, err2 = pcall(function() outline._render_for_test() end)
    assert.truthy(ok2, "render must not raise on a stale window, got: " .. tostring(err2))
  end)
end)

describe("nav/ts var_ref match (2026-10-28 round)", function()
  it("the greedy {{(.+)}} form would mangle a two-ref value (pattern pinned)", function()
    -- nav/ts.lua's var_value handler used text:match("{{(.+)}}"): on
    -- "Hello {{name}} — {{user.name}}" it captured
    -- "name}} — {{user.name" and fed find_var_def that garbage. The lazy
    -- form captures the first ref. This pins the PATTERN the code uses.
    local text = "Hello {{name}} — {{user.name}}"
    local lazy = text:match("{{(.-)}}")
    local greedy = text:match("{{(.+)}}")
    assert.equals("name", lazy)
    assert.not_equals("name", greedy)
  end)
end)

describe("shared alias-column locator (2026-10-28 round)", function()
  -- Dispatch through the module (mirrors the nav.text/nav.ts call sites):
  -- the helper used to be file-local, so those call sites called nil and
  -- gd on an import alias crashed — a mirrored copy here would have stayed
  -- green through exactly that failure.
  local nav_util = require("poste-http.http.nav.util")
  local function locate(line, alias)
    return nav_util.find_alias_col(line, alias)
  end

  it("locates the alias regardless of spacing around 'as'", function()
    -- The three former per-site copies each broke on one of these shapes:
    -- unanchored 'as%s+' matched inside the path, the '%s+as%s+' window
    -- assumed exactly one space, and the literal ' as ' missed two.
    assert.equals(18, locate("import ../gas as m", "m"),
      "an 'as' inside the path must not shift the match")
    assert.equals(20, locate("import ./a.lua  as m", "m"),
      "two spaces before 'as' must still locate the alias")
    assert.is_nil(locate("import ./a.lua   asm", "m"),
      "a path-local token is not the alias")
  end)
end)
