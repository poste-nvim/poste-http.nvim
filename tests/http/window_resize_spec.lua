-- Tests for response window rebalancing after a whole-window resize
-- (e.g. terminal maximize then restore).
--
-- Bug: when the overall Neovim window is resized, the http source split and
-- the response split are left to Neovim's default layout algorithms, which in
-- some cases (terminal maximize → restore) squeeze one window down to a sliver
-- so it is effectively invisible. The fix rebalances the response window on
-- VimResized so neither split disappears.

local harness = require("helpers.gui_harness")
local state = require("poste-http.state")

local function count_calls(name)
  local n = 0
  for _, call in ipairs(harness.calls) do
    if call == name then n = n + 1 end
  end
  return n
end

local function find_autocmd(events)
  for _, entry in ipairs(harness.get_autocmds()) do
    if type(entry.events) == "table" then
      for _, e in ipairs(entry.events) do
        if e == events then return true end
      end
    elseif entry.events == events then
      return true
    end
  end
  return false
end

describe("response window resize", function()
  local buffer

  before_each(function()
    harness.setup()
    state._split_override = nil
    state.config.result_window_ratio = 0.5
    package.loaded["poste-http.http.buffer"] = nil
    buffer = require("poste-http.http.buffer")
  end)

  after_each(function()
    harness.teardown()
    package.loaded["poste-http.http.buffer"] = nil
  end)

  it("registers a VimResized autocmd when the response split opens", function()
    buffer.render_buffer({ "HTTP/1.1 200 OK" }, "text")
    assert.is_true(find_autocmd("VimResized"))
  end)

  it("registers the VimResized autocmd only once", function()
    buffer.render_buffer({ "HTTP/1.1 200 OK" }, "text")
    buffer.render_buffer({ "HTTP/1.1 200 OK" }, "text")
    local n = 0
    for _, entry in ipairs(harness.get_autocmds()) do
      if type(entry.events) == "table" and entry.events[1] == "VimResized" then
        n = n + 1
      elseif entry.events == "VimResized" then
        n = n + 1
      end
    end
    assert.equals(1, n)
  end)

  it("does nothing when no response window is open", function()
    harness.reset_calls()
    buffer.rebalance_on_resize()
    assert.equals(0, count_calls("nvim_win_set_width"))
    assert.equals(0, count_calls("nvim_win_set_height"))
  end)

  ---------------------------------------------------------------------------
  -- Vertical split (default)
  ---------------------------------------------------------------------------

  it("rebalances width when the response split was squeezed to a sliver", function()
    buffer.render_buffer({ "HTTP/1.1 200 OK" }, "text")
    local win = buffer.get_response_win()
    vim.api.nvim_win_set_width(win, 1)  -- simulate broken layout after restore

    buffer.rebalance_on_resize()

    assert.equals(40, vim.api.nvim_win_get_width(win))  -- 0.5 * 80 columns
  end)

  it("rebalances width when the source split was squeezed to a sliver", function()
    buffer.render_buffer({ "HTTP/1.1 200 OK" }, "text")
    local win = buffer.get_response_win()
    vim.api.nvim_win_set_width(win, 79)  -- response eats everything, source = 1

    buffer.rebalance_on_resize()

    assert.equals(40, vim.api.nvim_win_get_width(win))  -- source gets 40 cols again
  end)

  it("honors result_window_ratio when rebalancing", function()
    state.config.result_window_ratio = 0.7
    vim.o.columns = 200
    buffer.render_buffer({ "HTTP/1.1 200 OK" }, "text")
    local win = buffer.get_response_win()
    vim.api.nvim_win_set_width(win, 1)

    buffer.rebalance_on_resize()

    assert.equals(140, vim.api.nvim_win_get_width(win))  -- floor(200 * 0.7)
  end)

  it("leaves a healthy layout untouched", function()
    buffer.render_buffer({ "HTTP/1.1 200 OK" }, "text")
    local win = buffer.get_response_win()
    vim.api.nvim_win_set_width(win, 40)  -- source = 40, response = 40: fine

    harness.reset_calls()
    buffer.rebalance_on_resize()

    assert.equals(0, count_calls("nvim_win_set_width"))
    assert.equals(40, vim.api.nvim_win_get_width(win))
  end)

  ---------------------------------------------------------------------------
  -- Horizontal split (split_direction = "horizontal")
  ---------------------------------------------------------------------------

  it("rebalances height when a stacked response split gets too short", function()
    state.config.split_direction = "horizontal"
    vim.o.lines = 30
    buffer.render_buffer({ "HTTP/1.1 200 OK" }, "text")
    local win = buffer.get_response_win()
    vim.api.nvim_win_set_height(win, 2)

    buffer.rebalance_on_resize()

    -- available rows = 30 - 1 (cmdheight) = 29; half ≈ 15
    assert.equals(15, vim.api.nvim_win_get_height(win))
  end)

  it("leaves a healthy stacked layout untouched", function()
    state.config.split_direction = "horizontal"
    vim.o.lines = 30
    buffer.render_buffer({ "HTTP/1.1 200 OK" }, "text")
    local win = buffer.get_response_win()
    -- rows = 29, healthy split: height 15, source 14
    vim.api.nvim_win_set_height(win, 15)

    harness.reset_calls()
    buffer.rebalance_on_resize()

    assert.equals(0, count_calls("nvim_win_set_height"))
    assert.equals(15, vim.api.nvim_win_get_height(win))
  end)
end)