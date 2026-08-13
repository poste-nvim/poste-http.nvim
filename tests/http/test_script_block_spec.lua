--- Tests for the unified script/assertion block extraction.
--- Both `scripts.extract_pre_script_blocks` (< marker) and
--- `assertions.extract_assertion_blocks` (> marker) share this implementation.
local script_block = require("poste-http.http.script_block")

describe("script_block.extract_script_blocks", function()
  it("extracts a single-line inline block and replaces it with an empty line", function()
    local stripped, code = script_block.extract_script_blocks("GET /x\n< {% $foo = 1 %}\n", "<")
    assert.equals("GET /x\n\n", stripped)
    assert.equals(" $foo = 1 ", code)
  end)

  it("extracts assertion blocks with the > marker", function()
    local stripped, code = script_block.extract_script_blocks("GET /x\n> {% client.test('a', function() end) %}\n", ">")
    assert.equals("GET /x\n\n", stripped)
    assert.equals(" client.test('a', function() end) ", code)
  end)

  it("does not extract > blocks when marker is <", function()
    local stripped, code = script_block.extract_script_blocks("GET /x\n> {% x() %}\n", "<")
    assert.equals("GET /x\n> {% x() %}\n", stripped)
    assert.is_nil(code)
  end)

  it("extracts multi-line blocks preserving inner lines", function()
    local content = table.concat({
      "GET /x",
      "< {%",
      "  local a = 1",
      "  request.variables.set('k', a)",
      "%}",
    }, "\n")
    local stripped, code = script_block.extract_script_blocks(content, "<")
    assert.equals("GET /x\n\n\n\n", stripped)
    assert.equals("  local a = 1\n  request.variables.set('k', a)", code)
  end)

  it("strips all blocks but only collects code within start_line/end_line", function()
    local content = table.concat({
      "### A",
      "< {% one() %}",
      "",
      "### B",
      "< {% two() %}",
    }, "\n")
    -- Only block B is within lines 4-5
    local stripped, code = script_block.extract_script_blocks(content, "<", 4, 5)
    assert.equals("### A\n\n\n### B\n", stripped)
    assert.equals(" two() ", code)
  end)

  it("collects from all blocks when range is nil", function()
    local content = table.concat({
      "### A",
      "< {% one() %}",
      "### B",
      "< {% two() %}",
    }, "\n")
    local _, code = script_block.extract_script_blocks(content, "<")
    assert.equals(" one() \n two() ", code)
  end)

  it("returns nil code when no blocks match", function()
    local stripped, code = script_block.extract_script_blocks("GET /x\nContent-Type: text/plain\n", "<")
    assert.equals("GET /x\nContent-Type: text/plain\n", stripped)
    assert.is_nil(code)
  end)
end)

describe("script_block external script loading", function()
  local dir
  local external_file
  local buf

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    external_file = dir .. "/external.lua"
    local f = io.open(external_file, "w")
    f:write("local x = 42\n")
    f:close()

    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, dir .. "/test.http")
    vim.api.nvim_set_current_buf(buf)
  end)

  after_each(function()
    pcall(os.remove, external_file)
    pcall(vim.fn.delete, dir, "rf")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("reads an external pre-script file with the < marker", function()
    local stripped, code = script_block.extract_script_blocks("GET /x\n< ./external.lua\n", "<")
    assert.equals("GET /x\n\n", stripped)
    assert.equals("-- external: " .. dir .. "/./external.lua\nlocal x = 42\n", code)
  end)

  it("reads an external assertion file with the > marker", function()
    local _, code = script_block.extract_script_blocks("GET /x\n> ./external.lua\n", ">")
    assert.equals("-- external: " .. dir .. "/./external.lua\nlocal x = 42\n", code)
  end)
end)

describe("legacy wrappers delegate to the shared implementation", function()
  local scripts = require("poste-http.http.scripts")
  local assertions = require("poste-http.http.assertions")

  it("extract_pre_script_blocks uses the < marker", function()
    local filled, code = scripts.extract_pre_script_blocks("GET /x\n< {% a = 1 %}\n", 0, 99)
    assert.equals("GET /x\n\n", filled)
    assert.equals(" a = 1 ", code)
  end)

  it("extract_assertion_blocks uses the > marker", function()
    local filled, code = assertions.extract_assertion_blocks("GET /x\n> {% b = 2 %}\n", 0, 99)
    assert.equals("GET /x\n\n", filled)
    assert.equals(" b = 2 ", code)
  end)
end)