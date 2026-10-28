local harness = require("helpers.gui_harness")

describe("script_snippet", function()
  before_each(function()
    harness.setup()
    package.loaded["poste-http.http.script_snippet"] = nil
  end)

  after_each(function()
    harness.teardown()
  end)

  it("setup registers autocmds and keymap", function()
    local snippet = require("poste-http.http.script_snippet")
    snippet.setup()

    local autocmds = harness.get_autocmds()
    local events = {}
    for _, entry in ipairs(autocmds) do
      local ev = entry.events
      if type(ev) == "string" then
        events[ev] = true
      elseif type(ev) == "table" then
        for _, e in ipairs(ev) do events[e] = true end
      end
    end

    assert.is_true(events["TextChangedI"], "should register TextChangedI autocmd")
    assert.is_true(events["InsertLeave"], "should register InsertLeave autocmd")
    assert.is_true(events["BufDelete"], "should register BufDelete autocmd")

    -- The <Tab> expansion used to be a GLOBAL insert-mode map registered in
    -- setup(), shadowing the user's own <Tab> in every filetype. It is now
    -- buffer-local and config-driven ("script_snippet_expand" in
    -- buffer_setup.setup_buffer_keymaps), so setup() must NOT register it.
    local kms = harness.get_keymaps()
    for _, modes in pairs(kms) do
      assert.falsy(modes["i"] and modes["i"]["<Tab>"],
        "setup() must not register a global insert-mode <Tab>")
    end
  end)

  it("Tab expansion is registered buffer-locally by setup_buffer_keymaps", function()
    local buffer_setup = require("poste-http.buffer_setup")
    buffer_setup.setup_buffer_keymaps(vim.api.nvim_get_current_buf())

    local kms = harness.get_keymaps()
    local has_tab = false
    for _, modes in pairs(kms) do
      if modes["i"] and modes["i"]["<Tab>"] then
        has_tab = true
      end
    end
    assert.is_true(has_tab, "buffer_setup should register the insert-mode <Tab> expansion")
  end)

  it("refresh shows hint when line contains only >", function()
    local snippet = require("poste-http.http.script_snippet")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ">" })
    vim.fn.line = function() return 1 end

    snippet.refresh()

    local has_extmark = false
    for i = 1, #harness.calls do
      if harness.calls[i] == "nvim_buf_set_extmark" then
        has_extmark = true
      end
    end
    assert.is_true(has_extmark, "should set extmark hint")
  end)

  it("clear removes extmark and resets state", function()
    local snippet = require("poste-http.http.script_snippet")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ">" })
    vim.fn.line = function() return 1 end

    snippet.refresh()
    harness.reset_calls()
    snippet.clear()

    local has_clear = false
    for i = 1, #harness.calls do
      if harness.calls[i] == "nvim_buf_clear_namespace" then
        has_clear = true
      end
    end
    assert.is_true(has_clear, "should clear namespace on clear")
  end)
end)