--- HTTP request session lifecycle (Phase 2b / F5).
---
--- Each `run_request()` creates a fresh Session at entry. Request-scoped
--- mutable fields live on the session and are mirrored onto `state.*` for
--- backward compatibility. Beginning a session clears all request-scoped
--- state so nothing from the previous request can leak.
---
--- Persistent fields (global_vars, script_variables, http_history, current_env)
--- are intentionally NOT cleared — they span multiple requests by design.

local M = {}

local active = nil

--- Create a new session object (not yet activated).
--- @param meta? table  { buf, line, file, name }
--- @return table
function M.new(meta)
  return {
    response = nil,
    responses = nil,       -- multi-response chain { {name, response}, ... }
    response_index = nil,
    assertion_results = nil,
    script_logs = nil,
    pending_request = nil,
    meta = meta or {},
  }
end

--- Clear every request-scoped state field and activate `session`.
--- Call this at the top of every `run_request()` entry.
--- @param meta? table
--- @return table  the active session
function M.begin(meta)
  local state = require("poste-http.state")
  local session = M.new(meta)

  state.clear_request_scoped()

  pcall(function()
    require("poste-http.http.buffer").reset_multi_response()
  end)

  active = session
  state._http_session = session
  return session
end

--- @return table|nil
function M.active()
  return active
end

--- Discard the active session reference (state fields left as-is for UI).
function M.finish()
  active = nil
  local state = require("poste-http.state")
  state._http_session = nil
end

--- Sync session fields from current state (call after writes to state.*).
function M.sync_from_state()
  if not active then return end
  local state = require("poste-http.state")
  active.response = state.last_response
  active.responses = state.last_responses
  active.response_index = state.response_index
  active.assertion_results = state.last_assertion_results
  active.script_logs = state.last_script_logs
  active.pending_request = state.pending_request
end

return M
