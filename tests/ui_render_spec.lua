-- Tests for the scratch-buffer line writer (poste-http.ui.render).
--
-- Replaces the modifiable-toggle + nvim_buf_set_lines boilerplate that was
-- hand-rolled in history.lua / view.lua / buffer.lua / json.lua / outline.lua.

local render = require("poste-http.ui.render")

describe("poste-http.ui.render", function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].modifiable = false
  end)

  after_each(function()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("replaces buffer contents even when the buffer is locked", function()
    render.set_lines(buf, { "alpha", "beta" })
    assert.are_same({ "alpha", "beta" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("locks the buffer again after writing", function()
    render.set_lines(buf, { "x" })
    assert.is_false(vim.bo[buf].modifiable)
  end)

  it("replaces prior contents instead of appending", function()
    render.set_lines(buf, { "one", "two" })
    render.set_lines(buf, { "three" })
    assert.are_same({ "three" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("accepts empty lines including blank entries", function()
    render.set_lines(buf, { "a", "", "b" })
    assert.are_same({ "a", "", "b" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("sets the filetype when asked (and leaves it otherwise)", function()
    render.set_lines(buf, { "x" }, { filetype = "json" })
    assert.equals("json", vim.bo[buf].filetype)

    local buf2 = vim.api.nvim_create_buf(false, true)
    render.set_lines(buf2, { "y" })
    assert.equals("", vim.bo[buf2].filetype)
    vim.api.nvim_buf_delete(buf2, { force = true })
  end)

  it("is a no-op for invalid buffers", function()
    assert.has_no_errors(function() render.set_lines(999999, { "x" }) end)
    assert.has_no_errors(function() render.set_lines(nil, { "x" }) end)
  end)
end)
