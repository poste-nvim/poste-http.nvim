local request_deps = require("poste-http.http.request_deps")

local function resolve_deps(content, block_line)
  local result
  request_deps._resolve_content_dependencies_impl(0, "/tmp/test.http", "dev", content, block_line, function(resolved)
    result = resolved
  end)
  return result
end

local function request_b_block()
  return table.concat({
    "### request_a",
    "GET {{host}}/path/a",
    "",
    "### request_b",
    "POST {{host}}/path/b",
    "Content-Type: application/json",
    "",
    "{",
    '  "clothClassMaskMap": {{request_a.response.body.info.a_json_obj}},',
    '  "sourceImgUrl": "{{request_a.response.body.info.a_string}}"',
    "}",
  }, "\n")
end

describe("request_deps value substitution into body", function()
  after_each(function()
    request_deps.cache_response("request_a", nil)
  end)

  it("substitutes a nested JSON object from a response as inline JSON (not a Lua table)", function()
    request_deps.cache_response("request_a", {
      body = vim.json.encode({ info = { a_json_obj = { foo = "bar", num = 1 }, a_string = "hello world" } }),
    })

    local result = resolve_deps(request_b_block(), 4)
    assert.truthy(result)
    assert.is_falsy(result:match("table: 0x"))
    assert.truthy(result:match('"clothClassMaskMap": %{%"foo"%:"bar"%,"num"%:1%}'))
  end)

  it("substitutes a nested string from a response", function()
    request_deps.cache_response("request_a", {
      body = vim.json.encode({ info = { a_json_obj = {}, a_string = "hello world" } }),
    })

    local result = resolve_deps(request_b_block(), 4)
    assert.truthy(result)
    assert.truthy(result:match('"sourceImgUrl": "hello world"'))
    assert.is_falsy(result:match("%{%%request_a%.response%."))
  end)

  it("substitutes false (falsy) values instead of leaving the ref untouched", function()
    request_deps.cache_response("request_a", {
      body = vim.json.encode({ info = { a_json_obj = {}, a_string = false } }),
    })

    local result = resolve_deps(request_b_block(), 4)
    assert.truthy(result)
    assert.truthy(result:match('"sourceImgUrl": "false"'))
    assert.is_falsy(result:match("%{%%request_a%.response%."))
  end)
end)
