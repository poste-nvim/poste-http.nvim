local state = require("poste-http.state")

describe("run_request busy-flag reset", function()
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
  end)

  it("resets _busy when the cursor is on an inter-block separator line", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local content = table.concat({
      "### recolor",
      "GET http://127.0.0.1:8899/cloth/recolor",
      "",
      "### recolor detail",
      "GET http://127.0.0.1:8899/cloth/recolor/detail",
      "",
    }, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    run.run_request()
    assert.equal(false, state._busy)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("resets _busy when the cursor is on the file-head area before the first block", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local content = table.concat({
      "@host = http://127.0.0.1:8899",
      "",
      "### recolor",
      "GET {{host}}/cloth/recolor",
      "",
    }, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    run.run_request()
    assert.equal(false, state._busy)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
