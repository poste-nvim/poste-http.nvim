--- End-to-end tests for the OpenAPI 3.x and Swagger 2.0 spec importers.
--- The generated .http file is meant to be committed and reviewed, so the
--- block order must be a pure function of the spec (sorted path order) —
--- pairs() hash order changed between runs and between nvim sessions.
local openapi = require("poste-http.http.import_openapi")
local swagger = require("poste-http.http.import_swagger")

local function write_json(path, tbl)
  local fd = io.open(path, "w")
  fd:write(vim.json.encode(tbl))
  fd:close()
end

local function read_file(path)
  local fd = io.open(path, "r")
  local content = fd and fd:read("*a") or nil
  if fd then fd:close() end
  return content
end

describe("OpenAPI import ordering", function()
  it("emits blocks in sorted path order and is deterministic across runs", function()
    -- 30 paths: pairs() hash order is certainly not sorted order here.
    local paths = {}
    for i = 1, 30 do
      paths[string.format("/p%02d", i)] = {
        get = { summary = "Get p" .. i, responses = { ["200"] = { description = "ok" } } },
      }
    end
    paths["/users"] = {
      get = { summary = "List users", responses = { ["200"] = { description = "ok" } } },
    }
    local spec_path = os.tmpname() .. ".json"
    write_json(spec_path, {
      openapi = "3.0.0",
      info = { title = "Ordering Test" },
      servers = { { url = "http://localhost:8080" } },
      paths = paths,
    })
    local out_dir = os.tmpname() .. "-out"
    os.remove(out_dir)

    local result = openapi.import_spec(spec_path, out_dir)
    assert.is_truthy(result, "import must succeed")

    local content = read_file(out_dir .. "/" .. result.filename)
    assert.is_truthy(content)

    -- Collect the request-line order and compare against the sorted paths.
    local order = {}
    for line in content:gmatch("[^\n]+") do
      if line:match("^GET ") then table.insert(order, line) end
    end
    assert.are_equal(31, #order)
    local sorted = {}
    for i = 1, 30 do table.insert(sorted, "GET {{base_url}}/p" .. string.format("%02d", i)) end
    table.insert(sorted, "GET {{base_url}}/users")
    for i, expected in ipairs(sorted) do
      assert.are_equal(expected, order[i], "block " .. i .. " must follow sorted path order")
    end

    -- Re-import into a second dir: byte-identical output.
    local out_dir2 = os.tmpname() .. "-out2"
    os.remove(out_dir2)
    local result2 = openapi.import_spec(spec_path, out_dir2)
    assert.are_equal(content, read_file(out_dir2 .. "/" .. result2.filename))

    os.remove(spec_path)
    os.remove(out_dir .. "/" .. result.filename)
    os.remove(out_dir .. "/env.json")
    os.remove(out_dir2 .. "/" .. result2.filename)
    os.remove(out_dir2 .. "/env.json")
  end)

  it("skips malformed (non-table) path items instead of erroring", function()
    local spec_path = os.tmpname() .. ".json"
    write_json(spec_path, {
      openapi = "3.0.0",
      info = { title = "Malformed" },
      paths = {
        ["/ok"] = { get = { summary = "Fine", responses = {} } },
        ["/bad-num"] = 42,
        ["/bad-null"] = vim.NIL,
      },
    })
    local out_dir = os.tmpname() .. "-out"
    os.remove(out_dir)

    local result, err = openapi.import_spec(spec_path, out_dir)
    assert.is_truthy(result, "malformed path items must be skipped, not fatal: " .. tostring(err))
    assert.are_equal(1, result.block_count)

    os.remove(spec_path)
    os.remove(out_dir .. "/" .. result.filename)
    os.remove(out_dir .. "/env.json")
  end)

  it("swagger: survives scalar/null security, parameters, and defs sections", function()
    -- JSON null decodes to vim.NIL (which `or {}` does NOT catch) and
    -- hand-edited files carry scalar lists: security/parameters used to
    -- raise ipairs-on-a-string or pairs-on-userdata mid-import.
    local spec_path = os.tmpname() .. ".json"
    write_json(spec_path, {
      swagger = "2.0",
      info = { title = "Drifted" },
      securityDefinitions = "not-a-table",
      paths = {
        ["/a"] = {
          get = {
            summary = "G",
            security = "not-a-table",
            parameters = "not-a-table",
            responses = {},
          },
          post = {
            summary = "P",
            security = { "not-a-table", { drift = {} } },
            parameters = { "scalar", { name = "q", ["in"] = "query", type = "string" } },
            responses = {},
          },
        },
      },
    })
    local out_dir = os.tmpname() .. "-out"
    os.remove(out_dir)

    local result, err = swagger.import_spec(spec_path, out_dir)
    assert.is_truthy(result, "drifted sections must degrade, not crash: " .. tostring(err))
    assert.are_equal(2, result.block_count)

    os.remove(spec_path)
    os.remove(out_dir .. "/" .. result.filename)
    os.remove(out_dir .. "/env.json")
  end)

  it("read_spec strips vim.NIL: JSON null anywhere imports as plain nil", function()
    -- The boundary contract every importer relies on: {"info":null} reads
    -- back as info == nil (not userdata), so `spec.info == nil` guards hold.
    local parser = require("poste-http.http.import_parser")
    local spec_path = os.tmpname() .. ".json"
    local fd = io.open(spec_path, "w")
    fd:write('{"info":null,"item":null,"paths":{"a":null}}')
    fd:close()
    local spec, err = parser.read_spec(spec_path)
    assert.is_truthy(spec, err)
    assert.is_nil(spec.info)
    assert.is_nil(spec.item)
    assert.is_nil(spec.paths.a)
    os.remove(spec_path)
  end)
end)

describe("Swagger import ordering", function()
  it("emits blocks in sorted path order and is deterministic across runs", function()
    local paths = {}
    for i = 1, 30 do
      paths[string.format("/p%02d", i)] = {
        get = { summary = "Get p" .. i, responses = { ["200"] = { description = "ok" } } },
      }
    end
    paths["/users"] = {
      get = { summary = "List users", responses = { ["200"] = { description = "ok" } } },
    }
    local spec_path = os.tmpname() .. ".json"
    write_json(spec_path, {
      swagger = "2.0",
      info = { title = "Ordering Test" },
      host = "localhost",
      basePath = "/api",
      paths = paths,
    })
    local out_dir = os.tmpname() .. "-out"
    os.remove(out_dir)

    local result = swagger.import_spec(spec_path, out_dir)
    assert.is_truthy(result, "import must succeed")

    local content = read_file(out_dir .. "/" .. result.filename)
    local order = {}
    for line in content:gmatch("[^\n]+") do
      if line:match("^GET ") then table.insert(order, line) end
    end
    assert.are_equal(31, #order)
    assert.matches("^GET {{base_url}}/api/p01$", order[1])
    assert.matches("^GET {{base_url}}/api/users$", order[31])

    local out_dir2 = os.tmpname() .. "-out2"
    os.remove(out_dir2)
    local result2 = swagger.import_spec(spec_path, out_dir2)
    assert.are_equal(content, read_file(out_dir2 .. "/" .. result2.filename))

    os.remove(spec_path)
    os.remove(out_dir .. "/" .. result.filename)
    os.remove(out_dir .. "/env.json")
    os.remove(out_dir2 .. "/" .. result2.filename)
    os.remove(out_dir2 .. "/env.json")
  end)

  it("skips malformed (non-table) path items instead of erroring", function()
    local spec_path = os.tmpname() .. ".json"
    write_json(spec_path, {
      swagger = "2.0",
      info = { title = "Malformed" },
      paths = {
        ["/ok"] = { get = { summary = "Fine", responses = {} } },
        ["/bad-num"] = 42,
      },
    })
    local out_dir = os.tmpname() .. "-out"
    os.remove(out_dir)

    local result, err = swagger.import_spec(spec_path, out_dir)
    assert.is_truthy(result, "malformed path items must be skipped, not fatal: " .. tostring(err))
    assert.are_equal(1, result.block_count)

    os.remove(spec_path)
    os.remove(out_dir .. "/" .. result.filename)
    os.remove(out_dir .. "/env.json")
  end)

  it("swagger: survives scalar/null security, parameters, and defs sections", function()
    -- JSON null decodes to vim.NIL (which `or {}` does NOT catch) and
    -- hand-edited files carry scalar lists: security/parameters used to
    -- raise ipairs-on-a-string or pairs-on-userdata mid-import.
    local spec_path = os.tmpname() .. ".json"
    write_json(spec_path, {
      swagger = "2.0",
      info = { title = "Drifted" },
      securityDefinitions = "not-a-table",
      paths = {
        ["/a"] = {
          get = {
            summary = "G",
            security = "not-a-table",
            parameters = "not-a-table",
            responses = {},
          },
          post = {
            summary = "P",
            security = { "not-a-table", { drift = {} } },
            parameters = { "scalar", { name = "q", ["in"] = "query", type = "string" } },
            responses = {},
          },
        },
      },
    })
    local out_dir = os.tmpname() .. "-out"
    os.remove(out_dir)

    local result, err = swagger.import_spec(spec_path, out_dir)
    assert.is_truthy(result, "drifted sections must degrade, not crash: " .. tostring(err))
    assert.are_equal(2, result.block_count)

    os.remove(spec_path)
    os.remove(out_dir .. "/" .. result.filename)
    os.remove(out_dir .. "/env.json")
  end)

  it("read_spec strips vim.NIL: JSON null anywhere imports as plain nil", function()
    -- The boundary contract every importer relies on: {"info":null} reads
    -- back as info == nil (not userdata), so `spec.info == nil` guards hold.
    local parser = require("poste-http.http.import_parser")
    local spec_path = os.tmpname() .. ".json"
    local fd = io.open(spec_path, "w")
    fd:write('{"info":null,"item":null,"paths":{"a":null}}')
    fd:close()
    local spec, err = parser.read_spec(spec_path)
    assert.is_truthy(spec, err)
    assert.is_nil(spec.info)
    assert.is_nil(spec.item)
    assert.is_nil(spec.paths.a)
    os.remove(spec_path)
  end)
end)

describe("hostile spec shapes (2026-10-28 round)", function()
  local function cleanup(path, out_dir)
    pcall(os.remove, path)
    pcall(vim.fn.delete, out_dir, "rf")
  end

  it("a scalar paths map imports as an empty file, not a crash", function()
    -- Both importers used to feed the scalar straight into pairs()
    -- ("bad argument #1 to 'pairs'") when a hand-edited spec carried
    -- "paths": "junk".
    local cases = {
      { label = "OpenAPI", mod = openapi, base = { openapi = "3.0.0" } },
      { label = "Swagger", mod = swagger, base = { swagger = "2.0" } },
    }
    for _, case in ipairs(cases) do
      local spec_path = os.tmpname() .. ".json"
      local out_dir = os.tmpname() .. "-out"
      os.remove(out_dir)
      local base = case.base
      base.info = { title = "Scalar Paths" }
      base.paths = "junk"
      write_json(spec_path, base)
      local result, err = case.mod.import_spec(spec_path, out_dir)
      assert.is_truthy(result, case.label .. " import must survive, got: " .. tostring(err))
      cleanup(spec_path, out_dir)
    end
  end)

  it("read_spec rejects a directory with an error instead of crashing", function()
    -- io.open succeeds on a directory; only the read fails. The OpenAPI
    -- finder runs in "both" mode, so confirming a directory landed here.
    local dir = os.tmpname()
    os.remove(dir)
    vim.fn.mkdir(dir, "p")
    local spec, err = require("poste-http.http.import_parser").read_spec(dir)
    assert.is_nil(spec)
    assert.truthy(err:match("Cannot read file"))
    vim.fn.delete(dir, "rf")
  end)

  it("extract_auth_header survives scalar security shapes", function()
    local parser = require("poste-http.http.import_parser")
    assert.is_nil(parser.extract_auth_header({ security = "junk" }))
    assert.is_nil(parser.extract_auth_header({ security = { 42 } }))
    assert.is_nil(parser.extract_auth_header({ security = { { bearer_auth = {} } },
      components = { securitySchemes = 42 } }))
    -- Well-formed input still resolves.
    local auth = parser.extract_auth_header({
      security = { { bearer_auth = {} } },
      components = { securitySchemes = { bearer_auth = { type = "http", scheme = "bearer" } } },
    })
    assert.equals("Authorization", auth.key)
  end)

  it("OpenAPI resolves a requestBody $ref instead of dropping the body", function()
    local spec_path = os.tmpname() .. ".json"
    local out_dir = os.tmpname() .. "-out"
    os.remove(out_dir)
    write_json(spec_path, {
      openapi = "3.0.0",
      info = { title = "Ref Body" },
      servers = { { url = "http://localhost:8080" } },
      paths = {
        ["/pets"] = {
          post = {
            summary = "Create pet",
            requestBody = { ["$ref"] = "#/components/requestBodies/Pet" },
            responses = { ["200"] = { description = "ok" } },
          },
        },
      },
      components = {
        requestBodies = {
          Pet = {
            content = {
              ["application/json"] = {
                schema = { type = "object", properties = { name = { type = "string" } } },
              },
            },
          },
        },
      },
    })
    local result, err = openapi.import_spec(spec_path, out_dir)
    assert.is_truthy(result, err)
    local content = read_file(out_dir .. "/" .. result.filename)
    -- The generated .http block carries the dereferenced JSON body plus its
    -- Content-Type (not a curl command — this is the file importer).
    assert.truthy(content:match('Content%-Type: application/json'), "body content-type must be present")
    assert.truthy(content:match('%{"name":"string"%}'), "the referenced schema's example must become the body")
    cleanup(spec_path, out_dir)
  end)

  it("OpenAPI survives scalar servers and keeps the default base_url", function()
    local spec_path = os.tmpname() .. ".json"
    local out_dir = os.tmpname() .. "-out"
    os.remove(out_dir)
    write_json(spec_path, {
      openapi = "3.0.0",
      info = { title = "Scalar Servers" },
      servers = "junk",
      paths = { ["/ping"] = { get = { summary = "Ping", responses = { ["200"] = { description = "ok" } } } } },
    })
    local result, err = openapi.import_spec(spec_path, out_dir)
    assert.is_truthy(result, err)
    local content = read_file(out_dir .. "/" .. result.filename)
    assert.truthy(content:match("http://localhost"), "default server URL must be used")
    cleanup(spec_path, out_dir)
  end)

  it("Swagger skips nameless parameters instead of crashing", function()
    local spec_path = os.tmpname() .. ".json"
    local out_dir = os.tmpname() .. "-out"
    os.remove(out_dir)
    write_json(spec_path, {
      swagger = "2.0",
      info = { title = "Nameless" },
      host = "api.example.com",
      paths = {
        ["/x"] = {
          get = {
            summary = "X",
            parameters = { { ["in"] = "header" }, { name = "q", ["in"] = "query", type = "string" } },
            responses = { ["200"] = { description = "ok" } },
          },
        },
      },
    })
    local result, err = swagger.import_spec(spec_path, out_dir)
    assert.is_truthy(result, err)
    local content = read_file(out_dir .. "/" .. result.filename)
    assert.truthy(content:match("q=string"), "the named query param must survive")
    cleanup(spec_path, out_dir)
  end)

  it("Swagger survives a scalar schemes value", function()
    local spec_path = os.tmpname() .. ".json"
    local out_dir = os.tmpname() .. "-out"
    os.remove(out_dir)
    write_json(spec_path, {
      swagger = "2.0",
      info = { title = "Scalar Schemes" },
      host = "api.example.com",
      schemes = "https",
      paths = { ["/y"] = { get = { summary = "Y", responses = { ["200"] = { description = "ok" } } } } },
    })
    local result, err = swagger.import_spec(spec_path, out_dir)
    assert.is_truthy(result, err)
    cleanup(spec_path, out_dir)
  end)

  it("propagates write_output failure instead of reporting success", function()
    -- An unwritable output path must reach the caller as (nil, err); the old
    -- silent-write path notified "N blocks → path" with nothing on disk.
    local spec_path = os.tmpname() .. ".json"
    write_json(spec_path, {
      openapi = "3.0.0",
      info = { title = "Bad Out" },
      paths = { ["/z"] = { get = { summary = "Z", responses = { ["200"] = { description = "ok" } } } } },
    })
    -- A FILE where the output directory should be: mkdir "p" fails.
    local blocker = os.tmpname()
    local f = io.open(blocker, "w")
    f:write("not a dir")
    f:close()
    local result, err = openapi.import_spec(spec_path, blocker)
    assert.is_nil(result)
    assert.truthy(err, "an error must come back")
    cleanup(spec_path, blocker)
  end)
end)
