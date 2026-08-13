local state = require("poste-http.state")
local global_headers = require("poste-http.http.global_headers")

describe("state.global_headers", function()
  before_each(function()
    state.global_headers = {}
    state.global_headers_sources = {}
  end)

  it("starts empty", function()
    assert.is_table(state.global_headers)
    assert.equals(0, vim.tbl_count(state.global_headers))
  end)

  it("set_global_header stores a value", function()
    state.set_global_header("Authorization", "Bearer tok1")
    assert.equals("Bearer tok1", state.global_headers["Authorization"])
  end)

  it("set_global_header overwrites existing value", function()
    state.set_global_header("X-Custom", "v1")
    state.set_global_header("X-Custom", "v2")
    assert.equals("v2", state.global_headers["X-Custom"])
  end)

  it("remove_global_header removes a header", function()
    state.set_global_header("X-Custom", "v1")
    state.remove_global_header("X-Custom")
    assert.is_nil(state.global_headers["X-Custom"])
  end)

  it("clear_global_headers removes all", function()
    state.set_global_header("A", "1")
    state.set_global_header("B", "2")
    state.clear_global_headers()
    assert.equals(0, vim.tbl_count(state.global_headers))
  end)

  it("set_global_header records source when _exec_context is set", function()
    state._exec_context = { file = "/test.http", line = 10 }
    state.set_global_header("X-Token", "abc")
    assert.is_not_nil(state.global_headers_sources["X-Token"])
    assert.equals("/test.http", state.global_headers_sources["X-Token"].file)
    assert.equals(10, state.global_headers_sources["X-Token"].line)
    state._exec_context = nil
  end)

  it("remove_global_header also clears source", function()
    state._exec_context = { file = "/test.http", line = 10 }
    state.set_global_header("X-Token", "abc")
    state.remove_global_header("X-Token")
    assert.is_nil(state.global_headers["X-Token"])
    assert.is_nil(state.global_headers_sources["X-Token"])
    state._exec_context = nil
  end)
end)

