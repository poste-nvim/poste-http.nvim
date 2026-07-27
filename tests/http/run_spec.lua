local state = require("poste_http.state")

describe("run._test.make_script_response", function()
  local run

  before_each(function()
    package.loaded["poste_http.http.run"] = nil
    run = require("poste_http.http.run")
  end)

  after_each(function()
    package.loaded["poste_http.http.run"] = nil
  end)

  it("returns a table with protocol = 'script'", function()
    local resp = run._test.make_script_response("SCRIPT", nil)
    assert.equal("script", resp.protocol)
  end)

  it("includes status 200 and status_text 'Script executed'", function()
    local resp = run._test.make_script_response("SCRIPT", nil)
    assert.equal(200, resp.status)
    assert.equal("Script executed", resp.status_text)
  end)

  it("stores trimmed req_text in url and metadata.request_line", function()
    local resp = run._test.make_script_response("  SCRIPT  ", nil)
    assert.equal("SCRIPT", resp.url)
    assert.equal("SCRIPT", resp.metadata.request_line)
  end)

  it("includes req_block.headers when req_block is provided", function()
    local req_block = { headers = { { "X-Custom", "val" } } }
    local resp = run._test.make_script_response("SCRIPT", req_block)
    assert.equal("X-Custom", resp.headers[1][1])
    assert.equal("val", resp.headers[1][2])
  end)

  it("defaults to empty headers when req_block is nil", function()
    local resp = run._test.make_script_response("SCRIPT", nil)
    assert.same({}, resp.headers)
  end)

  it("has a fixed body string", function()
    local resp = run._test.make_script_response("SCRIPT", nil)
    assert.equal("Script executed. See Assertions or Script Logs tab for details.", resp.body)
  end)

  it("sets metadata.method to 'SCRIPT' and exit_code to '0'", function()
    local resp = run._test.make_script_response("SCRIPT", nil)
    assert.equal("SCRIPT", resp.metadata.method)
    assert.equal("0", resp.metadata.exit_code)
  end)
end)

describe("run._test.make_error_response", function()
  local run

  before_each(function()
    package.loaded["poste_http.http.run"] = nil
    run = require("poste_http.http.run")
  end)

  after_each(function()
    package.loaded["poste_http.http.run"] = nil
  end)

  it("returns a table with protocol = 'error'", function()
    local resp = run._test.make_error_response("GET /fail", nil, "timeout", "Connection refused", 1)
    assert.equal("error", resp.protocol)
  end)

  it("includes body_text in the body field", function()
    local resp = run._test.make_error_response("GET /fail", nil, "timeout", "Connection refused", 1)
    assert.equal("timeout", resp.body)
  end)

  it("includes exit_code as string in metadata.exit_code", function()
    local resp = run._test.make_error_response("GET /fail", nil, "timeout", "Connection refused", 1)
    assert.equal("1", resp.metadata.exit_code)
  end)

  it("handles nil exit_code by using '?'", function()
    local resp = run._test.make_error_response("GET /fail", nil, "err", "msg", nil)
    assert.equal("?", resp.metadata.exit_code)
  end)

  it("includes err_msg as status_text", function()
    local resp = run._test.make_error_response("GET /fail", nil, "body content", "Not Found", 404)
    assert.equal("Not Found", resp.status_text)
  end)

  it("includes req_block.headers when req_block is provided", function()
    local req_block = { headers = { { "Content-Type", "text/plain" } } }
    local resp = run._test.make_error_response("GET /fail", req_block, "err", "msg", 1)
    assert.equal("Content-Type", resp.headers[1][1])
  end)
end)

