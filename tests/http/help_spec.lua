local harness = require("helpers.gui_harness")

describe("help", function()
  before_each(function()
    harness.setup()
  end)

  after_each(function()
    harness.teardown()
  end)

  it("open creates a floating window with help content", function()
    local help = require("poste-http.help")
    help.open()

    local wins = harness.get_wins()
    local float_count = 0
    for _, w in pairs(wins) do
      if w.valid ~= false then float_count = float_count + 1 end
    end

    assert.is_true(float_count >= 2, "should create a floating window")
  end)

  it("open sets help content in the buffer", function()
    local help = require("poste-http.help")
    help.open()

    local has_set_lines = false
    for i = 1, #harness.calls do
      if harness.calls[i] == "nvim_buf_set_lines" then
        has_set_lines = true
      end
    end
    assert.is_true(has_set_lines, "should set buffer lines")
  end)
end)