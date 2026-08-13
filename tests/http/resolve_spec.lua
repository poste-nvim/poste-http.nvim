local resolve = require("poste-http.http.resolve")

describe("resolve.resolve", function()
  local function fake_handlers(calls)
    return {
      prompts = function(content, opts, on_complete)
        table.insert(calls, {
          stage = "prompts",
          content = content,
          mode = opts.mode,
          cursor_line = opts.cursor_line,
        })
        on_complete(content .. " -> prompts")
      end,
      dependencies = function(content, opts, on_complete)
        table.insert(calls, {
          stage = "dependencies",
          content = content,
          mode = opts.mode,
          block_line = opts.block_line,
        })
        on_complete(content .. " -> deps")
      end,
    }
  end

  it("runs request mode as prompts then dependencies", function()
    local calls = {}

    local result = nil
    resolve.resolve("body", {
      mode = "request",
      cursor_line = 12,
      block_line = 10,
      handlers = fake_handlers(calls),
    }, function(resolved)
      result = resolved
    end)

    assert.equals("body -> prompts -> deps", result)
    assert.equals(2, #calls)
    assert.equals("prompts", calls[1].stage)
    assert.equals("dependencies", calls[2].stage)
    assert.equals("request", calls[1].mode)
    assert.equals("request", calls[2].mode)
  end)

  it("runs import mode as dependencies then prompts", function()
    local calls = {}

    local result = nil
    resolve.resolve("body", {
      mode = "import",
      cursor_line = 12,
      block_line = 10,
      handlers = fake_handlers(calls),
    }, function(resolved)
      result = resolved
    end)

    assert.equals("body -> deps -> prompts", result)
    assert.equals(2, #calls)
    assert.equals("dependencies", calls[1].stage)
    assert.equals("prompts", calls[2].stage)
    assert.equals("import", calls[1].mode)
    assert.equals("import", calls[2].mode)
  end)
end)