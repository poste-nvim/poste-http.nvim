local harness = require("helpers.gui_harness")

describe("outline", function()
  before_each(function()
    harness.setup()
    package.loaded["poste-http.http.outline"] = nil
  end)

  after_each(function()
    harness.teardown()
  end)

  it("open creates a floating window", function()
    local outline = require("poste-http.http.outline")
    outline.open()

    local wins = harness.get_wins()
    local win_count = 0
    for _, w in pairs(wins) do
      if w.valid ~= false then win_count = win_count + 1 end
    end
    assert.is_true(win_count >= 2, "should create a floating window")
  end)

  it("close removes the floating window", function()
    local outline = require("poste-http.http.outline")
    outline.open()
    outline.close()

    local wins = harness.get_wins()
    local valid_count = 0
    for _, w in pairs(wins) do
      if w.valid ~= false then valid_count = valid_count + 1 end
    end
    assert.equals(1, valid_count, "should restore to single window")
  end)
end)