local vars = require("poste-http.http.vars")

describe("collect_var_defs", function()
  local collect = vars._test.collect_var_defs

  it("collects single-line @var = value", function()
    local lines = { "@host = http://localhost:8888", "@token = abc123" }
    local r = collect(lines, 1, #lines)
    assert.equals("http://localhost:8888", r.host)
    assert.equals("abc123", r.token)
  end)

  it("collects multi-line @var=>>>...<<<", function()
    local lines = {
      '@headers_block=>>>',
      'X-Custom-Auth: Bearer token123',
      'X-Client-Id: poste-test',
      '<<<',
      'GET {{host}}/test',
    }
    local r = collect(lines, 1, 3)
    assert.not_nil(r.headers_block)
    assert.equals("X-Custom-Auth: Bearer token123\nX-Client-Id: poste-test", r.headers_block)
  end)

  it("collects multi-line var across file-level lines", function()
    local lines = {
      '@multi=>>>',
      'line1',
      'line2',
      'line3',
      '<<<',
      '@other = value',
    }
    local r = collect(lines, 1, #lines)
    assert.equals("line1\nline2\nline3", r.multi)
    assert.equals("value", r.other)
  end)

  it("handles multi-line var with blank lines inside", function()
    local lines = {
      '@body=>>>',
      '{"key": "value"}',
      '',
      '{"key2": "value2"}',
      '<<<',
    }
    local r = collect(lines, 1, #lines)
    assert.equals('{"key": "value"}\n\n{"key2": "value2"}', r.body)
  end)

  it("ignores lines after <<<", function()
    local lines = {
      '@x=>>>',
      'content',
      '<<<',
      'not a var',
    }
    local r = collect(lines, 1, #lines)
    assert.equals("content", r.x)
    assert.is_nil(r.not_a_var)
  end)

  it("strips single quotes from value", function()
    local lines = { "@name = 'hello world'" }
    local r = collect(lines, 1, #lines)
    assert.equals("hello world", r.name)
  end)

  it("strips double quotes from value", function()
    local lines = { '@name = "hello world"' }
    local r = collect(lines, 1, #lines)
    assert.equals("hello world", r.name)
  end)

  it("handles @var without = (space separator)", function()
    local lines = { "@host http://localhost:8888" }
    local r = collect(lines, 1, #lines)
    assert.equals("http://localhost:8888", r.host)
  end)
end)