-- Regression coverage for format/util.lua JSON re-encoding and form decoding.

local fmt_util = require("poste-http.http.format.util")

describe("json_pretty string/key escaping", function()
  it("escapes double quotes inside object keys", function()
    -- The key a"b is legal JSON; re-encoding it unescaped produced
    -- invalid JSON ("a"b": 1) that broke the json treesitter parse.
    local out = fmt_util.json_pretty({ ['a"b'] = 1 })
    assert.equals('{\n  "a\\"b": 1\n}', out)
  end)

  it("escapes backslashes and control chars in keys and values", function()
    local out = fmt_util.json_pretty({ ["k\\x"] = "line1\nline2\x01" })
    assert.is_truthy(out:find('k\\\\x', 1, true), "key backslash must be escaped")
    assert.is_truthy(out:find('line1\\nline2', 1, true), "value newline must be escaped")
    assert.is_truthy(out:find('\\u0001', 1, true), "control char must become \\u0001")
  end)

  it("round-trips through vim.json.decode", function()
    local original = { ['we"ird'] = { nested = "a\1b" } }
    local out = fmt_util.json_pretty(original)
    local decoded = vim.json.decode(out)
    assert.equals("a\1b", decoded['we"ird'].nested)
  end)
end)

describe("format_urlencoded_body key decoding", function()
  it("decodes percent-escapes and plus signs in keys, not just values", function()
    local lines = fmt_util.format_urlencoded_body("user%20name=john+doe&keep%2Bid=1")
    assert.same({ "  user name: john doe", "  keep+id: 1" }, lines)
  end)
end)

describe("url_decode contract", function()
  it("returns exactly one value (no gsub substitution count)", function()
    -- A bare `return s:gsub(...)` shipped two values; harmless to the
    -- current single-assignment callers but corrupts any future caller
    -- that consumes varargs or table-constructor positions.
    assert.equals(1, select("#", fmt_util.url_decode("a%2Bb")))
  end)

  it("decodes an encoded literal plus before treating + as space", function()
    assert.equals("a+b c", fmt_util.url_decode("a%2Bb+c"))
  end)

  it("leaves malformed escapes as literal text", function()
    assert.equals("100%", fmt_util.url_decode("100%"))
    assert.equals("%ZZ", fmt_util.url_decode("%ZZ"))
  end)
end)

describe("json_pretty mixed-type keys", function()
  it("sorts mixed number/string keys without raising", function()
    -- Lua-built tables (sparse arrays, e.g. from filters) can carry number
    -- and string keys at once; a bare table.sort raised
    -- "attempt to compare number with string".
    local out = fmt_util.json_pretty({ ["b"] = 1, [1] = "x" })
    local decoded = vim.json.decode(out)
    assert.equals("x", decoded["1"])
    assert.equals(1, decoded["b"])
  end)

  it("renders a sparse array as an object without raising", function()
    local t = {}
    t[1] = "a"
    t[3] = "c"
    local out = fmt_util.json_pretty(t)
    assert.equals("a", vim.json.decode(out)["1"])
  end)
end)

describe("json_pretty non-finite numbers", function()
  it("encodes inf/nan as null instead of bare inf/nan", function()
    -- vim.json.decode hands back math.huge for 1e999; a bare "inf"/"nan"
    -- token is invalid JSON and broke every later parse of the output.
    local out = fmt_util.json_pretty({ a = math.huge, b = 0 / 0, c = -math.huge, d = 1 })
    assert.truthy(out:match('"a": null'), out)
    assert.truthy(out:match('"b": null'), out)
    assert.truthy(out:match('"c": null'), out)
    assert.truthy(out:match('"d": 1'), out)
    -- the output must survive a decode round-trip
    local ok, decoded = pcall(vim.json.decode, out)
    assert.truthy(ok, out)
    -- null decodes back to the vim.NIL sentinel, not Lua nil
    assert.equals(vim.NIL, decoded.a)
  end)
end)

-- Regression: `human_size` reaches here from response metadata, which is
-- re-rendered from persisted history — a hand-edited `"file_size": "big"`
-- raised "bad argument #1 to 'abs' (number expected, got string)" and took
-- the whole Verbose / Body tab with it. The contract is now total.
describe("human_size totality", function()
  it("formats the ordinary magnitudes", function()
    assert.equals("0 B", fmt_util.human_size(0))
    assert.equals("512 B", fmt_util.human_size(512))
    assert.equals("1.0 KB", fmt_util.human_size(1024))
    assert.equals("1.5 MB", fmt_util.human_size(1572864))
  end)

  it("returns a string for every non-number instead of raising", function()
    for _, v in ipairs({ "big", "", true, {}, function() end }) do
      local out = fmt_util.human_size(v)
      assert.equals("0 B", out)
    end
    assert.equals("0 B", fmt_util.human_size(nil))
    assert.equals("0 B", fmt_util.human_size(vim.NIL))
  end)

  it("returns a string for non-finite numbers", function()
    -- 1e999 decodes to math.huge; log(inf) is inf, so the unit lookup used
    -- to miss and `%.1f` printed "inf".
    assert.equals("0 B", fmt_util.human_size(1 / 0))
    assert.equals("0 B", fmt_util.human_size(-1 / 0))
    assert.equals("0 B", fmt_util.human_size(0 / 0))
  end)
end)

-- Regression: these helpers are reached with fields from persisted history.
describe("non-string input tolerance", function()
  it("mime_of / is_text_content_type / content_type_extension never raise", function()
    for _, v in ipairs({ 42, {}, true }) do
      assert.equals("", fmt_util.mime_of(v))
      assert.is_true(fmt_util.is_text_content_type(v))
      assert.equals(".bin", fmt_util.content_type_extension(v))
    end
    assert.equals("", fmt_util.mime_of(nil))
  end)

  it("url_decode / split_lines / format_urlencoded_body tolerate non-strings", function()
    assert.equals("", fmt_util.url_decode(nil))
    assert.equals("", fmt_util.url_decode(42))
    assert.same({}, fmt_util.split_lines(nil))
    assert.same({}, fmt_util.split_lines(42))
    assert.is_nil(fmt_util.format_urlencoded_body(nil))
    assert.is_nil(fmt_util.format_urlencoded_body(42))
    assert.equals("", fmt_util.pretty_body(42, "application/json"))
    assert.is_false(fmt_util.is_large_body(42))
  end)

  it("url_decode does not ship gsub's substitution count", function()
    -- `return s:gsub(...)` would hand two values to a varargs caller.
    local n = select("#", fmt_util.url_decode("a%20b"))
    assert.equals(1, n)
  end)
end)
