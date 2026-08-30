-- Tests for the config-driven keymap registration helper (poste-http.ui.keymaps).
--
-- U7 from the 2026-08-30 review: buffer.lua (~160 lines) and history.lua
-- repeated the same `k = state.get_keymap(...); if k then vim.keymap.set(...) end`
-- pattern for every action.

local keymaps = require("poste-http.ui.keymaps")
local state = require("poste-http.state")

describe("poste-http.ui.keymaps", function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    state.config.keymaps.test_section = {
      close = "Q",
      jump = "<CR>",
      disabled = false,
    }
  end)

  after_each(function()
    state.config.keymaps.test_section = nil
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  local function lhs_list()
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      out[#out + 1] = m.lhs
    end
    return out
  end

  it("registers a mapping from config, falling back to the default", function()
    local registered = keymaps.register(buf, "test_section", "close", "q", function() end)
    assert.is_true(registered)
    assert.equals("Q", lhs_list()[1], "config value wins over the default")
  end)

  it("uses the default when the action is not configured", function()
    local registered = keymaps.register(buf, "test_section", "missing_action", "gx", function() end)
    assert.is_true(registered)
    assert.equals("gx", lhs_list()[1])
  end)

  it("skips registration when the action is disabled (false) in config", function()
    local registered = keymaps.register(buf, "test_section", "disabled", "dd", function() end)
    assert.is_false(registered)
    assert.equals(0, #lhs_list())
  end)

  it("registers a list of specs via register_all", function()
    local calls = {}
    local registered = keymaps.register_all(buf, "test_section", {
      { action = "close", default = "q", handler = function() table.insert(calls, "close") end },
      { action = "missing", default = "zz", handler = function() end, opts = { nowait = true } },
      { action = "disabled", default = "dd", handler = function() end },
    })
    assert.are_same({ true, true, false }, registered)
    local found = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      found[m.lhs] = m
    end
    assert.is_not_nil(found["Q"])
    assert.is_not_nil(found["zz"])
    assert.is_nil(found["dd"], "disabled action must not be mapped")
  end)

  it("invokes the handler when the mapped key is pressed", function()
    local called = false
    keymaps.register(buf, "test_section", "close", "q", function() called = true end)
    vim.api.nvim_set_current_win(vim.fn.bufwinid(buf) >= 0 and vim.fn.bufwinid(buf) or vim.api.nvim_open_win(buf, true, {
      relative = "editor", width = 10, height = 5, row = 1, col = 1,
    }))
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("Q", true, false, true), "mx", false)
    vim.wait(50)
    assert.is_true(called)
  end)
end)
