-- Tests for the winbar tab-row builder (poste-http.ui.winbar).
--
-- Replaces the duplicated TabLineSel/TabLine concatenation in
-- http/buffer.lua (response window) and http/history.lua (detail window).

local winbar = require("poste-http.ui.winbar")

describe("poste-http.ui.winbar", function()
  local tabs = {
    { id = "body", label = "Body [B]" },
    { id = "verbose", label = "Verb [E]" },
    { id = "asserts", label = "Asserts [A]" },
  }

  it("marks the active tab with TabLineSel and others with TabLine", function()
    local out = winbar.render_tabs(tabs, "verbose")
    assert.equals("%#TabLine# Body [B] %*%#TabLineSel# Verb [E] %*%#TabLine# Asserts [A] %*", out)
  end)

  it("treats a nil active id as none-selected", function()
    local out = winbar.render_tabs(tabs, nil)
    assert.is_nil(out:find("TabLineSel", 1, true))
    assert.equals(3, select(2, out:gsub("%%#TabLine#", "")))
  end)

  it("returns an empty string for no tabs", function()
    assert.equals("", winbar.render_tabs({}, "body"))
    assert.equals("", winbar.render_tabs(nil, "body"))
  end)

  describe("cycle", function()
    it("advances forward and wraps", function()
      assert.equals("verbose", winbar.cycle(tabs, "body", 1))
      assert.equals("asserts", winbar.cycle(tabs, "verbose", 1))
      assert.equals("body", winbar.cycle(tabs, "asserts", 1))
    end)

    it("steps backward and wraps", function()
      assert.equals("body", winbar.cycle(tabs, "verbose", -1))
      assert.equals("asserts", winbar.cycle(tabs, "body", -1))
    end)

    it("defaults direction to forward and tolerates unknown ids", function()
      assert.equals("verbose", winbar.cycle(tabs, "unknown", nil))
    end)

    it("returns nil for empty tab lists", function()
      assert.is_nil(winbar.cycle({}, "body", 1))
      assert.is_nil(winbar.cycle(nil, "body", 1))
    end)
  end)
end)
