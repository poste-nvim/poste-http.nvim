--- Regression tests: HTTP request block boundary.
--- Ensures describe.lua (tree-sitter semantic) and cache.lua (UI) agree on the
--- block boundary rule — trailing blank lines after a request body are NOT part
--- of the request block range, but trailing comment lines still resolve to the
--- block (so a cursor on a block-end comment can still run the request).
--- Both now share lua/poste-http/http/block_boundary.lua.

local poste_describe = require("poste-http.http.describe")
local block_boundary = require("poste-http.http.block_boundary")
local cache = require("poste-http.http.cache")

local magic_lines = {
  "### 0 Magic variables: all four types",
  "POST {{base_url}}/post",
  "Content-Type: application/json",
  "",
  "{",
  '  "name": "doge",',
  '  "value": 13',
  "}",
  "",
  "# ────────────────────────────────────────────────────────────",
  "# 0.1 {{$magic}} — magic variable substitution",
  "# ────────────────────────────────────────────────────────────",
  "",
  "### 0.1 Magic variables: all four types",
  "POST {{base_url}}/post",
}
local magic_vars = table.concat(magic_lines, "\n")

describe("block_boundary shared helper", function()
  it("is_separator", function()
    assert.is_true(block_boundary.is_separator("###"))
    assert.is_true(block_boundary.is_separator("### Get"))
    assert.is_true(block_boundary.is_separator("  ### Get"))
    assert.is_false(block_boundary.is_separator("GET /x"))
    assert.is_false(block_boundary.is_separator("# not a separator"))
  end)

  it("is_comment", function()
    assert.is_true(block_boundary.is_comment("# foo"))
    assert.is_true(block_boundary.is_comment("  # foo"))
    assert.is_true(block_boundary.is_comment("-- foo"))
    assert.is_false(block_boundary.is_comment(""))
    assert.is_false(block_boundary.is_comment('{"a":1}'))
    assert.is_false(block_boundary.is_comment("GET /x"))
  end)

  it("is_content", function()
    assert.is_true(block_boundary.is_content("GET /x"))
    assert.is_true(block_boundary.is_content("  {"))
    assert.is_false(block_boundary.is_content("# c"))
    assert.is_false(block_boundary.is_content("-- c"))
    assert.is_false(block_boundary.is_content(""))
    assert.is_false(block_boundary.is_content())
  end)

  it("compute_block_range trims trailing comments and blanks", function()
    local e, l = block_boundary.compute_block_range(magic_lines, 1)
    assert.equals(13, e)
    assert.equals(8, l)
  end)

  it("compute_block_range last block ends at last line", function()
    local e, l = block_boundary.compute_block_range(magic_lines, 14)
    assert.equals(15, e)
    assert.equals(15, l)
  end)
end)

describe("semantic block boundary", function()
  -- line 14 is second ###; block 1 body ends at line 8 (`}`).
  -- lines 9-13 are trailing blank / comment / separator → must NOT be included.
  it("computes last_content_line before trailing comments", function()
    local blocks = poste_describe.describe_content(magic_vars, "t.http")
    assert.is_true(#blocks >= 1)
    assert.equal(1, blocks[1].line)
    assert.equal(8, blocks[1].last_content_line)
    assert.equal(13, blocks[1].end_line)
  end)

  it("block_at_line returns the block on a trailing comment line", function()
    local blocks = poste_describe.describe_content(magic_vars, "t.http")
    -- line 10 is inside the trailing `# ...` comment block → belongs to block 1
    local b = poste_describe.block_at_line(blocks, 10)
    assert.is_not_nil(b)
    assert.equals(1, b.line)
  end)

  it("block_at_line returns block for its real content", function()
    local blocks = poste_describe.describe_content(magic_vars, "t.http")
    local b = poste_describe.block_at_line(blocks, 5)
    assert.is_not_nil(b)
    assert.equals(1, b.line)
  end)
end)

describe("describe and cache agree on block boundaries", function()
  local function create_buf(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
  end

  it("identical start/end/last_content for both paths", function()
    local buf = create_buf(magic_lines)
    local c = cache.get_buffer_cache(buf)
    assert.equals(1, c.blocks[1].start_line)
    assert.equals(13, c.blocks[1].end_line)
    assert.equals(8, c.blocks[1].last_content_line)

    local blocks = poste_describe.describe_content(magic_vars, "t.http")
    assert.equals(1, blocks[1].line)
    assert.equals(13, blocks[1].end_line)
    assert.equals(8, blocks[1].last_content_line)
  end)

  it("both resolve a trailing comment line to the same block", function()
    local buf = create_buf(magic_lines)
    local cb = cache.get_block_at_line(buf, 10)
    assert.is_not_nil(cb, "cache should resolve trailing comment line")
    assert.equals(1, cb.start_line)
    local blocks = poste_describe.describe_content(magic_vars, "t.http")
    local db = poste_describe.block_at_line(blocks, 10)
    assert.is_not_nil(db, "describe should resolve trailing comment line")
    assert.equals(1, db.line)
  end)
end)