-- Unit tests for detect_context()
-- Tests all completion context types: method, method_or_header, header_value, variable, nil

local context_detector = require("poste-http.http.context_detector")
local detect_context = context_detector.detect_context

local function block_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe("detect_context", function()
  describe("method context", function()
    it("returns 'method' for empty line inside block", function()
      local buf = block_buf({ "### Test", "" })
      local ctx, extra = detect_context("", buf, 2, 0)
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals("method", ctx)
      assert.is_nil(extra)
    end)

    it("returns 'method' for whitespace-only line inside block", function()
      local buf = block_buf({ "### Test", "   " })
      local ctx, extra = detect_context("   ", buf, 2, 3)
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals("method", ctx)
      assert.is_nil(extra)
    end)
  end)

  describe("method_or_header context", function()
    it("returns 'method_or_header' for single word without space inside block", function()
      local buf = block_buf({ "### Test", "GET" })
      local ctx, extra = detect_context("GET", buf, 2, 3)
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals("method_or_header", ctx)
      assert.is_nil(extra)
    end)

    it("returns 'method_or_header' for partial header name inside block", function()
      local buf = block_buf({ "### Test", "Cont" })
      local ctx, extra = detect_context("Cont", buf, 2, 4)
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals("method_or_header", ctx)
      assert.is_nil(extra)
    end)

    it("returns 'method_or_header' for header key on a request line without ### separator", function()
      local buf = block_buf({ "GET /api/users", "Content-T" })
      local ctx, extra = detect_context("Content-T", buf, 2, 9)
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals("method_or_header", ctx)
      assert.is_nil(extra)
    end)

    it("returns 'header_value' on a header line without ### separator", function()
      local buf = block_buf({ "GET /api/users", "Content-Type: " })
      local ctx, extra = detect_context("Content-Type: ", buf, 2, 14)
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals("header_value", ctx)
      assert.equals("Content-Type", extra)
    end)
  end)

  describe("header_value context", function()
    it("returns 'header_value' with header name after colon", function()
      local ctx, extra = detect_context("Content-Type: ")
      assert.equals("header_value", ctx)
      assert.equals("Content-Type", extra)
    end)

    it("returns 'header_value' with header name (no space after colon)", function()
      local ctx, extra = detect_context("Accept:")
      assert.equals("header_value", ctx)
      assert.equals("Accept", extra)
    end)

    it("extracts header name with hyphens", function()
      local ctx, extra = detect_context("X-Custom-Header: ")
      assert.equals("header_value", ctx)
      assert.equals("X-Custom-Header", extra)
    end)
  end)

  describe("variable context", function()
    it("returns 'variable' with empty string after {{", function()
      local ctx, extra = detect_context("GET {{")
      assert.equals("variable", ctx)
      assert.equals("", extra)
    end)

    it("returns 'variable' with partial text after {{", function()
      local ctx, extra = detect_context("GET {{ho")
      assert.equals("variable", ctx)
      assert.equals("ho", extra)
    end)

    it("returns 'variable' with $ prefix for magic vars", function()
      local ctx, extra = detect_context("GET {{$")
      assert.equals("variable", ctx)
      assert.equals("$", extra)
    end)

    it("returns 'variable' with $ prefix and partial text", function()
      local ctx, extra = detect_context("GET {{$ti")
      assert.equals("variable", ctx)
      assert.equals("$ti", extra)
    end)

    it("returns nil after closing }}", function()
      local ctx = detect_context("GET {{host}}")
      assert.is_nil(ctx)
    end)

    it("returns 'variable' for unclosed {{ after }}", function()
      local ctx, extra = detect_context("GET {{host}} {{")
      assert.equals("variable", ctx)
      assert.equals("", extra)
    end)
  end)

  describe("nil context (no completion)", function()
    it("returns nil for comment lines starting with #", function()
      local ctx = detect_context("# comment")
      assert.is_nil(ctx)
    end)

    it("returns 'variable' for << prompt line with unclosed {{", function()
      local ctx, extra = detect_context("<<fruit [{{Get Items.resp")
      assert.equals("variable", ctx)
      assert.equals("Get Items.resp", extra)
    end)

    it("returns 'variable_namespace' for {{Name. with valid prefix", function()
      local ctx, extra = detect_context("{{GetUser.")
      assert.equals("variable_namespace", ctx)
      assert.equals("GetUser", extra.prefix)
      assert.equals("", extra.partial)
    end)

    it("returns 'variable_namespace' for {{Name.res with valid prefix", function()
      local ctx, extra = detect_context("{{GetUser.res")
      assert.equals("variable_namespace", ctx)
      assert.equals("GetUser", extra.prefix)
      assert.equals("res", extra.partial)
    end)

    it("returns 'variable_namespace' for {{Name.response.b with multi-level prefix", function()
      local ctx, extra = detect_context("{{GetUser.response.b")
      assert.equals("variable_namespace", ctx)
      assert.equals("GetUser.response", extra.prefix)
      assert.equals("b", extra.partial)
    end)

    it("returns 'variable' for {{ with invalid prefix (space in name)", function()
      local ctx, extra = detect_context("{{Get Items.resp")
      assert.equals("variable", ctx)
      assert.equals("Get Items.resp", extra)
    end)

    it("returns 'variable' for # << commented prompt with unclosed {{", function()
      local ctx, extra = detect_context("# <<fruit [{{Get Items.resp")
      assert.equals("variable", ctx)
      assert.equals("Get Items.resp", extra)
    end)

    it("returns nil for << prompt line with closed {{", function()
      local ctx = detect_context("<<fruit [{{Get Items.response.body}}]")
      assert.is_nil(ctx)
    end)

    it("returns nil for request name lines starting with ###", function()
      local ctx = detect_context("### Request Name")
      assert.is_nil(ctx)
    end)

    it("returns nil for comment lines starting with --", function()
      local ctx = detect_context("-- comment")
      assert.is_nil(ctx)
    end)

    it("returns nil for @var definition lines", function()
      local ctx = detect_context("@var = value")
      assert.is_nil(ctx)
    end)

    it("returns 'variable' for @var line with unclosed {{", function()
      local ctx, extra = detect_context("@base_url = {{")
      assert.equals("variable", ctx)
      assert.equals("", extra)
    end)

    it("returns nil for lines with ://", function()
      local ctx = detect_context("http://example.com")
      assert.is_nil(ctx)
    end)

    it("returns nil after complete method followed by space", function()
      local ctx = detect_context("GET ")
      assert.is_nil(ctx)
    end)

    it("returns nil for lines with space but no colon", function()
      local ctx = detect_context("some text")
      assert.is_nil(ctx)
    end)
  end)

  describe("edge cases", function()
    it("handles leading whitespace", function()
      local ctx, extra = detect_context("  Content-Type: ")
      assert.equals("header_value", ctx)
      assert.equals("Content-Type", extra)
    end)

    it("handles tabs in whitespace", function()
      local ctx, extra = detect_context("\tAccept: ")
      assert.equals("header_value", ctx)
      assert.equals("Accept", extra)
    end)
  end)

  describe("tree-sitter context detection", function()
    local state = require("poste-http.state")
    local ts_query = require("poste-http.http.ts_query")
    local orig_ts_config
    local orig_is_available

    before_each(function()
      orig_ts_config = state.config.use_treesitter
      state.config.use_treesitter = { context_detector = true }
      orig_is_available = ts_query.is_available
    end)

    after_each(function()
      state.config.use_treesitter = orig_ts_config
      ts_query.is_available = orig_is_available
    end)

    describe("with working parser", function()
      it("returns nil for cursor past the URL on a request line, not 'method'", function()
        local buf = block_buf({ "### ", "POST {{base_url}}/post" })
        if not ts_query.is_available(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
          return -- parser not installed, skip
        end
        local ctx = detect_context("POST {{base_url}}/post", buf, 2, 22)
        vim.api.nvim_buf_delete(buf, { force = true })
        assert.is_nil(ctx)
      end)
    end)

    describe("with broken parser (falls back to regex)", function()
      before_each(function()
        ts_query.is_available = function() return false end
      end)

      it("returns 'method_or_header' for a header name line", function()
        local buf = block_buf({
          "### ",
          "POST {{base_url}}/post/",
          "Content-Type: application/json",
          "A",
        })
        local ctx = detect_context("A", buf, 4, 1)
        vim.api.nvim_buf_delete(buf, { force = true })
        assert.equals("method_or_header", ctx)
      end)

      it("returns nil on a request line URL", function()
        local buf = block_buf({ "### ", "POST {{base_url}}/post/" })
        local ctx = detect_context("POST {{base_url}}/post/", buf, 2, 23)
        vim.api.nvim_buf_delete(buf, { force = true })
        assert.is_nil(ctx)
      end)
    end)
  end)
end)

describe("detect_context: client.run target inside SCRIPT blocks", function()
  local function script_buf(target_line)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "### Orchestration",
      "SCRIPT",
      "> {%",
      target_line,
      "%}",
    })
    return buf
  end

  it("returns run_target_alias with alias and partial", function()
    local buf = script_buf('  local login = client.run("#api.')
    local ctx, extra = detect_context('  local login = client.run("#api.', buf, 4, 35)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.equals("run_target_alias", ctx)
    assert.equals("api", extra.alias)
    assert.equals("", extra.partial)
  end)

  it("returns run_target_alias with a typed partial", function()
    local buf = script_buf('  local login = client.run("#api.Log')
    local ctx, extra = detect_context('  local login = client.run("#api.Log', buf, 4, 38)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.equals("run_target_alias", ctx)
    assert.equals("api", extra.alias)
    assert.equals("Log", extra.partial)
  end)

  it("returns run_target_hash after the # without a dot", function()
    local buf = script_buf('  local r = client.run("#')
    local ctx, extra = detect_context('  local r = client.run("#', buf, 4, 28)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.equals("run_target_hash", ctx)
    assert.equals("", extra)
  end)

  it("returns run_target right after the opening quote", function()
    local buf = script_buf('  local r = client.run("')
    local ctx, extra = detect_context('  local r = client.run("', buf, 4, 27)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.equals("run_target", ctx)
    assert.is_nil(extra)
  end)

  it("keeps script context for other script lines", function()
    local buf = script_buf('  client.log("hi")')
    local ctx = detect_context('  client.log("hi")', buf, 4, 10)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.equals("post_script", ctx)
  end)
end)
