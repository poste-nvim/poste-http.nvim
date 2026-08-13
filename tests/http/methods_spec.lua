-- Drift guard: lua/poste-http/http/data.lua http_methods must match the
-- method_* tokens in tree-sitter-poste-http/grammar.js.
-- Keeps the two copies in sync without a code-generation step.

local data = require("poste-http.http.data")

local REPO_ROOT = vim.fn.fnamemodify("tests/http/methods_spec.lua", ":p:h:h:h")
local GRAMMAR = REPO_ROOT .. "/tree-sitter-poste-http/grammar.js"

local function grammar_methods()
  local f = io.open(GRAMMAR, "r")
  assert(f, "cannot open grammar.js at " .. GRAMMAR)
  local source = f:read("*a")
  f:close()

  local methods = {}
  for m in source:gmatch("method_%w+: %$ => '(%w+)'") do
    methods[#methods + 1] = m
  end
  table.sort(methods)
  return methods
end

describe("http_methods sync with grammar", function()
  it("matches the method_* tokens in grammar.js", function()
    local from_grammar = grammar_methods()
    local from_lua = vim.deepcopy(data.http_methods)
    table.sort(from_lua)

    assert.are.same(from_grammar, from_lua,
      "data.lua http_methods drifted from grammar.js — update both copies")
  end)

  it("contains at least the standard HTTP methods", function()
    for _, m in ipairs({ "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" }) do
      assert.is_true(vim.tbl_contains(data.http_methods, m))
    end
  end)
end)