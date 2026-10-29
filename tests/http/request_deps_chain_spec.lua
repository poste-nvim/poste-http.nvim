--- Regression specs for the dependency-chain state used by the real run
--- pipeline (`_resolve_content_dependencies_impl`, the entry resolve.lua
--- dispatches to).
---
--- Bug 1 (chain leak): `_chain_dep_set`/`_chain_dep_order` were only reset by
--- the two other entry points, so a second request kept the first request's
--- deps in `M._dep_chain` — stale responses re-entered the multi-response
--- view and were written to history a second time.
---
--- Bug 2 (multi-line replacement): `substitute_and_finish` mapped the
--- resolved block back onto the ORIGINAL block height 1:1, so a replacement
--- value containing a newline silently dropped every line after it in the
--- block (e.g. an `X-Keep` header following a multi-line body ref).
local request_deps = require("poste-http.http.request_deps")
local curl_exec = require("poste-http.http.curl_exec")

local function resolve_impl(content, block_line)
  local result
  request_deps._resolve_content_dependencies_impl(0, "/tmp/test.http", "dev", content, block_line, function(resolved)
    result = resolved
  end)
  vim.wait(200, function() return result ~= nil end)
  return result
end

--- Minimal wire-shaped response the curl stub can hand back. The chain
--- rebuild only reads `request_response_cache[name]`, so no metadata needed.
local function fake_response(body)
  return { status = 200, body = body or "{}", headers = {}, ok = true }
end

describe("request_deps chain state across runs (real pipeline entry)", function()
  local orig_execute

  before_each(function()
    orig_execute = curl_exec.execute
  end)

  after_each(function()
    curl_exec.execute = orig_execute
    request_deps.cache_response("dep_one", nil)
    request_deps.cache_response("dep_two", nil)
    request_deps._dep_chain = nil
  end)

  it("does not leak the previous run's dependencies into _dep_chain", function()
    -- Every dep "executes" through the stub; the fake curl records which
    -- names were requested so the assertion is meaningful.
    local executed = {}
    curl_exec.execute = function(req, cb)
      executed[#executed + 1] = req.url
      cb(fake_response('{"ok":true}'))
    end

    local first = resolve_impl(table.concat({
      "### dep_one",
      "GET http://dep.one/x",
      "",
      "### target_a",
      "GET http://a.example/x",
      "X-From: {{dep_one.response.body.ok}}",
    }, "\n"), 4)
    assert.truthy(first, "first run should complete")
    assert.truthy(first:match("true"), "first run should substitute its dep")
    local chain_one = request_deps._dep_chain
    assert.equals(1, #chain_one)
    assert.equals("dep_one", chain_one[1].name)

    -- Second run: a different target depending on a DIFFERENT dep only.
    -- The stale dep_one (still in the response cache, deliberately) must not
    -- reappear in the chain.
    local second = resolve_impl(table.concat({
      "### dep_two",
      "GET http://dep.two/y",
      "",
      "### target_b",
      "GET http://b.example/y",
      "X-From: {{dep_two.response.body.ok}}",
    }, "\n"), 4)
    assert.truthy(second, "second run should complete")
    assert.truthy(second:match("true"), "second run should substitute its dep")

    local chain_two = request_deps._dep_chain
    assert.equals(1, #chain_two, "chain must contain only this run's dep, got "
      .. vim.inspect(chain_two))
    assert.equals("dep_two", chain_two[1].name)
  end)

  it("does not cache a network-failed dependency response", function()
    -- parse_error's canonical shape for a network-level failure: protocol
    -- "error", status 0, ok false — and NO .error field (that one is only
    -- for curl_exec's own failures). Caching this shape used to poison the
    -- session: every later run hit the cache short-circuit and could never
    -- recover until the dependency was re-run by hand.
    local wire_error = {
      protocol = "error", status = 0, status_text = "Failed (exit 28)",
      url = "", content_type = "text/plain", headers = {}, body = "",
      cookies = {}, ok = false,
      metadata = { method = "GET", exit_code = "28", verbose = "timeout" },
    }
    local executed = 0
    curl_exec.execute = function(req, cb)
      executed = executed + 1
      cb(vim.deepcopy(wire_error))
    end

    local content = table.concat({
      "### dep_fail",
      "GET http://dep.fail/x",
      "",
      "### target",
      "GET http://t.example/x",
      "X-From: {{dep_fail.response.body.ok}}",
    }, "\n")

    local first = resolve_impl(content, 4)
    -- impl semantics: a failed dep is skipped, the block completes with the
    -- reference left unresolved (run.lua's pre-request gate reports it).
    -- The assertion that matters: the FAILED response must not be usable
    -- as a substitution value.
    assert.truthy(first, "resolution should still complete after a dep failure")
    assert.truthy(first:match("X%-From: {{dep_fail%.response%.body%.ok}}"),
      "the failed dep must not substitute any value")
    assert.equals(1, executed, "the dependency should have gone to curl once")
    assert.is_false(request_deps.is_response_cached("dep_fail"),
      "a failed response must not enter the response cache")

    -- Second run: the failed dep must be re-executed, not served from cache.
    resolve_impl(content, 4)
    assert.equals(2, executed, "the second run must re-execute the failed dep")
  end)

  it("does not cache a dependency whose curl_exec reported its own error", function()
    curl_exec.execute = function(req, cb)
      cb({ error = "No URL provided" })
    end

    local first = resolve_impl(table.concat({
      "### dep_err",
      "GET http://dep.err/x",
      "",
      "### target",
      "GET http://t.example/x",
      "X-From: {{dep_err.response.body.ok}}",
    }, "\n"), 4)
    assert.truthy(first)
    assert.is_false(request_deps.is_response_cached("dep_err"))
  end)
end)

describe("request_deps multi-line replacement values", function()
  after_each(function()
    request_deps.cache_response("dep_ml", nil)
    request_deps._dep_chain = nil
  end)

  it("keeps block lines after a replacement value that contains a newline", function()
    -- The dep response body field itself spans two lines: value_to_http_string
    -- injects strings as-is, so the resolved block grows one physical line.
    request_deps.cache_response("dep_ml", fake_response("line1\nline2"))

    local result = resolve_impl(table.concat({
      "### target",
      "GET http://t.example/x",
      "X-Note: {{dep_ml.response.body}}",
      "X-Keep: yes",
    }, "\n"), 1)

    assert.truthy(result, "resolution should complete")
    assert.truthy(result:match("line1\nline2"), "multi-line value should be inlined")
    assert.truthy(result:match("X%-Keep: yes"),
      "the header after the multi-line substitution must survive, got:\n" .. tostring(result))
    assert.truthy(result:match("GET http://t%.example/x"),
      "the request line must survive")
  end)

  it("keeps trailing lines when the block is at the end of the file", function()
    request_deps.cache_response("dep_ml", fake_response("a\nb\nc"))

    local result = resolve_impl(table.concat({
      "### target",
      "POST http://t.example/x",
      "Content-Type: application/json",
      "",
      "{",
      '  "text": "{{dep_ml.response.body}}"',
      "}",
    }, "\n"), 1)

    assert.truthy(result:match('%"text%": "a\nb\nc"'), "inlined value should span lines")
    assert.truthy(result:match("^}$") or result:match("\n}$"),
      "the closing brace must survive, got:\n" .. tostring(result))
  end)
end)
