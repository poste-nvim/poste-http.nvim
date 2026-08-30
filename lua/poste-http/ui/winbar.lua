--- Winbar tab-row rendering shared by the response window and history detail.
---
--- Both surfaces render a row of tabs as a winbar string; only the tab list
--- construction differs (which tabs are active depends on the surface).

local M = {}

--- Render tab descriptors into a winbar string.
--- @param tabs table[]  array of { id = string, label = string }
--- @param active_id string|nil  id of the highlighted tab
--- @return string
function M.render_tabs(tabs, active_id)
  local parts = {}
  for _, tab in ipairs(tabs or {}) do
    if tab.id == active_id then
      parts[#parts + 1] = "%#TabLineSel# " .. tab.label .. " %*"
    else
      parts[#parts + 1] = "%#TabLine# " .. tab.label .. " %*"
    end
  end
  return table.concat(parts)
end

--- Id of the tab after stepping direction (-1/+1) from current_id, wrapping
--- around the ends. Unknown ids start from the first tab.
--- @param tabs table[]  array of { id = string }
--- @param current_id string|nil
--- @param direction number|nil  default 1
--- @return string|nil  next tab id, or nil when there are no tabs
function M.cycle(tabs, current_id, direction)
  if not tabs or #tabs == 0 then return nil end
  local idx = 1
  for i, tab in ipairs(tabs) do
    if tab.id == current_id then idx = i end
  end
  local next_idx = ((idx - 1 + (direction or 1)) % #tabs) + 1
  return tabs[next_idx].id
end

return M
