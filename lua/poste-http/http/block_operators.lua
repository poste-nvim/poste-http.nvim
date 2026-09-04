--- Block operator extraction.
---
--- Operators are namespaced comment directives inside a request block
--- (`# @grpc-proto echo.proto`, `# @ws-wait-ms 3000`) that carry
--- per-protocol executor options. They live in comment lines so parsing,
--- formatting, and the HTTP pipeline stay protocol-neutral; the protocol
--- executor picks the keys it understands (see
--- docs/dev/multi-protocol-design.md).
---
--- M.extract(lines, from_line, to_line) -> operators
---   operators[name] = { value, ... }
---   Repeated operators collect into the list; bare flags store one empty
---   string. from/to are 1-indexed inclusive bounds and default to the
---   whole `lines` array.

local M = {}

function M.extract(lines, from_line, to_line)
  local operators = {}
  if not lines then return operators end
  local from = from_line or 1
  local to = to_line or #lines
  for i = from, to do
    local line = lines[i]
    if line then
      local name, value = line:match("^%s*#%s*@([%w%-]+)%s*(.-)%s*$")
      if name then
        operators[name] = operators[name] or {}
        table.insert(operators[name], value)
      end
    end
  end
  return operators
end

return M
