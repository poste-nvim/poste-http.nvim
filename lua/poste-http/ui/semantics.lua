--- HTTP semantics → highlight group mappings.
---
--- Single source of truth for "which highlight group represents this method /
--- status". The groups themselves are defined and themed in
--- http/highlights.lua; this module only decides which group applies, so new
--- methods and UI surfaces stay in sync (this used to be four drifting method
--- tables and two status functions).

local M = {}

local METHOD_HL = {
  GET = "PosteMethodGET",
  POST = "PosteMethodPOST",
  PUT = "PosteMethodPUT",
  DELETE = "PosteMethodDELETE",
  PATCH = "PosteMethodPATCH",
  HEAD = "PosteMethodHEAD",
  OPTIONS = "PosteMethodOPTIONS",
  SCRIPT = "PosteMethodScript",
  GRAPHQL = "PosteMethodScript",
  GRPC = "PosteMethodScript",
  WEBSOCKET = "PosteMethodScript",
  RUN = "PosteRun",
}

--- Highlight group for an HTTP method token (case-insensitive).
--- Unknown / placeholder methods ("", "--", nil) map to PosteMethodOther.
--- Callers with extra semantics (e.g. outline's "@" file vars) special-case
--- before delegating.
--- @param method string|nil
--- @return string
function M.method_hl(method)
  if type(method) ~= "string" then return "PosteMethodOther" end
  if method == "" or method == "--" then return "PosteMethodOther" end
  return METHOD_HL[method:upper()] or "PosteMethodOther"
end

--- Highlight group for an HTTP status code. Accepts numbers or strings;
--- anything without a positive status (0, nil, "-") renders as a comment.
--- @param status number|string|nil
--- @return string
function M.status_hl(status)
  local sc = tonumber(status) or 0
  if sc <= 0 then return "Comment" end
  if sc < 300 then return "PosteStatus2xx" end
  if sc < 400 then return "PosteStatus3xx" end
  if sc < 500 then return "PosteStatus4xx" end
  return "PosteStatus5xx"
end

return M
