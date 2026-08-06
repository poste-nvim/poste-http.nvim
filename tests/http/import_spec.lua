--- Tests for the import/run cross-file reference resolution module.
local import_mod = require("poste-http.http.import")
local state = require("poste-http.state")
local _test = import_mod._test

describe("parse_import_line", function()
  it("parses bare import", function()
    local r = _test.parse_import_line("import ./auth.http")
    assert.are_equal("bare", r.type)
    assert.are_equal("./auth.http", r.path)
  end)

  it("parses aliased import", function()
    local r = _test.parse_import_line("import ./orders.http as orders")
    assert.are_equal("aliased", r.type)
    assert.are_equal("./orders.http", r.path)
    assert.are_equal("orders", r.alias)
  end)

  it("rejects non-import lines", function()
    assert.is_nil(_test.parse_import_line("### Request"))
    assert.is_nil(_test.parse_import_line("@var = value"))
    assert.is_nil(_test.parse_import_line(""))
    assert.is_nil(_test.parse_import_line("run #Login"))
  end)

  it("handles leading whitespace", function()
    local r = _test.parse_import_line("  import ./auth.http")
    assert.are_equal("bare", r.type)
  end)
end)

describe("parse_run_line", function()
  it("parses run #Name", function()
    local r = _test.parse_run_line("run #Login")
    assert.are_equal("by_name", r.type)
    assert.are_equal("Login", r.name)
    assert.is_true(next(r.vars) == nil)
  end)

  it("parses run #alias.Name", function()
    local r = _test.parse_run_line("run #orders.ListOrders")
    assert.are_equal("by_alias", r.type)
    assert.are_equal("orders", r.alias)
    assert.are_equal("ListOrders", r.name)
  end)

  it("parses run ./path", function()
    local r = _test.parse_run_line("run ./batch.http")
    assert.are_equal("by_path", r.type)
    assert.are_equal("./batch.http", r.path)
  end)

  it("parses run with variable overrides", function()
    local r = _test.parse_run_line("run #Login (@token=xyz)")
    assert.are_equal("by_name", r.type)
    assert.are_equal("Login", r.name)
    assert.are_equal("xyz", r.vars.token)
  end)

  it("parses run with multiple variable overrides", function()
    local r = _test.parse_run_line("run #Login (@token=xyz, @env=staging)")
    assert.are_equal("by_name", r.type)
    assert.are_equal("xyz", r.vars.token)
    assert.are_equal("staging", r.vars.env)
  end)

  it("rejects non-run lines", function()
    assert.is_nil(_test.parse_run_line("### Request"))
    assert.is_nil(_test.parse_run_line(""))
    assert.is_nil(_test.parse_run_line("import ./auth.http"))
  end)
end)

describe("resolve_path", function()
  it("keeps absolute paths", function()
    local r = _test.resolve_path("/absolute/path.http", "/dir")
    assert.are_equal("/absolute/path.http", r)
  end)

  it("resolves relative paths", function()
    local r = _test.resolve_path("./sub/file.http", "/base/dir")
    assert.are_equal("/base/dir/sub/file.http", r)
  end)
end)

