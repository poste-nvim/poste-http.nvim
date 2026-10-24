-- Coverage for lua/poste-http/http/lua_docs.lua — the Lua documentation
-- provider behind hover in script blocks. This module used to sit in the
-- "exercised via integration specs" list of zero_coverage_smoke_spec.lua,
-- but no spec actually required it (found 2026-10-24); this spec covers the
-- pure logic (script-block extraction, built-in doc lookup) and the no-LSP
-- fallback paths. LSP-dependent behavior is tested with
-- `_ensure_lsp_attached` stubbed false, so the spec never depends on
-- lua-language-server being installed on the runner.

local lua_docs = require("poste-http.http.lua_docs")
local util = require("poste-http.util")

local M = {}

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe("lua_docs", function()
  ---------------------------------------------------------------------------
  -- extract_script_block
  ---------------------------------------------------------------------------
  describe("extract_script_block", function()
    it("extracts a request script block and maps the cursor", function()
      local buf = make_buf({
        "### Run",
        "GET /x",
        "< {%",
        '  local s = "hi"',
        "  print(s)",
        "%}",
      })
      local lines, lua_line, lua_col = lua_docs.extract_script_block(buf, 5, 4)
      assert.is_not_nil(lines)
      assert.equals(4, #lines)
      assert.equals('  local s = "hi"', lines[2])
      assert.equals(3, lua_line)
      assert.equals(4, lua_col)
    end)

    it("extracts a response script block opened with > {%", function()
      local buf = make_buf({
        "POST /x",
        '> {% client.log("done")',
        "%}",
      })
      local lines, lua_line, lua_col = lua_docs.extract_script_block(buf, 2, 10)
      assert.is_not_nil(lines)
      assert.equals(' client.log("done")', lines[1])
      assert.equals(1, lua_line)
      assert.equals(6, lua_col)
    end)

    it("maps a cursor on the opening marker line itself", function()
      local buf = make_buf({
        "< {% local x = 1",
        "%}",
      })
      local lines, lua_line, lua_col = lua_docs.extract_script_block(buf, 1, 12)
      assert.is_not_nil(lines)
      assert.equals(" local x = 1", lines[1])
      assert.equals(1, lua_line)
      assert.equals(8, lua_col)
    end)

    it("clamps the cursor to 1,1 when it sits outside the code", function()
      local buf = make_buf({
        "### Run",
        "GET /x",
        "< {%",
        "  print(1)",
        "%}",
        "",
      })
      local lines, lua_line, lua_col = lua_docs.extract_script_block(buf, 6, 1)
      assert.is_not_nil(lines)
      assert.equals(1, lua_line)
      assert.equals(1, lua_col)
    end)

    it("returns nil with no script block above the cursor", function()
      local buf = make_buf({ "### Run", "GET /x" })
      assert.is_nil(lua_docs.extract_script_block(buf, 2, 1))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("returns nil when the block never closes", function()
      local buf = make_buf({ "< {%", "  print(1)" })
      assert.is_nil(lua_docs.extract_script_block(buf, 2, 3))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    after_each(function()
      -- Wipe leftover scratch buffers so later specs start clean
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buftype == "nofile" then
          pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
      end
    end)
  end)

  ---------------------------------------------------------------------------
  -- built-in doc lookup
  ---------------------------------------------------------------------------
  describe("lookup_builtin", function()
    it("finds a module-qualified entry directly", function()
      local entry = lua_docs.lookup_builtin("string.match")
      assert.is_not_nil(entry)
      assert.equals("string.match(s, p [, i])", entry.sig)
    end)

    it("qualifies a bare method name to its module", function()
      local entry = lua_docs.lookup_builtin("match")
      assert.is_not_nil(entry)
      assert.equals(lua_docs.lua_docs["string.match"], entry)
    end)

    it("walks a dotted path up to the nearest documented prefix", function()
      -- io.stderr is documented; io.stderr.write is not
      local entry = lua_docs.lookup_builtin("io.stderr.write")
      assert.is_not_nil(entry)
      assert.equals("io.stderr", entry.sig)
    end)

    it("returns nil for unknown identifiers", function()
      assert.is_nil(lua_docs.lookup_builtin("flurb"))
    end)
  end)

  describe("is_lua_identifier", function()
    it("accepts lua stdlib roots and bare method names", function()
      assert.is_true(lua_docs.is_lua_identifier("string.match"))
      assert.is_true(lua_docs.is_lua_identifier("tostring"))
      assert.is_true(lua_docs.is_lua_identifier("match"))
    end)

    it("rejects non-lua identifiers", function()
      assert.is_false(lua_docs.is_lua_identifier("http.get"))
      assert.is_false(lua_docs.is_lua_identifier("flurb"))
    end)
  end)

  ---------------------------------------------------------------------------
  -- fallback rendering (no LSP)
  ---------------------------------------------------------------------------
  describe("show_builtin_fallback", function()
    local captured, orig_preview

    before_each(function()
      captured = nil
      orig_preview = util.open_doc_preview
      util.open_doc_preview = function(lines, opts)
        captured = { lines = lines, opts = opts }
      end
    end)

    after_each(function()
      util.open_doc_preview = orig_preview
    end)

    it("renders a markdown code block with sig and desc", function()
      lua_docs.show_builtin_fallback("string.match", "k1")
      assert.is_not_nil(captured)
      assert.equals("```lua", captured.lines[1])
      assert.equals("string.match(s, p [, i])", captured.lines[2])
      assert.equals("k1", captured.opts.track_key)
    end)

    it("renders nothing for an unknown identifier", function()
      lua_docs.show_builtin_fallback("flurb", "k2")
      assert.is_nil(captured)
    end)
  end)

  ---------------------------------------------------------------------------
  -- LSP plumbing, with attachment stubbed so no server is ever needed
  ---------------------------------------------------------------------------
  describe("_create_lsp_buffer", function()
    it("creates a wiped lua scratch buffer with a .lua name", function()
      local buf = lua_docs._create_lsp_buffer()
      assert.is_not_nil(buf)
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      assert.equals("lua", vim.bo[buf].filetype)
      assert.equals("wipe", vim.bo[buf].bufhidden)
      assert.matches("%.lua$", vim.api.nvim_buf_get_name(buf))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("try_lsp_hover without an attached server", function()
    local orig_attached, orig_create, created_buf

    before_each(function()
      orig_attached = lua_docs._ensure_lsp_attached
      orig_create = lua_docs._create_lsp_buffer
      lua_docs._ensure_lsp_attached = function() return false end
      created_buf = nil
      -- Wrap (not replace) creation so the spec can watch the buffer's
      -- lifetime without changing what the function under test does.
      lua_docs._create_lsp_buffer = function()
        created_buf = orig_create(lua_docs)
        return created_buf
      end
    end)

    after_each(function()
      lua_docs._ensure_lsp_attached = orig_attached
      lua_docs._create_lsp_buffer = orig_create
    end)

    it("calls back nil and deletes the temp buffer", function()
      local got
      lua_docs.try_lsp_hover({ "local x = 1" }, 1, 1, function(result)
        got = result
      end)
      assert.is_nil(got)
      assert.is_not_nil(created_buf)
      assert.is_false(vim.api.nvim_buf_is_valid(created_buf))
    end)

    it("calls back nil when buffer creation fails", function()
      lua_docs._create_lsp_buffer = function() return nil end
      local got = "unset"
      lua_docs.try_lsp_hover({ "local x = 1" }, 1, 1, function(result)
        got = result
      end)
      assert.is_nil(got)
    end)
  end)

  describe("show_doc falls back to built-in docs without LSP", function()
    local captured, orig_preview, orig_attached

    before_each(function()
      captured = nil
      orig_preview = util.open_doc_preview
      util.open_doc_preview = function(lines, opts)
        captured = { lines = lines, opts = opts }
      end
      orig_attached = lua_docs._ensure_lsp_attached
      lua_docs._ensure_lsp_attached = function() return false end
    end)

    after_each(function()
      util.open_doc_preview = orig_preview
      lua_docs._ensure_lsp_attached = orig_attached
    end)

    it("shows built-in docs for an identifier inside a script block", function()
      local buf = make_buf({
        "< {%",
        "  local t = tostring(1)",
        "%}",
      })
      lua_docs.show_doc(buf, 2, 14, "tostring")
      assert.is_not_nil(captured)
      assert.equals("tostring(v)", captured.lines[2])
      assert.equals("lua:tostring", captured.opts.track_key)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("qualifies a bare method name before the LSP attempt", function()
      -- "match" alone must resolve to the string.match entry, not nothing
      local buf = make_buf({ "< {%", '  ("s"):match("x")', "%}" })
      lua_docs.show_doc(buf, 2, 8, "match")
      assert.is_not_nil(captured)
      assert.equals("string.match(s, p [, i])", captured.lines[2])
      assert.equals("lua:match", captured.opts.track_key)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)

return M
