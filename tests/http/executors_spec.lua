-- Tests for the protocol executor dispatch (docs/dev/multi-protocol-design.md).
--
-- Executors own the subprocess for one protocol and share the canonical
-- response contract: M.run(req, callback) with
-- req = { method, url, headers, body, buf_dir, timeout, name }.

local executors = require("poste-http.http.executors")

describe("executors.get", function()
  it("returns the HTTP executor for plain HTTP verbs", function()
    local http = require("poste-http.http.executors.http")
    assert.equals(http, executors.get("GET"))
    assert.equals(http, executors.get("POST"))
  end)

  it("falls back to the HTTP executor for unknown methods", function()
    local http = require("poste-http.http.executors.http")
    assert.equals(http, executors.get("TELEPORT"))
    assert.equals(http, executors.get(""))
    assert.equals(http, executors.get(nil))
  end)

  it("is case-insensitive", function()
    local http = require("poste-http.http.executors.http")
    assert.equals(http, executors.get("get"))
  end)
end)

describe("executors.run", function()
  it("dispatches to the HTTP executor with the original req", function()
    local http = require("poste-http.http.executors.http")
    local orig = http.run
    local captured_req, captured_cb
    http.run = function(req, cb)
      captured_req = req
      captured_cb = cb
    end

    local req = { method = "GET", url = "https://example.com" }
    local cb = function() end
    executors.run(req, cb)

    http.run = orig
    assert.equals(req, captured_req)
    assert.equals(cb, captured_cb)
  end)

  it("dispatches by method to the registered executor", function()
    local custom = { run = function() end }
    package.loaded["poste-http.http.executors.test_only"] = custom
    local orig_get = executors.get
    executors.get = function(method)
      if method == "TESTONLY" then return custom end
      return orig_get(method)
    end

    -- Dispatch happens through M.get, so overriding get reroutes the run.
    local called
    local orig_run = custom.run
    custom.run = function() called = true end
    executors.run({ method = "TESTONLY" }, function() end)

    executors.get = orig_get
    custom.run = orig_run
    package.loaded["poste-http.http.executors.test_only"] = nil
    assert.is_true(called)
  end)
end)

describe("executors.http", function()
  it("delegates to curl_exec.execute with req and callback", function()
    local curl_exec = require("poste-http.http.curl_exec")
    local orig = curl_exec.execute
    local captured_req, captured_cb
    curl_exec.execute = function(req, cb)
      captured_req = req
      captured_cb = cb
    end

    local http = require("poste-http.http.executors.http")
    local req = { method = "POST", url = "https://example.com", body = "{}" }
    local cb = function() end
    http.run(req, cb)

    curl_exec.execute = orig
    assert.equals(req, captured_req)
    assert.equals(cb, captured_cb)
  end)
end)
