-- Tests for the reusable list-column layout component (poste-http.ui.columns).
--
-- The component formats rows of cells into display-width-aligned lines and
-- reports per-cell byte ranges for extmark highlighting. Column specs:
--   align    "left" (default) | "right"
--   width    fixed column width (cells padded/truncated)
--   max      column uses its natural width, capped at max (cells truncated)
--   flex     column stretches to fill the remaining line width (opts.width)
--   min/max  bounds applied to flex columns
--   lead     leading spaces before the column (default: opts.gap, 0 for first)
--   ellipsis truncate with "..." (default true; false = hard cut)

local columns = require("poste-http.ui.columns")

describe("poste-http.ui.columns", function()
  it("left-aligns fixed-width columns and pads to width", function()
    local lines, cells = columns.render(
      { { "GET", "RegisterUser", "200" } },
      { { width = 8 }, { width = 18 }, { width = 3 } },
      {}
    )
    assert.equals("GET" .. string.rep(" ", 6) .. "RegisterUser" .. string.rep(" ", 7) .. "200", lines[1])
    assert.equals(0, cells[1][1].col)
    assert.equals(3, cells[1][1].end_col)
    assert.equals("RegisterUser", cells[1][2].text)
    assert.equals(9, cells[1][2].col)
    assert.equals(28, cells[1][3].col)
    assert.equals(31, cells[1][3].end_col)
  end)

  it("right-aligns a column", function()
    local lines = columns.render(
      { { "abc", "42" }, { "x", "7" } },
      { { width = 6 }, { align = "right", width = 4 } },
      {}
    )
    assert.equals("abc" .. string.rep(" ", 6) .. "42", lines[1])
    assert.equals("x" .. string.rep(" ", 9) .. "7", lines[2])
  end)

  it("caps column width at max, truncating long cells with an ellipsis", function()
    local lines = columns.render(
      { { "short" }, { "ThisNameIsWayTooLongForTheList" } },
      { { max = 10 } },
      {}
    )
    assert.equals("short" .. string.rep(" ", 5), lines[1])
    assert.equals("ThisNam...", lines[2])
  end)

  it("hard-cuts when ellipsis is disabled", function()
    local lines = columns.render(
      { { "DELETE" } },
      { { width = 3, ellipsis = false } },
      {}
    )
    assert.equals("DEL", lines[1])
  end)

  it("stretches a flex column to fill the total width", function()
    local lines = columns.render(
      { { "GET", "RegisterUser", "200" }, { "POST", "X", "-" } },
      { { width = 8 }, { flex = true }, { width = 3 } },
      { width = 30 }
    )
    assert.equals(30, #lines[1])
    assert.equals(30, #lines[2])
    assert.equals("RegisterUser" .. string.rep(" ", 5), lines[1]:sub(10, 26))
    assert.equals("X" .. string.rep(" ", 16), lines[2]:sub(10, 26))
  end)

  it("supports per-column leading gaps", function()
    local lines = columns.render(
      { { "a", "b", "c", "d" } },
      { { width = 1 }, { lead = 2, width = 1 }, { lead = 1, width = 1 }, { lead = 3, width = 1 } },
      {}
    )
    assert.equals("a  b c   d", lines[1])
  end)

  it("reports per-cell byte ranges for highlighting", function()
    local _, cells = columns.render(
      { { "GET", "User", "200", "12.00 ms", "07:26" } },
      { { width = 8 }, { flex = true, lead = 0 }, { width = 3, lead = 0 }, { lead = 1, width = 9 }, { lead = 2 } },
      { width = 46 }
    )
    assert.equals(0, cells[1][1].col)
    assert.equals(3, cells[1][1].end_col)
    assert.equals(8, cells[1][2].col)
    assert.equals(12, cells[1][2].end_col)
    assert.equals(26, cells[1][3].col)
    assert.equals(29, cells[1][3].end_col)
    assert.equals(30, cells[1][4].col)
    assert.equals(38, cells[1][4].end_col)
    assert.equals(41, cells[1][5].col)
    assert.equals(46, cells[1][5].end_col)
  end)

  it("supports a right-aligned stretched column with max-width neighbors", function()
    local lines = columns.render(
      { { "alpha", "v1", "99" }, { "b", "v2", "7" } },
      { { max = 6 }, { align = "right", flex = true }, { align = "right", max = 4 } },
      { width = 20 }
    )
    assert.equals(20, #lines[1])
    assert.equals(20, #lines[2])
    assert.matches("^alpha +v1 +99$", lines[1])
    assert.matches("^b +v2 +7$", lines[2])
  end)

  it("treats missing cells as empty strings", function()
    local lines = columns.render({ { "a" } }, { { width = 4 }, { width = 4 } }, {})
    assert.equals("a" .. string.rep(" ", 8), lines[1])
  end)

  it("stringifies number cells", function()
    local lines = columns.render({ { 42, "x" } }, { { width = 4 }, { width = 1 } }, {})
    assert.equals("42" .. string.rep(" ", 3) .. "x", lines[1])
  end)

  it("supports a custom pad character", function()
    local lines = columns.render({ { "ab" } }, { { width = 4 } }, { pad = "." })
    assert.equals("ab..", lines[1])
  end)

  it("truncates by display width, keeping wide characters intact", function()
    local lines = columns.render({ { "中文测试" } }, { { max = 5 } }, {})
    assert.equals("中...", lines[1])
  end)

  it("pads wide characters by display width, not byte length", function()
    local lines = columns.render({ { "中文" } }, { { width = 4 } }, {})
    assert.equals("中文", lines[1])
    assert.equals(6, #lines[1])
  end)

  it("errors when a flex column has no total width", function()
    assert.has_error(function()
      columns.render({ { "a", "b" } }, { { width = 1 }, { flex = true } }, {})
    end)
  end)
end)
