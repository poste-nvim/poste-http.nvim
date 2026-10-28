--- Messages view formatter: renders WebSocket frames into lines (pure).
---
--- Frame transcript shape (docs/dev/multi-protocol-design.md):
---   → outgoing text frames (Sent)
---   ← incoming text frames (Received)
--- Lives in format/ per the layering guardrail: response → lines only,
--- no windows, no IO.

local M = {}

--- Normalize a frame entry: tables carry .data, plain strings are the data.
--- Total by contract: frames re-render from persisted history too, where
--- `.data` can be any JSON type — a nil/table used to raise on the
--- `"→ " .. data` concatenation and take the whole Msgs tab down.
local function frame_data(f)
  local data = type(f) == "table" and f.data or f
  if type(data) == "string" then return data end
  if data == nil or data == vim.NIL then return "" end
  return tostring(data)
end

--- Format the messages view for a response carrying metadata.frames.
--- @param r table|nil  canonical response
--- @return table lines, string filetype
function M.format_messages(r)
  local frames = (r and r.metadata and r.metadata.frames) or {}
  local sent = frames.sent or {}
  local received = frames.received or {}

  local lines = {}
  if #sent == 0 and #received == 0 then
    return { "(no messages received)" }, "text"
  end

  if #sent > 0 then
    table.insert(lines, "Sent (" .. #sent .. ")")
    for _, f in ipairs(sent) do
      -- Same normalization as received frames: a frame entry may be a plain
      -- string (the ws_session send path today) or a { data = ... } table.
      table.insert(lines, "→ " .. frame_data(f))
    end
    if #received > 0 then
      table.insert(lines, "")
    end
  end

  if #received > 0 then
    table.insert(lines, "Received (" .. #received .. ")")
    for _, f in ipairs(received) do
      table.insert(lines, "← " .. frame_data(f))
    end
  end

  return lines, "text"
end

return M
