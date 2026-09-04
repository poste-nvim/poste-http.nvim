-- Tests for block operator extraction (docs/dev/multi-protocol-design.md).
--
-- Operators are namespaced comment directives (`# @grpc-proto echo.proto`)
-- carrying per-protocol executor options inside a request block.

local block_operators = require("poste-http.http.block_operators")

local function extract(block_text)
  local lines = vim.split(block_text, "\n", { plain = true })
  return block_operators.extract(lines, 1, #lines)
end

describe("block_operators.extract", function()
  it("returns an empty table when there are no operators", function()
    assert.same({}, extract("# just a comment\nGET /x"))
  end)

  it("extracts a valued operator", function()
    local ops = extract("# @grpc-proto echo.proto\nGRPC localhost:5001/x/Y")
    assert.same({ ["grpc-proto"] = { "echo.proto" } }, ops)
  end)

  it("extracts a bare flag as an empty string value", function()
    local ops = extract("# @grpc-plaintext\nGRPC localhost:5001/x/Y")
    assert.same({ ["grpc-plaintext"] = { "" } }, ops)
  end)

  it("collects repeated operators into a list", function()
    local ops = extract("# @grpc-proto a.proto\n# @grpc-proto b.proto\nGRPC localhost:5001/x/Y")
    assert.same({ ["grpc-proto"] = { "a.proto", "b.proto" } }, ops)
  end)

  it("preserves spaces inside the value", function()
    local ops = extract("# @grpc-flags -plaintext -max-time 5")
    assert.same({ ["grpc-flags"] = { "-plaintext -max-time 5" } }, ops)
  end)

  it("ignores plain comments and header lines", function()
    local ops = extract("# hello world\n# @param not tracked\nGET /x")
    assert.same({ ["param"] = { "not tracked" } }, ops)
  end)

  it("respects the requested line range", function()
    local lines = { "# @grpc-proto a.proto", "GRPC localhost:5001/x/Y", "# @grpc-proto b.proto" }
    local ops = block_operators.extract(lines, 3, 3)
    assert.same({ ["grpc-proto"] = { "b.proto" } }, ops)
  end)

  it("tolerates missing bounds", function()
    local lines = { "# @grpc-proto a.proto" }
    local ops = block_operators.extract(lines, nil, nil)
    assert.same({ ["grpc-proto"] = { "a.proto" } }, ops)
  end)
end)
