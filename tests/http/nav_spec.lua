--- Tests for navigation: gd on client.run("#target", ...) inside SCRIPT blocks.
local nav_util = require("poste-http.http.nav.util")

local function setup_buffers()
  local req_file = os.tmpname() .. ".http"
  local f = io.open(req_file, "w")
  f:write("### Login\nPOST /api/login\nContent-Type: application/json\n\n{\"username\": \"{{username}}\"}\n")
  f:close()

  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, os.tmpname() .. ".http")
  vim.bo[buf].filetype = "poste_http"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "import " .. req_file .. " as api",
    "",
    "### Orchestration",
    "SCRIPT",
    "> {%",
    '  local login = client.run("#api.Login", { username = "u" })',
    "%}",
  })
  return req_file, buf
end

describe("nav_util.goto_client_run_definition", function()
  local req_file
  local buf

  before_each(function()
    req_file, buf = setup_buffers()
    vim.api.nvim_set_current_buf(buf)
  end)

  after_each(function()
    os.remove(req_file)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    pcall(vim.cmd, "bwipeout!")
  end)

  it("jumps to the imported request when the cursor is on the target", function()
    local line_text = vim.api.nvim_buf_get_lines(buf, 5, 6, false)[1]
    local col = line_text:find("Login", 1, true) - 1

    local handled = nav_util.goto_client_run_definition(buf, 6, col)
    assert.is_true(handled)
    assert.are_equal(vim.fn.resolve(req_file), vim.api.nvim_buf_get_name(0))
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert.are_equal(1, cursor[1])
    local target_text = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1] or ""
    assert.matches("### Login", target_text)
  end)

  it("does nothing when the cursor is outside the target", function()
    local handled = nav_util.goto_client_run_definition(buf, 6, 0)
    assert.is_false(handled)
    assert.are_equal(vim.api.nvim_buf_get_name(buf), vim.api.nvim_buf_get_name(0))
  end)

  it("returns false on lines without a client.run call", function()
    local handled = nav_util.goto_client_run_definition(buf, 2, 0)
    assert.is_false(handled)
  end)

  it("handles an unresolvable target without jumping", function()
    local buf2 = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf2, os.tmpname() .. ".http")
    vim.api.nvim_buf_set_lines(buf2, 0, -1, false, {
      "import ./missing.http as api",
      "",
      "### Orchestration",
      "SCRIPT",
      "> {%",
      '  local r = client.run("#api.Nope", {})',
      "%}",
    })
    vim.api.nvim_set_current_buf(buf2)
    local line_text = vim.api.nvim_buf_get_lines(buf2, 5, 6, false)[1]
    local handled = nav_util.goto_client_run_definition(buf2, 6, line_text:find("Nope", 1, true) - 1)
    assert.is_true(handled)
    assert.are_equal(vim.api.nvim_buf_get_name(buf2), vim.api.nvim_buf_get_name(0))
    pcall(vim.api.nvim_buf_delete, buf2, { force = true })
  end)
end)

describe("nav.text.goto_definition on client.run", function()
  it("jumps through the default text nav path", function()
    local req_file, buf = setup_buffers()
    vim.api.nvim_set_current_buf(buf)
    local line_text = vim.api.nvim_buf_get_lines(buf, 5, 6, false)[1]
    vim.api.nvim_win_set_cursor(0, { 6, line_text:find("Login", 1, true) - 1 })

    require("poste-http.http.nav.text").goto_definition()

    assert.are_equal(vim.fn.resolve(req_file), vim.api.nvim_buf_get_name(0))
    assert.are_equal(1, vim.api.nvim_win_get_cursor(0)[1])
    os.remove(req_file)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    pcall(vim.cmd, "bwipeout!")
  end)
end)