describe("extract_request_names", function()
  it("extracts named blocks", function()
    local content = "### Login\nGET /api/login\n\n### Logout\nGET /api/logout\n"
    local names = _test.extract_request_names(content)
    assert.are_equal(2, #names)
    assert.are_equal("Login", names[1].name)
    assert.are_equal(1, names[1].line)
    assert.are_equal("Logout", names[2].name)
    assert.are_equal(4, names[2].line)
  end)

  it("returns empty for no blocks", function()
    local content = "@var = value\n"
    local names = _test.extract_request_names(content)
    assert.are_equal(0, #names)
  end)

  it("ignores nameless ###", function()
    local content = "###\nGET /api\n"
    local names = _test.extract_request_names(content)
    assert.are_equal(0, #names)
  end)
end)

describe("resolve_reference", function()
  local index = {
    bare = {
      {
        path = "/dir/auth.http",
        requests = { { name = "Login", line = 1 }, { name = "Logout", line = 4 } },
      },
    },
    aliased = {
      orders = {
        path = "/dir/orders.http",
        requests = { { name = "ListOrders", line = 1 }, { name = "GetOrder", line = 5 } },
      },
    },
    errors = {},
    warnings = {},
  }

  it("resolves bare reference", function()
    local r = _test.resolve_reference("Login", index)
    assert.are_equal("/dir/auth.http", r.path)
    assert.are_equal(1, r.line)
  end)

  it("resolves aliased reference", function()
    local r = _test.resolve_reference("orders.ListOrders", index)
    assert.are_equal("/dir/orders.http", r.path)
    assert.are_equal(1, r.line)
  end)

  it("returns nil for unknown reference", function()
    assert.is_nil(_test.resolve_reference("Unknown", index))
  end)

  it("returns nil for unknown alias", function()
    assert.is_nil(_test.resolve_reference("bad.Name", index))
  end)
end)

describe("Lua import support", function()
  describe("parse_import_line with .lua", function()
    it("parses import ./variables.lua as m", function()
      local r = _test.parse_import_line("import ./variables.lua as m")
      assert.are_equal("aliased", r.type)
      assert.are_equal("./variables.lua", r.path)
      assert.are_equal("m", r.alias)
    end)

    it("parses import ./vars.lua (bare)", function()
      local r = _test.parse_import_line("import ./vars.lua")
      assert.are_equal("bare", r.type)
      assert.are_equal("./vars.lua", r.path)
    end)
  end)

  describe("build_import_index with .lua", function()
    it("loads Lua module exports", function()
      local tmpfile = os.tmpname() .. ".lua"
      local f = io.open(tmpfile, "w")
      f:write("return { an_int_value = 100, name = 'lex', tags = { 'rust', 'lua' } }")
      f:close()

      local imports = {
        { type = "aliased", path = tmpfile, alias = "m" },
      }
      local index = import_mod.build_import_index(imports, "/tmp")

      assert.are_equal(0, #index.errors)
      assert.is_not_nil(index.aliased.m)
      assert.is_true(index.aliased.m.is_lua)
      assert.are_equal(100, index.aliased.m.exports.an_int_value)
      assert.are_equal("lex", index.aliased.m.exports.name)
      assert.are_equal("rust", index.aliased.m.exports.tags[1])

      os.remove(tmpfile)
    end)

    it("reports Lua load errors", function()
      local tmpfile = os.tmpname() .. ".lua"
      local f = io.open(tmpfile, "w")
      f:write("this is not valid lua {{{")
      f:close()

      local imports = {
        { type = "aliased", path = tmpfile, alias = "bad" },
      }
      local index = import_mod.build_import_index(imports, "/tmp")

      assert.are_equal(1, #index.errors)
      assert.matches("Cannot load Lua import", index.errors[1])

      os.remove(tmpfile)
    end)

    it("reports Lua runtime errors", function()
      local tmpfile = os.tmpname() .. ".lua"
      local f = io.open(tmpfile, "w")
      f:write("error('boom')")
      f:close()

      local imports = {
        { type = "aliased", path = tmpfile, alias = "bad" },
      }
      local index = import_mod.build_import_index(imports, "/tmp")

      assert.are_equal(1, #index.errors)
      assert.matches("Cannot execute Lua import", index.errors[1])

      os.remove(tmpfile)
    end)

    it("loads bare Lua import", function()
      local tmpfile = os.tmpname() .. ".lua"
      local f = io.open(tmpfile, "w")
      f:write("return { key = 'value' }")
      f:close()

      local imports = {
        { type = "bare", path = tmpfile },
      }
      local index = import_mod.build_import_index(imports, "/tmp")

      assert.are_equal(0, #index.errors)
      assert.are_equal(1, #index.bare)
      assert.is_true(index.bare[1].is_lua)
      assert.are_equal("value", index.bare[1].exports.key)

      os.remove(tmpfile)
    end)
  end)

  describe("resolve_path_for_export", function()
    it("resolves top-level key", function()
      local exports = { name = "lex", age = 23 }
      assert.are_equal("lex", _test.resolve_path_for_export(exports, "name"))
      assert.are_equal(23, _test.resolve_path_for_export(exports, "age"))
    end)

    it("resolves nested key", function()
      local exports = { person = { name = "lex", age = 23 } }
      assert.are_equal("lex", _test.resolve_path_for_export(exports, "person.name"))
      assert.are_equal(23, _test.resolve_path_for_export(exports, "person.age"))
    end)

    it("resolves array index", function()
      local exports = { tags = { "rust", "lua", "neovim" } }
      assert.are_equal("rust", _test.resolve_path_for_export(exports, "tags[1]"))
      assert.are_equal("lua", _test.resolve_path_for_export(exports, "tags[2]"))
      assert.are_equal("neovim", _test.resolve_path_for_export(exports, "tags[3]"))
    end)

    it("resolves deeply nested path", function()
      local exports = { data = { items = { { id = 1, name = "alice" } } } }
      assert.are_equal(1, _test.resolve_path_for_export(exports, "data.items[1].id"))
      assert.are_equal("alice", _test.resolve_path_for_export(exports, "data.items[1].name"))
    end)

    it("returns nil for unknown key", function()
      local exports = { name = "lex" }
      assert.is_nil(_test.resolve_path_for_export(exports, "unknown"))
      assert.is_nil(_test.resolve_path_for_export(exports, "name.unknown"))
    end)
  end)

  describe("value_to_http_string", function()
    it("converts number to string", function()
      assert.are_equal("100", _test.value_to_http_string(100))
    end)

    it("keeps string as-is", function()
      assert.are_equal("hello", _test.value_to_http_string("hello"))
    end)

    it("encodes table as JSON", function()
      local result = _test.value_to_http_string({ name = "lex", age = 23 })
      -- vim.json.encode may order keys differently; check structure
      local ok, decoded = pcall(vim.json.decode, result)
      assert.is_true(ok)
      assert.are_equal("lex", decoded.name)
      assert.are_equal(23, decoded.age)
    end)

    it("converts boolean to string", function()
      assert.are_equal("true", _test.value_to_http_string(true))
    end)

    it("returns empty for nil", function()
      assert.are_equal("", _test.value_to_http_string(nil))
    end)
  end)

  describe("resolve_lua_imports", function()
    it("replaces {{alias.key}} in content", function()
      local tmpfile = os.tmpname() .. ".lua"
      local f = io.open(tmpfile, "w")
      f:write("return { an_int_value = 100, name = 'lex' }")
      f:close()

      local content = ("import %s as m\n\n### Test\nPOST /post/{{m.an_int_value}}\nContent-Type: application/json\n\n{\"name\": \"{{m.name}}\"}"):format(tmpfile)
      local result = import_mod.resolve_lua_imports(content, "/tmp")
      assert.matches("POST /post/100", result)
      assert.matches('"name": "lex"', result)

      os.remove(tmpfile)
    end)

    it("replaces @var = alias.key lines", function()
      local tmpfile = os.tmpname() .. ".lua"
      local f = io.open(tmpfile, "w")
      f:write("return { person = { name = 'lex', age = 23 } }")
      f:close()

      local content = ("import %s as m\n\n@my_person = m.person\n\n### Test\nPOST /test\n\n{{my_person}}"):format(tmpfile)
      local result = import_mod.resolve_lua_imports(content, "/tmp")
      assert.matches('@my_person = ', result)
      assert.matches('"name":"lex"', result)
      assert.matches('"age":23', result)

      os.remove(tmpfile)
    end)

    it("{{tmp_var}} in body expands via @var = alias.key", function()
      local tmpfile = os.tmpname() .. ".lua"
      local f = io.open(tmpfile, "w")
      f:write("return { person = { name = 'lex', age = 23 } }")
      f:close()

      local content = ("import %s as m\n@my_data = m.person\n\n### Test\nPOST /test\n\n{{my_data}}"):format(tmpfile)
      local result = import_mod.resolve_lua_imports(content, "/tmp")
      -- @my_data should be resolved to JSON value
      assert.matches('@my_data = ', result)
      -- {{my_data}} stays as-is (Rust parser handles substitution)
      assert.matches('{{my_data}}', result)

      os.remove(tmpfile)
    end)

    it("preserves content when no Lua imports", function()
      local content = [[
### Test
POST /test

{"key": "value"}
]]
      local result = import_mod.resolve_lua_imports(content, "/tmp")
      assert.are_equal(content, result)
    end)

    it("strips import lines from content", function()
      local tmpfile = os.tmpname() .. ".lua"
      local f = io.open(tmpfile, "w")
      f:write("return { val = 42 }")
      f:close()

      local content = ("import %s as m\n\n### Test\nPOST /test\n"):format(tmpfile)
      local result = import_mod.resolve_lua_imports(content, "/tmp")
      -- Import line becomes blank line (preserves line count)
      local lines = vim.split(result, "\n", { plain = true })
      assert.are_equal("", vim.trim(lines[1]))
      assert.are_equal("### Test", lines[3])

      os.remove(tmpfile)
    end)
  end)
end)

describe("execute_import_via_curl", function()
  local orig_execute
  local orig_describe

  before_each(function()
    package.loaded["poste-http.http.import"] = nil
    package.loaded["poste-http.http.curl_exec"] = nil
    package.loaded["poste-http.http.describe"] = nil
    state.pending_request = nil
    orig_execute = nil
    orig_describe = nil
  end)

  after_each(function()
    state.pending_request = nil
    if orig_execute then
      package.loaded["poste-http.http.curl_exec"] = nil
    end
    if orig_describe then
      package.loaded["poste-http.http.describe"] = nil
    end
    package.loaded["poste-http.http.import"] = nil
  end)

  it("sets state.pending_request with Authorization header before curl execution", function()
    -- Mock describe to return a valid block, avoiding tree-sitter dependency
    local mock_describe = {
      describe_content = function()
        return {
          {
            name = "GetUser",
            line = 1,
            end_line = 3,
            method = "GET",
            path = "/api/users/42",
            headers = { { "Authorization", "Bearer token123" } },
            body = "",
            request_line = "GET /api/users/42",
          },
        }, nil
      end,
      block_at_line = function(blocks, line)
        return blocks[1]
      end,
      to_req_block = function(meta)
        return {
          request_line = meta.request_line or "",
          headers = meta.headers or {},
          name = meta.name or "",
          method = meta.method or "",
          path = meta.path or "",
          body = meta.body or "",
        }
      end,
      headers_str = function(meta)
        local parts = {}
        for _, h in ipairs(meta.headers or {}) do
          table.insert(parts, h[1] .. ": " .. (h[2] or ""))
        end
        return table.concat(parts, "\n")
      end,
    }
    package.loaded["poste-http.http.describe"] = mock_describe

    -- Mock curl_exec.execute to avoid real curl execution
    local curl_exec = require("poste-http.http.curl_exec")
    orig_execute = curl_exec.execute
    curl_exec.execute = function(opts, callback)
      callback({ status = 200, body = "ok", headers = {}, metadata = {} })
    end

    local import_mod = require("poste-http.http.import")
    local content = [[
### GetUser
GET /api/users/42
Authorization: Bearer token123
]]
    import_mod._test.execute_import_via_curl(content, "/tmp/test.http", 1, "default", function(response) end)

    assert.is_not_nil(state.pending_request)
    assert.is_not_nil(state.pending_request.headers_str)
    assert.matches("Authorization: Bearer token123", state.pending_request.headers_str)
  end)
end)

describe("resolve_request_reference", function()
  local req_file
  local buf

  before_each(function()
    package.loaded["poste-http.http.import"] = nil
    req_file = os.tmpname() .. ".http"
    local f = io.open(req_file, "w")
    f:write("### login\nPOST /login\n\n### get_profile\nGET /profile\n")
    f:close()
    buf = vim.api.nvim_create_buf(true, true)
  end)

  after_each(function()
    os.remove(req_file)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    package.loaded["poste-http.http.import"] = nil
  end)

  local function set_buffer_content(lines)
    vim.api.nvim_buf_set_name(buf, os.tmpname() .. ".http")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  it("resolves an aliased reference from the buffer's imports", function()
    set_buffer_content({ "import " .. req_file .. " as alias" })
    local import_mod = require("poste-http.http.import")
    local r = import_mod.resolve_request_reference("#alias.login", buf)
    assert.are_equal("execute", r.action)
    assert.are_equal(req_file, r.path)
    assert.are_equal("login", r.request_name)
  end)

  it("resolves a bare reference", function()
    set_buffer_content({ "import " .. req_file })
    local import_mod = require("poste-http.http.import")
    local r = import_mod.resolve_request_reference("#get_profile", buf)
    assert.are_equal(req_file, r.path)
    assert.are_equal("get_profile", r.request_name)
  end)

  it("returns nil and an error for an unknown reference", function()
    set_buffer_content({ "import " .. req_file .. " as alias" })
    local import_mod = require("poste-http.http.import")
    local r, err = import_mod.resolve_request_reference("#nope", buf)
    assert.is_nil(r)
    assert.matches("not found", err)
  end)
end)

describe("execute_request_reference", function()
  local import_mod
  local orig_resolve
  local orig_execute

  before_each(function()
    package.loaded["poste-http.http.import"] = nil
    import_mod = require("poste-http.http.import")
    orig_resolve = import_mod.resolve_request_reference
    orig_execute = import_mod.execute_run_directive
  end)

  after_each(function()
    import_mod.resolve_request_reference = orig_resolve
    import_mod.execute_run_directive = orig_execute
    package.loaded["poste-http.http.import"] = nil
  end)

  it("stringifies Lua arg values into run variable overrides", function()
    import_mod.resolve_request_reference = function()
      return { action = "execute", path = "/tmp/a.http", line = 1, request_name = "login", vars = {} }
    end
    local captured
    import_mod.execute_run_directive = function(opts, callback)
      captured = opts
      callback(true, { status = 200, body = "{}" })
    end

    local ok, response, name = false
    import_mod.execute_request_reference("#alias.login", { token = 42, flag = true, obj = { a = 1 } }, nil, function(a, b, c)
      ok, response, name = a, b, c
    end)

    assert.is_true(ok)
    assert.are_equal(200, response.status)
    assert.are_equal("login", name)
    assert.are_equal("42", captured.vars.token)
    assert.are_equal("true", captured.vars.flag)
    assert.are_equal(vim.json.encode({ a = 1 }), captured.vars.obj)
  end)

  it("reports an unresolvable reference without executing", function()
    import_mod.resolve_request_reference = function()
      return nil, "Request 'nope' not found in imports"
    end
    local executed = false
    import_mod.execute_run_directive = function()
      executed = true
    end

    local ok, response, name, err
    import_mod.execute_request_reference("#nope", {}, nil, function(a, b, c, d)
      ok, response, name, err = a, b, c, d
    end)

    assert.is_false(ok)
    assert.is_nil(response)
    assert.is_nil(name)
    assert.matches("not found", err)
    assert.is_false(executed)
  end)
end)
