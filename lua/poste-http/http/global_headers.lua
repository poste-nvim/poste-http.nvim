local state = require("poste-http.state")

local M = {}

--- Merge global headers into per-request headers.
--- Per-request headers with the same name (case-insensitive) override global ones.
--- Global header values are resolved through the provided resolver at call time.
--- @param per_req_headers table  { { "Key", "Value" }, ... }
--- @param resolver table|nil  VarResolver instance for {{var}} substitution
--- @return table  merged { { "Key", "Value" }, ... }
function M.merge(per_req_headers, resolver)
  if not state.global_headers or not next(state.global_headers) then
    return per_req_headers or {}
  end

  local merged = {}
  local seen = {}

  for name, raw_value in pairs(state.global_headers) do
    local resolved = raw_value
    if resolver and resolver.substitute then
      resolved = resolver:substitute(raw_value)
    end
    table.insert(merged, { name, resolved })
    seen[name:lower()] = #merged
  end

  for _, h in ipairs(per_req_headers or {}) do
    local key = h[1]:lower()
    if seen[key] then
      merged[seen[key]] = h
    else
      table.insert(merged, h)
      seen[key] = #merged
    end
  end

  return merged
end

return M