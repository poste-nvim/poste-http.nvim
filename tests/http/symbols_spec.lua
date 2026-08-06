--- Tests for outline/symbol request collection (method column).
local symbols = require("poste-http.http.symbols")

local function collect(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local requests = symbols._test.collect_requests(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  return requests
end

describe("symbols.collect_requests method column", function()
  it("shows SCRIPT for script-only orchestration blocks", function()
    local requests = collect({
      "import ./requests.http as api",
      "",
      "### Orchestration: login flow",
      "SCRIPT",
      "> {%",
      '  local r = client.run("#api.Login", {})',
      "%}",
    })
    assert.are_equal(1, #requests)
    assert.are_equal("SCRIPT", requests[1].method)
    assert.are_equal("Orchestration: login flow", requests[1].name)
  end)

  it("keeps GET for normal request blocks", function()
    local requests = collect({
      "### Get users",
      "GET /api/users",
    })
    assert.are_equal("GET", requests[1].method)
  end)

  it("keeps run for run directives", function()
    local requests = collect({
      "### Run login",
      "run #api.Login (@username=alice)",
    })
    assert.are_equal("run", requests[1].method)
  end)
end)
