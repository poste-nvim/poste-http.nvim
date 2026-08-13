--- Tests for source-buffer extmark highlights, including client.run targets
--- inside SCRIPT blocks.
local treesitter = require("poste-http.http.treesitter")

local function extmark_groups(buf, row)
  local marks = vim.api.nvim_buf_get_extmarks(buf, treesitter.ns, { row, 0 }, { row, -1 }, { details = true })
  local groups = {}
  for _, m in ipairs(marks) do
    groups[#groups + 1] = m[4].hl_group
  end
  return groups
end

describe("treesitter client.run target highlights", function()
  it("highlights #alias.Name targets inside script blocks", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "### Orchestration",
      "SCRIPT",
      "> {%",
      '  local login = client.run("#api.Login", {})',
      "%}",
    })

    treesitter.highlight_var_refs(buf)

    local groups = extmark_groups(buf, 3)
    assert.is_true(vim.tbl_contains(groups, "PosteRunTarget"),
      "expected PosteRunTarget for #api. prefix, got: " .. vim.inspect(groups))
    assert.is_true(vim.tbl_contains(groups, "PosteRequestName"),
      "expected PosteRequestName for request name, got: " .. vim.inspect(groups))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("highlights bare #Name targets with PosteRequestName", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "### Orchestration",
      "SCRIPT",
      "> {%",
      '  local r = client.run("#Login", {})',
      "%}",
    })

    treesitter.highlight_var_refs(buf)

    local groups = extmark_groups(buf, 3)
    assert.is_true(vim.tbl_contains(groups, "PosteRequestName"),
      "expected PosteRequestName, got: " .. vim.inspect(groups))
    assert.is_false(vim.tbl_contains(groups, "PosteRunTarget"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("treesitter Lua import var ref highlights", function()
  it("subdivides alias, dots and keys in @var = alias.keypath", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "@my_name = m.config.endpoint" })

    treesitter.highlight_var_refs(buf)

    local groups = extmark_groups(buf, 0)
    assert.is_true(vim.tbl_contains(groups, "PosteImportRefAlias"),
      "expected PosteImportRefAlias for alias, got: " .. vim.inspect(groups))
    assert.is_true(vim.tbl_contains(groups, "PosteImportRefDot"),
      "expected PosteImportRefDot for '.' separators, got: " .. vim.inspect(groups))
    assert.is_true(vim.tbl_contains(groups, "PosteImportRefKey"),
      "expected PosteImportRefKey for path segments, got: " .. vim.inspect(groups))
    assert.is_false(vim.tbl_contains(groups, "PosteImportRefIndex"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("highlights array index separately in @var = alias.key[1]", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "@first_tag = m.tags[1]" })

    treesitter.highlight_var_refs(buf)

    local groups = extmark_groups(buf, 0)
    assert.is_true(vim.tbl_contains(groups, "PosteImportRefIndex"),
      "expected PosteImportRefIndex for [1], got: " .. vim.inspect(groups))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("does not highlight plain var values", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "@plain = hello world" })

    treesitter.highlight_var_refs(buf)

    local groups = extmark_groups(buf, 0)
    assert.is_false(vim.tbl_contains(groups, "PosteImportRefAlias"))
    assert.is_false(vim.tbl_contains(groups, "PosteImportRefKey"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
