--- Tests for outline/symbol request collection (method column).
local symbols = require("poste-http.http.symbols")

local function collect(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local requests = symbols.collect_requests(buf)
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
    assert.are_equal("RUN", requests[1].method)
  end)

  it("finds GET after pre-script with space in tag", function()
    local requests = collect({
      "### Session test",
      "< {% client.global.set('x', '1') %}",
      "GET /anything/session-test",
      "Authorization: Bearer {{session_token}}",
    })
    assert.are_equal(1, #requests)
    assert.are_equal("GET", requests[1].method)
    assert.are_equal("/anything/session-test", requests[1].url_path)
  end)

  it("skips non-HTTP lines and finds the actual request", function()
    local requests = collect({
      "### Multiline var",
      "# Tests: multi-line variable",
      "@headers_block=>>>",
      "X-Custom-Auth: Bearer token123",
      "X-Client-Id: poste-test",
      "<<<",
      "GET {{host}}/anything/multiline-var",
      "{{headers_block}}",
    })
    assert.are_equal(1, #requests)
    assert.are_equal("GET", requests[1].method)
    -- extract_url_path strips {{var}} wrappers, leaving just the path
    assert.are_equal("/anything/multiline-var", requests[1].url_path)
  end)

  it("finds the request line beyond 20 lines into the block", function()
    local lines = { "### Deep block" }
    for i = 1, 30 do
      lines[#lines + 1] = "@var" .. i .. " = " .. i
    end
    lines[#lines + 1] = "POST /deep"
    local requests = collect(lines)
    assert.are_equal(1, #requests)
    assert.are_equal("POST", requests[1].method)
    assert.are_equal("/deep", requests[1].url_path)
  end)

  it("survives long CJK request names without truncation errors", function()
    local long_name = string.rep("请求", 20)
    local requests = collect({
      "### " .. long_name,
      "GET /cjk",
    })
    assert.are_equal(1, #requests)
    assert.are_equal("GET", requests[1].method)
    assert.are_equal(long_name, requests[1].name)
  end)
end)
