--- Real-API tests for the `boundary_style` setup option, which picks how
--- :PosteHttpBoundary marks the request block: "background" (default,
--- full-width rectangle) or "gutter" (only the number column, poste-db.nvim
--- parity).
---
--- Own spec file on purpose: tests/http/boundary_indicator_spec.lua stubs
--- vim.api via helpers.mock_nvim and that poisoning outlives its teardown
--- within the same runner process, so real-API extmark tests cannot share
--- a file with it (same reason as attach_boundary_spec.lua's header note).

local state = require("poste-http.state")
local boundary = require("poste-http.http.boundary_indicator")
-- plugin/poste.lua loads the plugin lazily, so the highlight definitions
-- are not in this process unless the spec requires them itself.
require("poste-http.http.highlights")

local ns = vim.api.nvim_create_namespace("poste_boundary")

local function make_request_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "### a",
    "GET https://x.dev/api",
    "Authorization: Bearer token",
  })
  vim.bo[buf].filetype = "poste_http"
  return buf
end

local function marks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end

describe("boundary_indicator boundary_style", function()
  local buf

  before_each(function()
    state.config.boundary_style = "background"
    buf = make_request_buf()
  end)

  after_each(function()
    state.config.boundary_style = "background"
    boundary.clear(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("background (default) paints a full-width rectangle", function()
    boundary.refresh(buf, 1)
    local all = marks(buf)
    assert.is_true(#all > 0, "refresh must paint boundary extmarks")
    for _, m in ipairs(all) do
      assert.are.equal("PosteHttpBoundary", m[4].hl_group)
      assert.is_truthy(m[4].hl_eol, "background must reach past EOL")
      assert.is_nil(m[4].number_hl_group)
    end
  end)

  it("gutter tints only the number column, not the lines", function()
    state.config.boundary_style = "gutter"
    boundary.refresh(buf, 1)
    local all = marks(buf)
    assert.is_true(#all > 0, "refresh must paint boundary extmarks")
    for _, m in ipairs(all) do
      assert.are.equal("PosteHttpBoundaryGutter", m[4].number_hl_group)
      assert.is_nil(m[4].hl_group, "gutter style must not tint the lines")
      assert.is_nil(m[4].hl_eol, "gutter style must not reach past EOL")
    end
  end)

  it("switching the style replaces the old marks on the next refresh", function()
    boundary.refresh(buf, 1)
    assert.is_true(#marks(buf) > 0)
    state.config.boundary_style = "gutter"
    boundary.refresh(buf, 1)
    local all = marks(buf)
    assert.is_true(#all > 0)
    for _, m in ipairs(all) do
      assert.is_nil(m[4].hl_group, "stale background rectangle survived the switch")
      assert.are.equal("PosteHttpBoundaryGutter", m[4].number_hl_group)
    end
  end)

  it("PosteHttpBoundaryGutter links to PosteHttpBoundary", function()
    local hl = vim.api.nvim_get_hl(0, { name = "PosteHttpBoundaryGutter" })
    assert.are.equal("PosteHttpBoundary", hl.link,
      "gutter must follow the rectangle colour unless overridden")
  end)

  --- Count the extmarks `fn` places, without stubbing the real API.
  local function count_extmarks(fn)
    local real = vim.api.nvim_buf_set_extmark
    local n = 0
    vim.api.nvim_buf_set_extmark = function(...)
      n = n + 1
      return real(...)
    end
    local ok, err = pcall(fn)
    vim.api.nvim_buf_set_extmark = real
    assert.is_true(ok, tostring(err))
    return n
  end

  -- Perf regression: the paint rides a CursorMoved/CursorMovedI autocmd, and
  -- the old code cleared the namespace and re-placed one extmark per row on
  -- EVERY event — N nvim_buf_set_extmark calls per character typed inside an
  -- N-line request block. Nothing about the paint changes while the cursor
  -- stays in the same block with the text untouched, so it must not repaint.
  it("does not repaint while the cursor stays inside one unchanged block", function()
    assert.is_true(count_extmarks(function() boundary.refresh(buf, 1) end) > 0,
      "the first refresh must paint")
    assert.equals(0, count_extmarks(function() boundary.refresh(buf, 1) end),
      "an identical refresh must not re-place extmarks")
    assert.equals(0, count_extmarks(function() boundary.refresh(buf, 2) end),
      "moving within the same block must not repaint either")
  end)

  it("repaints when the block's text changes", function()
    boundary.refresh(buf, 1)
    assert.equals(0, count_extmarks(function() boundary.refresh(buf, 1) end))
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "X-Extra: 1" })
    assert.is_true(count_extmarks(function() boundary.refresh(buf, 1) end) > 0,
      "an edited block must be repainted")
  end)

  it("repaints when the cursor enters a different block", function()
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
      "", "### b", "GET https://y.dev/api", "",
    })
    boundary.refresh(buf, 1)
    assert.equals(0, count_extmarks(function() boundary.refresh(buf, 1) end))
    assert.is_true(count_extmarks(function() boundary.refresh(buf, 5) end) > 0,
      "a different block must be painted")
  end)

  it("repaints after clear()", function()
    boundary.refresh(buf, 1)
    assert.is_true(#marks(buf) > 0)
    boundary.clear(buf)
    assert.equals(0, #marks(buf), "clear must drop the marks")
    assert.is_true(count_extmarks(function() boundary.refresh(buf, 1) end) > 0,
      "clear must invalidate the paint memo")
  end)
end)
