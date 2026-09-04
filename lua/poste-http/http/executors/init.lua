--- Protocol executor dispatch.
---
--- Executors own the subprocess for one protocol and share the canonical
--- response contract (docs/dev/multi-protocol-design.md):
---
---   M.run(req, callback)
---     req      = { method, url, headers, body, buf_dir, timeout, name }
---     callback = function(canonical_response)
---
--- The canonical response carries the protocol-aware `ok` flag stamped by
--- each executor; see lua/poste-http/http/response.lua.

local M = {}

-- Request-line methods with a dedicated executor. Everything else (plain
-- HTTP verbs, unknown methods) falls back to the HTTP executor.
local registry = {
  ["GRAPHQL"] = "poste-http.http.executors.graphql",
  -- ["GRPC"] = "poste-http.http.executors.grpc",           -- Phase 2
  -- ["WEBSOCKET"] = "poste-http.http.executors.websocket", -- Phase 3
}

--- Resolve the executor module for a request-line method.
--- Unknown methods fall back to the HTTP executor.
function M.get(method)
  local name = registry[method and string.upper(method) or ""]
  if not name then
    return require("poste-http.http.executors.http")
  end
  return require(name)
end

--- Run a request through its protocol executor.
function M.run(req, callback)
  M.get(req.method).run(req, callback)
end

return M
