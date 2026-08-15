-- Tests for copy.lua: copy_as_curl exports request blocks as curl commands.

local copy = require("poste-http.http.copy")

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe("copy_as_curl", function()
  it("quotes IPv6 URLs so the [] survive shell parsing", function()
    local buf = make_buf({
      "### Ping",
      "GET http://[::1]:8080/health",
    })
    vim.api.nvim_set_current_buf(buf)
    vim.fn.setpos(".", { 0, 2, 1, 0 })

    local cmd = copy.copy_as_curl()
    assert.is_not_nil(cmd)
    assert.matches("'http://%[::1%]:8080/health'", cmd)
  end)

  it("leaves simple URLs unquoted", function()
    local buf = make_buf({
      "GET https://api.example.com/users",
    })
    vim.api.nvim_set_current_buf(buf)
    vim.fn.setpos(".", { 0, 1, 1, 0 })

    local cmd = copy.copy_as_curl()
    assert.is_not_nil(cmd)
    assert.matches("https://api%.example%.com/users", cmd)
  end)

  it("includes headers and method", function()
    local buf = make_buf({
      "### Create",
      "POST https://api.example.com/users",
      "Content-Type: application/json",
      "",
      '{"name": "test"}',
    })
    vim.api.nvim_set_current_buf(buf)
    vim.fn.setpos(".", { 0, 2, 1, 0 })

    local cmd = copy.copy_as_curl()
    assert.is_not_nil(cmd)
    assert.matches("-X POST", cmd)
    assert.matches("Content%-Type: application/json", cmd)
    assert.matches("data%-binary", cmd)
  end)

  it("returns error when no request block at cursor (blank separator line)", function()
    local buf = make_buf({
      "### Block one",
      "GET https://example.com/a",
      "",
      "### Block two",
      "GET https://example.com/b",
    })
    vim.api.nvim_set_current_buf(buf)
    vim.fn.setpos(".", { 0, 3, 1, 0 })

    local cmd, err = copy.copy_as_curl()
    assert.is_nil(cmd)
    assert.matches("No request block", err)
  end)

  it("resolves the block from a trailing comment line", function()
    local buf = make_buf({
      "### Block one",
      "GET https://example.com/a",
      "",
      "-- trailing comment",
    })
    vim.api.nvim_set_current_buf(buf)
    vim.fn.setpos(".", { 0, 4, 1, 0 })

    local cmd = copy.copy_as_curl()
    assert.is_not_nil(cmd)
  end)
end)