describe("global_headers.merge", function()
  before_each(function()
    state.global_headers = {}
  end)

  it("returns per-request headers unchanged when no global headers", function()
    local per_req = { { "Content-Type", "application/json" } }
    local result = global_headers.merge(per_req)
    assert.same(per_req, result)
  end)

  it("returns empty when no headers at all", function()
    assert.same({}, global_headers.merge(nil))
    assert.same({}, global_headers.merge({}))
  end)

  it("includes global headers when no per-request headers", function()
    state.set_global_header("Authorization", "Bearer tok1")
    local result = global_headers.merge({})
    assert.equals(1, #result)
    assert.equals("Authorization", result[1][1])
    assert.equals("Bearer tok1", result[1][2])
  end)

  it("merges global and per-request headers", function()
    state.set_global_header("Authorization", "Bearer tok1")
    local per_req = { { "Content-Type", "application/json" } }
    local result = global_headers.merge(per_req)
    assert.equals(2, #result)
    local names = { result[1][1]:lower(), result[2][1]:lower() }
    table.sort(names)
    assert.same({ "authorization", "content-type" }, names)
  end)

  it("per-request header overrides global header (case-insensitive)", function()
    state.set_global_header("Authorization", "Bearer global")
    local per_req = { { "authorization", "Bearer local" } }
    local result = global_headers.merge(per_req)
    assert.equals(1, #result)
    assert.equals("authorization", result[1][1])
    assert.equals("Bearer local", result[1][2])
  end)

  it("per-request header overrides global with different case in global", function()
    state.set_global_header("authorization", "Bearer global")
    local per_req = { { "Authorization", "Bearer local" } }
    local result = global_headers.merge(per_req)
    assert.equals(1, #result)
    assert.equals("Authorization", result[1][1])
    assert.equals("Bearer local", result[1][2])
  end)

  it("preserves order: global first, then per-request in append order", function()
    state.set_global_header("X-Global", "g1")
    state.set_global_header("X-Global2", "g2")
    local per_req = { { "X-Local", "l1" } }
    local result = global_headers.merge(per_req)
    assert.equals(3, #result)
    assert.equals("X-Global", result[1][1])
    assert.equals("X-Local", result[3][1])
  end)

  it("resolves {{var}} in global header values when resolver given", function()
    state.set_global_header("Authorization", "Bearer {{token}}")
    local resolver = {
      substitute = function(_, input)
        return input:gsub("{{token}}", "resolved-token")
      end,
    }
    local result = global_headers.merge({}, resolver)
    assert.equals("Bearer resolved-token", result[1][2])
  end)

  it("keeps raw {{var}} in global header values when no resolver", function()
    state.set_global_header("Authorization", "Bearer {{token}}")
    local result = global_headers.merge({})
    assert.equals("Bearer {{token}}", result[1][2])
  end)

  it("empty global headers does not trigger merge logic", function()
    -- state.global_headers is empty table
    local per_req = { { "X", "1" } }
    local result = global_headers.merge(per_req)
    assert.same(per_req, result)
  end)
end)

describe("state.global_headers in clear_request_scoped", function()
  it("survives clear_request_scoped (persistent)", function()
    state.set_global_header("X-Persist", "should-stay")
    state.clear_request_scoped()
    assert.equals("should-stay", state.global_headers["X-Persist"])
    state.clear_global_headers()
  end)
end)

describe("scripts sandbox client.global.header API", function()
  local scripts = require("poste-http.http.scripts")

  before_each(function()
    state.global_headers = {}
    state.global_headers_sources = {}
  end)

  it("client.global.header.set stores a header", function()
    local result = scripts.run_pre_script([[
      client.global.header.set("Authorization", "Bearer tok1")
    ]], { variables = {}, env = {} })
    assert.is_nil(result.error)
    assert.equals("Bearer tok1", state.global_headers["Authorization"])
  end)

  it("client.global.header.get reads a header", function()
    state.set_global_header("X-Custom", "val1")
    local result = scripts.run_pre_script([[
      local v = client.global.header.get("X-Custom")
      client.log(v)
    ]], { variables = {}, env = {} })
    assert.is_nil(result.error)
    assert.is_not_nil(result.logs)
    assert.equals("val1", result.logs[1])
  end)

  it("client.global.header.remove deletes a header", function()
    state.set_global_header("X-Custom", "val1")
    local result = scripts.run_pre_script([[
      client.global.header.remove("X-Custom")
    ]], { variables = {}, env = {} })
    assert.is_nil(result.error)
    assert.is_nil(state.global_headers["X-Custom"])
  end)

  it("client.global.header.clear removes all headers", function()
    state.set_global_header("A", "1")
    state.set_global_header("B", "2")
    local result = scripts.run_pre_script([[
      client.global.header.clear()
    ]], { variables = {}, env = {} })
    assert.is_nil(result.error)
    assert.equals(0, vim.tbl_count(state.global_headers))
  end)
end)

describe("assertions sandbox client.global.header API", function()
  local assertions = require("poste-http.http.assertions")

  before_each(function()
    state.global_headers = {}
    state.global_headers_sources = {}
  end)

  it("client.global.header.set stores a header in post-script", function()
    local response = { status = 200, headers = {}, body = "{}" }
    local result = assertions.run_assertions(response, [[
      client.global.header.set("Authorization", "Bearer tok2")
    ]], { variables = {}, env = {} })
    assert.is_nil(result.error)
    assert.equals("Bearer tok2", state.global_headers["Authorization"])
  end)

  it("client.global.header.get reads a header in post-script", function()
    state.set_global_header("X-Custom", "val1")
    local response = { status = 200, headers = {}, body = "{}" }
    local result = assertions.run_assertions(response, [[
      local v = client.global.header.get("X-Custom")
      client.log(v)
    ]], { variables = {}, env = {} })
    assert.is_nil(result.error)
    assert.equals("val1", result.logs[1])
  end)

  it("client.global.header.remove in post-script", function()
    state.set_global_header("X-Custom", "val1")
    local response = { status = 200, headers = {}, body = "{}" }
    local result = assertions.run_assertions(response, [[
      client.global.header.remove("X-Custom")
    ]], { variables = {}, env = {} })
    assert.is_nil(result.error)
    assert.is_nil(state.global_headers["X-Custom"])
  end)

  it("client.global.header.clear in post-script", function()
    state.set_global_header("A", "1")
    state.set_global_header("B", "2")
    local response = { status = 200, headers = {}, body = "{}" }
    local result = assertions.run_assertions(response, [[
      client.global.header.clear()
    ]], { variables = {}, env = {} })
    assert.is_nil(result.error)
    assert.equals(0, vim.tbl_count(state.global_headers))
  end)
end)