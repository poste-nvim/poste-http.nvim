-- Tests for the Poste HTTP history list rendering.
--
-- The list line is built by a pure function (history._test.format_list_line)
-- so the layout can be locked down without a floating window. Extmark
-- placement is driven by the column offsets it returns.

local history = require("poste-http.http.history")

local function entry(name, opts)
  opts = opts or {}
  return {
    name = name,
    time = opts.time or os.time({ year = 2026, month = 8, day = 7, hour = 7, min = 26, sec = 0 }),
    response = {
      latency_ms = opts.latency_ms,
      status = opts.status or 200,
      metadata = { method = opts.method or "GET" },
    },
  }
end

describe("history._test.format_list_line", function()
  it("formats POST with name, elapsed and timestamp like the requested layout", function()
    local line, info = history._test.format_list_line(entry("RegisterUser", {
      method = "POST",
      latency_ms = 12,
    }), 18)
    assert.equals("POST    RegisterUser      200 12.00 ms  " .. os.date("%H:%M", entry("RegisterUser").time), line)
    assert.equals("PosteMethodPOST", info.method_hl)
    assert.equals(0, info.method_col)
    assert.equals(4, info.method_end)
    assert.equals(8 + 18, info.status_col)
    assert.equals("200", info.status)
    assert.equals("PosteStatus2xx", info.status_hl)
    assert.equals(8 + 18 + 4, info.elapsed_col)
    assert.equals(8 + 18 + 4 + 8 + 2, info.ts_col)
  end)

  it("shows status before elapsed", function()
    local line = history._test.format_list_line(entry("GetUser", { latency_ms = 9.23 }), 18)
    assert.matches("^GET%s+GetUser%s+200%s+9%.23 ms%s+%d%d:%d%d$", line)
  end)

  it("keeps three-digit elapsed values aligned", function()
    local line, info = history._test.format_list_line(entry("GetProfile", { status = 404, latency_ms = 123 }), 18)
    assert.matches("^GET%s+GetProfile%s+404%s+123%.00 ms%s+%d%d:%d%d$", line)
    assert.equals("PosteStatus4xx", info.status_hl)
  end)

  it("colors status codes by class like the verbose view", function()
    local _, info = history._test.format_list_line(entry("Ok", { status = 200, latency_ms = 5 }), 18)
    assert.equals("PosteStatus2xx", info.status_hl)

    _, info = history._test.format_list_line(entry("Moved", { status = 301, latency_ms = 5 }), 18)
    assert.equals("PosteStatus3xx", info.status_hl)

    _, info = history._test.format_list_line(entry("Broken", { status = 503, latency_ms = 5 }), 18)
    assert.equals("PosteStatus5xx", info.status_hl)
  end)

  it("shows '-' for failed requests with status 0", function()
    local line, info = history._test.format_list_line(entry("Failed", { method = "", status = 0, latency_ms = 0 }), 18)
    assert.matches("^%-%s+Failed%s+%-%s+0%.00 ms%s+%d%d:%d%d$", line)
    assert.equals("-", info.status)
    assert.equals("Comment", info.status_hl)
  end)

  it("formats elapsed above one second as seconds", function()
    local line = history._test.format_list_line(entry("Slow", { latency_ms = 1200 }), 18)
    assert.matches("1%.20 s", line)
  end)

  it("shows '-' when latency is missing", function()
    local line = history._test.format_list_line(entry("NoLatency", { latency_ms = nil }), 18)
    assert.matches("%-%s+%d%d:%d%d$", line)
  end)

  it("maps SCRIPT to the script highlight group", function()
    local _, info = history._test.format_list_line(entry("Run", { method = "SCRIPT", latency_ms = 5 }), 18)
    assert.equals("SCRIPT", info.method)
    assert.equals("PosteMethodScript", info.method_hl)
  end)

  it("maps unknown methods to PosteMethodOther", function()
    local _, info = history._test.format_list_line(entry("Custom", { method = "FOO", latency_ms = 5 }), 18)
    assert.equals("PosteMethodOther", info.method_hl)
  end)

  it("shows '-' for entries without a method", function()
    local line, info = history._test.format_list_line(entry("Failed", { method = "", latency_ms = 0 }), 18)
    assert.matches("^%-%s+Failed%s+200", line)
    assert.equals("-", info.method)
    assert.equals("PosteMethodOther", info.method_hl)
  end)

  it("falls back to the response metadata method when entry.method is absent", function()
    local e = entry("Direct", { latency_ms = 5 })
    e.method = nil
    local _, info = history._test.format_list_line(e, 18)
    assert.equals("GET", info.method)
    assert.equals("PosteMethodGET", info.method_hl)
  end)

  it("truncates long names with an ellipsis", function()
    local line = history._test.format_list_line(entry("ThisNameIsWayTooLongForTheList", { latency_ms = 5 }), 18)
    assert.equals("ThisNameIsWayTo...", line:sub(9, 9 + 17))
  end)
end)
