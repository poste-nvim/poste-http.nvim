-- Tests for scripts.collect_script_variables:
-- file-level + block-level @var collection via the canonical vars.lua parser
-- (supports >>>/<<< multiline values and {{var}} reference resolution).

local scripts = require("poste-http.http.scripts")
local state = require("poste-http.state")

local function with_buf(name)
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

describe("collect_script_variables", function()
  local buf
  local orig_env

  before_each(function()
    orig_env = state.current_env
    state.current_env = nil
  end)

  after_each(function()
    state.current_env = orig_env
    if buf then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      buf = nil
    end
  end)

  it("collects file-level vars and resolves {{ref}} chains", function()
    buf = with_buf("/tmp/collect_vars.http")
    local content = table.concat({
      "@base = https://api.example.com",
      "@url = {{base}}/users",
      "",
      "### Get",
      "GET {{url}}",
    }, "\n")

    local result = scripts.collect_script_variables(content, 4, 5)
    assert.equals("https://api.example.com", result.variables.base)
    assert.equals("https://api.example.com/users", result.variables.url)
  end)

  it("collects block-level vars overriding file-level", function()
    buf = with_buf("/tmp/collect_vars2.http")
    local content = table.concat({
      "@mode = file",
      "",
      "### One",
      "@mode = block",
      "GET /x",
    }, "\n")

    local result = scripts.collect_script_variables(content, 4, 5)
    assert.equals("block", result.variables.mode)
  end)

  it("supports >>>/<<< multiline block values", function()
    buf = with_buf("/tmp/collect_vars3.http")
    local content = table.concat({
      "### Payload",
      "@payload = >>>",
      "{\"a\": 1}",
      "<<<",
      "POST /x",
    }, "\n")

    local result = scripts.collect_script_variables(content, 2, 5)
    assert.equals('{"a": 1}', result.variables.payload)
  end)
end)
