local variable_inspector = require("poste-http.http.variable_inspector")
local request_deps = require("poste-http.http.request_deps")
local state = require("poste-http.state")

local function setup_buffer(lines)
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, os.tmpname() .. ".http")
  vim.bo[buf].filetype = "poste_http"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

describe("variable_inspector collect_entries", function()
  local buf

  before_each(function()
    state.global_vars = {}
    state.script_variables = {}
    state.current_env = ""
  end)

  after_each(function()
    state.global_vars = {}
    state.script_variables = {}
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    pcall(vim.cmd, "bwipeout!")
  end)

  it("displays a table-valued request ref as JSON, not 'table: 0x...'", function()
    request_deps.cache_response("request1", {
      body = vim.json.encode({ obj = { name = "doge" } }),
    })

    buf = setup_buffer({
      "### request1",
      "GET /request1",
      "",
      "### request2",
      "@obj = {{request1.response.body.obj}}",
      "POST /request2",
      "Content-Type: application/json",
      "",
      '{"obj": {{request1.response.body.obj}}}',
    })

    local entries, sorted = variable_inspector._test.collect_entries(buf, 5)
    assert.truthy(entries)
    assert.truthy(entries.obj)
    assert.equals('{"name":"doge"}', entries.obj[1].value)
    assert.is_falsy(entries.obj[1].value:match("^table:"))
  end)
end)