describe("run._test.choose_view_tab", function()
  local run

  before_each(function()
    package.loaded["poste_http.http.run"] = nil
    run = require("poste_http.http.run")
    state.config.default_view = nil
  end)

  after_each(function()
    package.loaded["poste_http.http.run"] = nil
  end)

  it("returns 'assertions' when assertion_results has failures", function()
    local parsed = { status = 200 }
    local results = { total = 3, passed = 1, failed = 2 }
    assert.equal("assertions", run._test.choose_view_tab(parsed, results))
  end)

  it("returns 'verbose' when status >= 400 and no assertion failures", function()
    local parsed = { status = 404 }
    assert.equal("verbose", run._test.choose_view_tab(parsed, nil))
  end)

  it("returns 'verbose' when status >= 400 even with all-passing assertions", function()
    local parsed = { status = 500 }
    local results = { total = 2, passed = 2, failed = 0 }
    assert.equal("verbose", run._test.choose_view_tab(parsed, results))
  end)

  it("returns 'body' by default when no assertions and status < 400", function()
    local parsed = { status = 200 }
    assert.equal("body", run._test.choose_view_tab(parsed, nil))
  end)

  it("returns default_view from config when set (overrides 'body')", function()
    state.config.default_view = "headers"
    local parsed = { status = 200 }
    assert.equal("headers", run._test.choose_view_tab(parsed, nil))
  end)
end)

describe("run._test.inject_global_vars", function()
  local run

  before_each(function()
    package.loaded["poste_http.http.run"] = nil
    run = require("poste_http.http.run")
  end)

  after_each(function()
    package.loaded["poste_http.http.run"] = nil
  end)

  it("injects @var = value lines after block_start", function()
    local content = "GET /test\nHost: example.com"
    local vars = { host = "example.com", token = "abc123" }
    local result, count = run._test.inject_global_vars(content, 1, vars)
    assert.equal(2, count)
    local lines = vim.split(result, "\n", { plain = true })
    assert.equal(4, #lines)
    assert.equal("GET /test", lines[1])
    assert.matches("@host = example.com", result)
    assert.matches("@token = abc123", result)
    assert.equal("Host: example.com", lines[4])
  end)

  it("returns content unchanged and count 0 when global_vars is empty", function()
    local content = "GET /test\nHost: example.com"
    local result, count = run._test.inject_global_vars(content, 1, {})
    assert.equal(0, count)
    assert.equal("GET /test\nHost: example.com", result)
  end)

  it("returns content unchanged and count 0 when global_vars is nil", function()
    local content = "GET /test\nHost: example.com"
    local result, count = run._test.inject_global_vars(content, 1, nil)
    assert.equal(0, count)
    assert.equal("GET /test\nHost: example.com", result)
  end)

  it("returns content unchanged and count 0 when block_start is nil", function()
    local content = "GET /test\nHost: example.com"
    local result, count = run._test.inject_global_vars(content, nil, { key = "val" })
    assert.equal(0, count)
    assert.equal("GET /test\nHost: example.com", result)
  end)

  it("returns content unchanged and count 0 when block_start is nil and global_vars is empty", function()
    local content = "GET /test"
    local result, count = run._test.inject_global_vars(content, nil, {})
    assert.equal(0, count)
    assert.equal("GET /test", result)
  end)

  it("injects after a later block_start line, not just line 1", function()
    local content = "GET /a\nHost: a\n\n###\n\nGET /b\nHost: b"
    local vars = { env = "staging" }
    local result, count = run._test.inject_global_vars(content, 5, vars)
    assert.equal(1, count)
    local lines = vim.split(result, "\n", { plain = true })
    -- block_start=5 is the empty line before "GET /b"
    -- injection adds @env = staging after line 5, shifting subsequent lines
    assert.equal("", lines[5])
    assert.matches("@env = staging", lines[6])
    assert.equal("GET /b", lines[7])
  end)

  it("handles single-line content correctly", function()
    local content = "GET /ping"
    local vars = { debug = "true" }
    local result, count = run._test.inject_global_vars(content, 1, vars)
    assert.equal(1, count)
    local lines = vim.split(result, "\n", { plain = true })
    assert.equal(2, #lines)
    assert.equal("GET /ping", lines[1])
    assert.matches("@debug = true", lines[2])
  end)
end)