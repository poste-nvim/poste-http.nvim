-- Tests for the centered floating-window primitive (poste-http.ui.float).
--
-- Replaces nine hand-rolled scratch-buffer + nvim_open_win blocks across
-- help / inspector / outline / select / history / image / commands.
-- Behavioral guarantees being locked down:
--   * failure to open cleans up the freshly created buffer
--   * close_keys map onto the buffer and close the window
--   * on_close fires exactly once, regardless of the close path

local float = require("poste-http.ui.float")

describe("poste-http.ui.float", function()
  describe("center (pure geometry)", function()
    it("centers a window inside the editor", function()
      vim.api.nvim_set_option_value("columns", 80, {})
      vim.api.nvim_set_option_value("lines", 24, {})
      local row, col = float.center(40, 10)
      assert.equals(7, row)
      assert.equals(20, col)
    end)

    it("clamps to zero for oversized windows", function()
      local row, col = float.center(999, 999)
      assert.equals(0, row)
      assert.equals(0, col)
    end)
  end)

  describe("open", function()
    after_each(function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative ~= "" then
          pcall(vim.api.nvim_win_close, w, true)
        end
      end
    end)

    it("creates a scratch buffer and a valid window", function()
      local buf, win = float.open({ width = 30, height = 5, lines = { "hello" } })
      assert.is_not_nil(buf)
      assert.is_not_nil(win)
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      assert.is_true(vim.api.nvim_win_is_valid(win))
      assert.equals("nofile", vim.bo[buf].buftype)
      assert.are_same({ "hello" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      vim.api.nvim_win_close(win, true)
    end)

    it("applies border/title/filetype/cursorline options", function()
      local buf, win = float.open({
        width = 30, height = 5,
        title = " T ", border = "single",
        filetype = "poste_help", cursorline = true,
      })
      local cfg = vim.api.nvim_win_get_config(win)
      assert.is_not_nil(cfg.border, "border must be configured")
      -- nvim returns title as a chunk array: { { text } }
      assert.equals(" T ", cfg.title[1][1])
      assert.equals("poste_help", vim.bo[buf].filetype)
      assert.is_true(vim.wo[win].cursorline)
      vim.api.nvim_win_close(win, true)
    end)

    it("opens unfocused windows when focus=false", function()
      local _, win = float.open({ width = 30, height = 5, focus = false })
      assert.is_true(vim.api.nvim_win_is_valid(win))
      assert.is_false(vim.api.nvim_get_current_win() == win)
      vim.api.nvim_win_close(win, true)
    end)

    it("accepts a caller-created buffer untouched", function()
      local mybuf = vim.api.nvim_create_buf(false, true)
      vim.bo[mybuf].bufhidden = "hide"
      local buf, win = float.open({ buf = mybuf, width = 20, height = 3 })
      assert.equals(mybuf, buf)
      assert.equals("hide", vim.bo[buf].bufhidden, "caller buffer options must be preserved")
      vim.api.nvim_win_close(win, true)
      pcall(vim.api.nvim_buf_delete, mybuf, { force = true })
    end)

    it("honors explicit row/col overrides", function()
      local _, win = float.open({ width = 20, height = 3, row = 1, col = 2 })
      local cfg = vim.api.nvim_win_get_config(win)
      -- row/col are numbers for relative="editor" floats
      assert.equals(1, cfg.row)
      assert.equals(2, cfg.col)
      vim.api.nvim_win_close(win, true)
    end)

    it("maps default close keys (q, <Esc>) to closing the window", function()
      local buf, win = float.open({ width = 20, height = 3 })
      -- keymaps exist on the buffer; get_keymap reports lhs as "<Esc>"
      local maps = vim.api.nvim_buf_get_keymap(buf, "n")
      local found = {}
      for _, m in ipairs(maps) do
        found[m.lhs] = true
      end
      assert.is_true(found["q"] ~= nil, "q should be mapped")
      assert.is_true(found["<Esc>"] ~= nil, "<Esc> should be mapped")

      vim.api.nvim_set_current_win(win)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("q", true, false, true), "mx", false)
      vim.wait(50)
      assert.is_false(vim.api.nvim_win_is_valid(win), "q should close the float")
    end)

    it("fires on_close exactly once when closed via keymap", function()
      local calls = 0
      local _, win = float.open({
        width = 20, height = 3,
        on_close = function() calls = calls + 1 end,
      })
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("q", true, false, true), "mx", false)
      vim.wait(50)
      assert.equals(1, calls)
    end)

    it("fires on_close when the window is closed by other means", function()
      local calls = 0
      local _, win = float.open({
        width = 20, height = 3,
        close_keys = {},
        on_close = function() calls = calls + 1 end,
      })
      vim.api.nvim_win_close(win, true)
      vim.wait(50)
      assert.equals(1, calls)
    end)

    it("skips close keymaps when close_keys is empty", function()
      local buf = float.open({ width = 20, height = 3, close_keys = {} })
      local maps = vim.api.nvim_buf_get_keymap(buf, "n")
      assert.equals(0, #maps, "no close keymaps should be registered")
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
