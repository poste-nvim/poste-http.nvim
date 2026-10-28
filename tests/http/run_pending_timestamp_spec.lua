--- Regression: `handle_curl_response` re-stamped `state.pending_request` with
--- `vim.tbl_extend("keep", { timestamp = util.timestamp() }, pending)`. "keep"
--- prefers the FIRST table, so the fresh (response-arrival) timestamp always
--- overwrote the request-send timestamp — a 30s request showed a Request Time
--- 30s late. The pending request is the request-time snapshot written by
--- `start_curl_exec`; it must not be re-stamped when the response arrives.
local state = require("poste-http.state")

describe("run_request keeps the request-send timestamp on the pending request", function()
  local run
  local orig_execute
  local orig_timestamp

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
          metadata = {}, -- no timestamp: handle_curl_response fills it from pending
        })
      end)
    end

    -- A marker value the request-send path (os.date) can never produce: if
    -- the response handler re-stamps pending_request, the marker leaks into
    -- response.metadata.timestamp.
    local util = require("poste-http.util")
    orig_timestamp = util.timestamp
    util.timestamp = function() return "2000-01-01 00:00:00" end
  end)

  after_each(function()
    if orig_execute then
      package.loaded["poste-http.http.curl_exec"] = nil
      orig_execute = nil
    end
    if orig_timestamp then
      require("poste-http.util").timestamp = orig_timestamp
      orig_timestamp = nil
    end
    state._busy = false
    state.set_pending_request(nil)
    state.set_response(nil)
  end)

  it("does not overwrite the request-send timestamp when the response arrives", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local content = table.concat({
      "### timed",
      "GET http://127.0.0.1:8899/ping",
    }, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    run.run_request()
    vim.wait(300, function() return state.last_response ~= nil and not state._busy end)

    local r = state.last_response
    assert.truthy(r, "request should have completed")
    assert.not_equal("2000-01-01 00:00:00", r.metadata.timestamp,
      "response.metadata.timestamp must come from the request-send time, "
      .. "not a re-stamp at response-arrival time")
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
