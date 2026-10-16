--- Single entry point for every user-facing notification.
---
--- The message itself stays a bare, capitalized sentence — plugin attribution
--- is carried by the title alone (ui/keymaps-style single-owner primitive).
--- Every message is mirrored into the state.log sink, so what the user saw is
--- always reconstructible from the log file.
---
--- Guardrail: `vim.notify` is only allowed inside this file — tests/run.sh
--- greps for violations.

local state = require("poste-http.state")
local text = require("poste-http.ui.text")
local constants = require("poste-http.constants")

local M = {}

local LEVEL_NAMES = {
  [vim.log.levels.TRACE] = "TRACE",
  [vim.log.levels.DEBUG] = "DEBUG",
  [vim.log.levels.INFO] = "INFO",
  [vim.log.levels.WARN] = "WARN",
  [vim.log.levels.ERROR] = "ERROR",
}

-- Display-column budget: curl/jq failures embed raw command output that
-- otherwise floods both the notify window and :messages.
local MAX_WIDTH = 200
-- …and a line budget, for the same reason one level up: a multi-line panel
-- (`:PosteHttpInfo`, the `:PosteHttpTSInspect` notification fallback) should
-- not push a thousand rows at the user.
local MAX_LINES = 60

--- Normalize one message for display: NUL-strip and length cap. The text is
--- otherwise verbatim — call sites own sentence style, so tool names (jq,
--- curl) and `{{var}}` placeholders survive untouched. Exposed for specs.
---
--- The width budget is PER LINE. A multi-line message is a panel (the
--- `:PosteHttpInfo` status block, the tree-sitter tree dump), and summing the
--- display widths of its lines cut such a panel off mid-way — the last lines
--- vanished behind a trailing "…" — even though no single line was too long.
--- @param msg any
--- @return string
function M._normalize(msg)
  local s = tostring(msg)
  if not s:find("\n", 1, true) then
    return text.truncate(s, MAX_WIDTH)
  end
  local lines = vim.split(s, "\n", { plain = true })
  local shown = math.min(#lines, MAX_LINES)
  local kept = {}
  for i = 1, shown do
    kept[i] = text.truncate(lines[i], MAX_WIDTH)
  end
  if #lines > shown then
    kept[#kept + 1] = string.format("… (%d more lines)", #lines - shown)
  end
  return table.concat(kept, "\n")
end

--- Show a notification and mirror it into the log sink.
--- @param msg any       Message text (tostring'ed; nil-safe)
--- @param level number|nil  vim.log.levels.* (default INFO)
--- @param opts table|nil  { title = string } overrides constants.NOTIFY_TITLE
function M.notify(msg, level, opts)
  level = level or vim.log.levels.INFO
  opts = opts or {}
  msg = M._normalize(msg)
  local title = opts.title or constants.NOTIFY_TITLE
  local emit = function()
    vim.notify(msg, level, { title = title })
    state.log(LEVEL_NAMES[level] or "INFO", msg)
  end
  -- state.log does file IO: never inline in a fast event (uv assert).
  if vim.in_fast_event() then
    vim.schedule(emit)
  else
    emit()
  end
end

return M
