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

describe("treesitter parse-tree inspection", function()
  local SOURCE = {
    "@base = https://example.com",
    "",
    "### List users",
    "GET {{base}}/users",
    "Accept: application/json",
  }

  local function scratch_buf(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "poste_http"
    return buf
  end

  local function parser_available(buf)
    local ok, parser = pcall(vim.treesitter.get_parser, buf, "poste_http")
    return ok and parser ~= nil
  end

  it("dump_tree renders one indented line per node", function()
    local buf = scratch_buf(SOURCE)
    if not parser_available(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
      pending("poste_http parser not installed")
      return
    end
    local parser = vim.treesitter.get_parser(buf, "poste_http")
    local lines = treesitter.dump_tree(parser:parse()[1]:root())

    assert.is_true(#lines > 0, "a parsed buffer must yield nodes")
    assert.equals("document", lines[1]:match("^(%a+)"), "the root is a document node")
    assert.truthy(lines[1]:match("%[%d+:%d+ %- %d+:%d+%]$"), "each line carries a byte range")
    -- at least one nested node is indented, i.e. the walk recursed
    local saw_indent = false
    for _, l in ipairs(lines) do
      if l:match("^  %S") then saw_indent = true break end
    end
    assert.is_true(saw_indent, "child nodes must be indented")
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("inspect shows the tree in a scrollable float instead of truncating it", function()
    local buf = scratch_buf(SOURCE)
    if not parser_available(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
      pending("poste_http parser not installed")
      return
    end

    treesitter.inspect(buf)

    local win = vim.api.nvim_get_current_win()
    local cfg = vim.api.nvim_win_get_config(win)
    assert.equals("editor", cfg.relative, "the tree must open in a floating window")
    local float_buf = vim.api.nvim_win_get_buf(win)
    local text = table.concat(vim.api.nvim_buf_get_lines(float_buf, 0, -1, false), "\n")
    assert.truthy(text:find("document", 1, true), "the float must carry the tree dump")
    assert.is_false(vim.bo[float_buf].modifiable, "a dump is read-only")

    -- `q` closes it (ui/float's default close keys).
    vim.api.nvim_feedkeys("q", "x", false)
    assert.is_false(vim.api.nvim_win_is_valid(win), "q must close the tree float")

    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
