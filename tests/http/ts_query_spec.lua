local ts_query = require("poste-http.http.ts_query")

describe("ts_query.query_nodes", function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "poste_http"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "### Login",
      "POST https://api.example.com/login",
      "Content-Type: application/json",
      "",
      '{"user": "admin"}',
      "",
      "### Get Data",
      "GET https://api.example.com/data",
    })
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns captures for request blocks", function()
    local results = ts_query.query_nodes(buf, [[
      (request_block
        (separator)
        (request_name) @name)
    ]])
    assert.equals(2, #results)
    assert.equals("name", results[1].captures[1].name)
    local name = vim.trim(ts_query.node_text(results[1].captures[1].node, buf))
    assert.equals("Login", name)
  end)

  it("returns captures for headers", function()
    local results = ts_query.query_nodes(buf, [[
      (header
        (header_key) @key
        (header_value) @val)
    ]])
    assert.equals(1, #results)
    assert.equals("key", results[1].captures[1].name)
    assert.equals("val", results[1].captures[2].name)
    local key = vim.trim(ts_query.node_text(results[1].captures[1].node, buf))
    local val = vim.trim(ts_query.node_text(results[1].captures[2].node, buf))
    assert.equals("Content-Type", key)
    assert.equals("application/json", val)
  end)

  it("returns matches for separators", function()
    local results = ts_query.query_nodes(buf, [[
      (separator) @sep
    ]])
    assert.equals(2, #results)
  end)

  it("query_nodes_in_range scopes to given rows", function()
    local results = ts_query.query_nodes_in_range(buf, [[
      (request_block
        (separator)
        (request_name) @name)
    ]], 0, 5)
    assert.equals(1, #results)
    local name = vim.trim(ts_query.node_text(results[1].captures[1].node, buf))
    assert.equals("Login", name)
  end)

  it("node_at_point returns correct node", function()
    local node = ts_query.node_at_point(buf, 1, 5)
    assert.is_not_nil(node)
    local ok, t = pcall(node.type, node)
    assert.is_true(ok)
  end)

  it("parent_of_type finds request_block ancestor", function()
    local node = ts_query.node_at_point(buf, 0, 5)
    local parent = ts_query.parent_of_type(node, "request_block")
    assert.is_not_nil(parent)
  end)
end)

describe("diagnostics.update_diagnostics", function()
  local diagnostics = require("poste-http.http.diagnostics")
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "poste_http"
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("does not crash on valid HTTP file", function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "### Test",
      "GET https://example.com",
      "Accept: application/json",
    })
    diagnostics.enable(buf)
    diagnostics.update_diagnostics(buf)
    local diags = vim.diagnostic.get(buf)
    assert.is_not_nil(diags)
  end)

  it("detects duplicate @var definitions", function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "@host = https://example.com",
      "@host = https://other.com",
      "### Test",
      "GET {{host}}/api",
    })
    diagnostics.enable(buf)
    diagnostics.update_diagnostics(buf)
    local diags = vim.diagnostic.get(buf)
    local found = false
    for _, d in ipairs(diags) do
      if d.message:find("Duplicate") then
        found = true
        break
      end
    end
    assert.is_true(found)
  end)
end)