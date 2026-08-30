-- Tests for poste-http.ai — question prefill builder + context registration.
-- Registration specs are conditional on poste-ai.nvim being on the runtimepath
-- (tests/minimal_init.lua appends ../poste-ai.nvim when present).

local ai = require("poste-http.ai")

---------------------------------------------------------------------------
-- build_question (pure)
---------------------------------------------------------------------------

describe("ai.build_question", function()
  it("renders the request block with file/env context", function()
    local q = ai.build_question({
      directive = "Help me with this response:",
      file = "api.http",
      env = "dev",
      request_text = "### Login\nPOST {{api_base}}/login",
    })
    assert.truthy(q:match("^Help me with this response:\n\n"))
    assert.truthy(q:match("`api%.http`, env `dev`"))
    assert.truthy(q:match("```http\n### Login\nPOST {{api_base}}/login\n```"))
  end)

  it("includes errors, response and failed assertions", function()
    local q = ai.build_question({
      file = "api.http",
      env = "dev",
      request_text = "### Get\nGET /x",
      errors_lines = { "  pre_script: boom" },
      response = {
        status = 500,
        status_text = "Internal Server Error",
        url = "http://x/x",
        headers = { { "content-type", "application/json" } },
        body = string.rep("y", 5000),
        metadata = { method = "GET" },
      },
      assertion_results = {
        passed = 0, total = 1, failed = 1,
        tests = { { name = "ok", failed = 1, errors = { "expected 200" } } },
      },
      max_body = 100,
    })
    assert.truthy(q:match("Errors:\n```\npre_script: boom\n```"))
    assert.truthy(q:match("Status: 500 Internal Server Error"))
    assert.truthy(q:match("Request: GET http://x/x"))
    assert.truthy(q:match("%- content%-type: application/json"))
    assert.truthy(q:match("truncated"))
    assert.truthy(q:match("Assertions: 0/1 passed"))
    assert.truthy(q:match("%- FAIL ok: expected 200"))
  end)

  it("never includes resolved request headers, only response headers", function()
    local q = ai.build_question({
      request_text = "GET /x\nAuthorization: Bearer {{api_token}}",
      response = {
        status = 200,
        headers = { { "x-request-id", "abc" } },
        metadata = { request_headers = "Authorization: Bearer real-secret-token" },
      },
    })
    assert.truthy(q:match("{{api_token}}"))
    assert.falsy(q:match("real-secret-token"))
  end)

  it("renders transport errors as failures", function()
    local q = ai.build_question({
      request_text = "GET /x",
      response = { status = 0, protocol = "error", status_text = "connection refused", body = "connection refused" },
    })
    assert.truthy(q:match("Status: 0 connection refused"))
  end)
end)

---------------------------------------------------------------------------
-- context registration (needs poste-ai.nvim on the runtimepath)
---------------------------------------------------------------------------

if ai.available() then
  describe("ai.register (poste-ai on rtp)", function()
    after_each(function()
      pcall(require("poste-ai.context_api").unregister, "http")
    end)

    it("registers a complete 'http' context on poste-ai", function()
      assert.is_true(ai.register())
      local spec = require("poste-ai.context_api").get("http")
      assert.truthy(spec)
      assert.equals("function", type(spec.system_prompt))
      assert.equals("function", type(spec.auto_context))
      assert.same({ "http" }, spec.codeblock.langs)
      assert.equals("function", type(spec.codeblock.confirm))
      assert.equals("function", type(spec.codeblock.execute))
      assert.equals("function", type(spec.codeblock.append_header))
      assert.equals("function", type(spec.mention.match))
      assert.equals("function", type(spec.mention.complete))
      assert.equals("function", type(spec.mention.resolve))
      assert.equals(2, #spec.commands)
      assert.equals("requests", spec.commands[1].name)
      assert.equals("env", spec.commands[2].name)

      -- the mention contract round-trips through the registered spec
      assert.same({ request = "Login" }, spec.mention.match("req/Login"))
      assert.is_nil(spec.mention.match("something-else"))
    end)

    it("is idempotent across repeated registration", function()
      assert.is_true(ai.register())
      assert.is_true(ai.register())
      assert.truthy(require("poste-ai.context_api").get("http"))
    end)
  end)
end
