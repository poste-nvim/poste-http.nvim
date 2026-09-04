-- Tests for the messages view formatter (WebSocket frames → lines).

local messages = require("poste-http.http.format.messages")

describe("format.messages.format_messages", function()
  it("renders sent and received sections", function()
    local lines = messages.format_messages({
      metadata = {
        frames = {
          sent = { '{"type": "ping"}' },
          received = { 'pong', '{"type": "message"}' },
        },
      },
    })
    local joined = table.concat(lines, "\n")
    assert.matches("Sent", joined)
    assert.matches("Received", joined)
    assert.matches("→ %{\"type\": \"ping\"%}", joined)
    assert.matches("← pong", joined)
    assert.matches("← %{\"type\": \"message\"%}", joined)
  end)

  it("renders a hint when nothing was received", function()
    local lines = messages.format_messages({
      metadata = { frames = { sent = {}, received = {} } },
    })
    assert.matches("no messages received", table.concat(lines, "\n"))
  end)

  it("tolerates a response without frames", function()
    local lines = messages.format_messages({ metadata = {} })
    assert.is_true(#lines > 0)
  end)
end)
