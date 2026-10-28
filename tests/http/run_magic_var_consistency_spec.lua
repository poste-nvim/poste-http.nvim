--- Regression: `process_form_data` read its block bounds from the BUFFER but
--- applied them to the resolved CONTENT, which pre-script/global injections
--- had already shifted. Magic-var lines near the block's tail fell outside
--- the substitution window and the later VarResolver pass drew a SECOND,
--- different value for the same `{{$uuid}}`/`{{$timestamp}}` — one request
--- carrying two different magic values.
---
--- Fix: run.lua passes the content-coordinate block bounds explicitly, so
--- the substitution window always matches the content it is applied to.
local state = require("poste-http.state")

describe("run_request keeps one magic value per draw across the block", function()
  local run
  local orig_execute
  local captured

  before_each(function()
    package.loaded["poste-http.http.curl_exec"] = nil
    package.loaded["poste-http.http.run"] = nil
    run = require("poste-http.http.run")
    state._busy = false

    local curl_exec = require("poste-http.http.curl_exec")
    orig_execute = curl_exec.execute
    captured = nil
    curl_exec.execute = function(req, callback)
      captured = req
      vim.schedule(function()
        callback({
          status = 200,
          status_text = "OK",
          body = "mocked",
          headers = {},
          metadata = {},
        })
      end)
    end
  end)

  after_each(function()
    if orig_execute then
      package.loaded["poste-http.http.curl_exec"] = nil
      orig_execute = nil
    end
    package.loaded["poste-http.http.run"] = nil
    state._busy = false
    state.set_pending_request(nil)
    state.set_response(nil)
  end)

  it("uses the same generated uuid for refs before and after the injection point", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local content = table.concat({
      "### magic_block",
      "POST http://127.0.0.1:8899/echo",
      "X-Before: {{$uuid}}",
      "< {% request.variables.set('token', 'abc') %}",
      "Content-Type: application/json",
      "",
      '{ "id": "{{$uuid}}" }',
    }, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    run.run_request()
    vim.wait(300, function() return captured ~= nil and not state._busy end)

    assert.truthy(captured, "request should have reached curl")
    local body = captured.body or ""
    local header_uuid
    for _, h in ipairs(captured.headers or {}) do
      if h[1] == "X-Before" then header_uuid = h[2] end
    end
    assert.truthy(header_uuid, "X-Before header should be present")
    -- Both occurrences must carry the SAME drawn value: the header is
    -- substituted in the same form_data pass as the body.
    assert.truthy(body:find(header_uuid, 1, true),
      "body uuid must equal the header uuid, header=" .. tostring(header_uuid)
      .. " body=" .. tostring(body))
    assert.falsy(body:match("{{%$uuid}}"),
      "no literal {{$uuid}} may remain in the sent body, got: " .. tostring(body))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
