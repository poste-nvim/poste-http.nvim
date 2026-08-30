-- Tests for the floating list picker (poste-http.ui.picker).
--
-- Extracted from select.lua (2026-08-30 review U8): the snacks-less fallback
-- picker with incremental search. Drives the real headless UI via feedkeys.

local picker = require("poste-http.ui.picker")

describe("poste-http.ui.picker", function()
  local items
  local choice

  before_each(function()
    items = {
      { key = "dev", name = "dev", description = "local" },
      { key = "staging", name = "staging", description = "stage cluster" },
      { key = "prod", name = "prod", description = "production" },
    }
    choice = nil
  end)

  after_each(function()
    vim.cmd("stopinsert")
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
  end)

  local function open()
    picker.open(items, " Pick ", function(key) choice = key end)
    vim.wait(50)
  end

  -- One key per feedkeys call: the picker queues startinsert! on open, and
  -- multi-key blobs race with that deferred mode switch under headless
  -- feedkeys. Single keys + waits behave deterministically.
  local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
    vim.wait(80)
  end

  -- Headless feedkeys never actually enters insert mode, so the TextChangedI
  -- search path is driven by editing the search line and firing the autocmd
  -- directly — same callback, same filter, same render.
  local function type_in_search(text)
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "\239\134\133 " .. text })
    vim.cmd("doautocmd TextChangedI")
    vim.wait(50)
  end

  it("renders the search line and item list into the float", function()
    open()
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("\239\134\133 ", lines[1], "first line is the search box")
    assert.equals("▶ dev  (local)", lines[2], "selection cursor on the first item")
    assert.equals("  prod  (production)", lines[4])
  end)

  it("moves the selection with j and resolves on <CR>", function()
    open()
    feed("j")
    feed("j")
    feed("<CR>")
    vim.wait(100)
    assert.equals("prod", choice)
  end)

  it("clamps k at the first item and resolves on <CR>", function()
    open()
    feed("k")
    feed("k")
    feed("<CR>")
    vim.wait(100)
    assert.equals("dev", choice, "k below the first item stays on it")
  end)

  it("cancels with <Esc> and resolves nil", function()
    open()
    feed("<Esc>")
    vim.wait(100)
    assert.is_nil(choice)
  end)

  it("cancels with q in normal mode and resolves nil", function()
    open()
    feed("q")
    vim.wait(100)
    assert.is_nil(choice)
  end)

  it("filters items while typing in the search box", function()
    open()
    type_in_search("ta")
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- search box echoes the typed text; only matching items remain
    assert.equals("\239\134\133 ta", lines[1])
    local visible = {}
    for i = 2, #lines do
      if lines[i] ~= "" then table.insert(visible, lines[i]) end
    end
    assert.equals(1, #visible, "only the 'staging' item matches 'ta'")
    assert.equals("▶ staging  (stage cluster)", visible[1])
  end)

  it("resolves the filtered selection on <CR>", function()
    open()
    type_in_search("prod")
    feed("<CR>")
    vim.wait(100)
    assert.equals("prod", choice)
  end)

  it("keeps all items when the search text matches nothing after cancel-reset", function()
    open()
    type_in_search("zzz")
    type_in_search("")
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local visible = {}
    for i = 2, #lines do
      if lines[i] ~= "" then table.insert(visible, lines[i]) end
    end
    assert.equals(3, #visible, "clearing the search restores all items")
  end)

  it("resolves nil exactly once when the window is closed externally", function()
    local calls = 0
    picker.open(items, " Pick ", function(key)
      calls = calls + 1
      choice = key
    end)
    vim.wait(50)
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_close(win, true)
    vim.wait(100)
    assert.equals(1, calls, "on_select must fire exactly once")
    assert.is_nil(choice)
  end)
end)
