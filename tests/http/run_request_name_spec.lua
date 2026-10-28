--- Regression: a pre-script that injects variables shifted the cursor line by
--- the injected count, but every consumer of that line resolves against the
--- REAL buffer (which never gained lines). With the cursor on the block's
--- last line the shifted line fell outside the block, the request name
--- resolved to nil, the response was not cached under its name, and later
--- `{{Name.response...}}` refs broke with "Cannot resolve variable".
---
--- Fix: keep `line` in buffer coordinates — the injected lines exist only in
--- the resolved content string, never in the buffer.
local state = require("poste-http.state")

describe("run_request keeps the request name when a pre-script injects vars", function()
  local run
  local orig_execute

  before_each(function()
    package.loaded["poste-http.http.curl_exec"] = nil
    package.loaded["poste-http.http.run"] = nil
    run = require("poste-http.http.run")
    state._busy = false

    local curl_exec = require("poste-http.http.curl_exec")
    orig_execute = curl_exec.execute
    curl_exec.execute = function(_, callback)
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

  it("resolves the block name with the cursor on the block's last line", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local content = table.concat({
      "### named_login",
      "POST http://127.0.0.1:8899/login",
      "Content-Type: application/json",
      "",
      "< {% request.variables.set('token', 'abc') %}",
      '{ "user": "u" }',
    }, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
    vim.api.nvim_set_current_buf(buf)
    -- Last line of the block: the injected @var line pushes the shifted
    -- cursor line past the block end, which used to lose the name.
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    run.run_request()
    vim.wait(300, function() return state.last_response ~= nil and not state._busy end)

    local r = state.last_response
    assert.truthy(r, "request should have completed")
    assert.equal("named_login", r.request_name)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("still resolves the name with the cursor on the request line", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local content = table.concat({
      "### named_login",
      "POST http://127.0.0.1:8899/login",
      "< {% request.variables.set('token', 'abc') %}",
    }, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    run.run_request()
    vim.wait(300, function() return state.last_response ~= nil end)

    local r = state.last_response
    assert.truthy(r, "request should have completed")
    assert.equal("named_login", r.request_name)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
