local ts_query = require("poste-http.http.ts_query")

local M = {}

local function get_separator_ranges(buf)
  local results = ts_query.query_nodes(buf, [[
    (separator) @sep
  ]])
  local ranges = {}
  for _, match in ipairs(results) do
    for _, cap in ipairs(match.captures) do
      if cap.name == "sep" then
        local sr = cap.node:start()
        table.insert(ranges, sr)
      end
    end
  end
  table.sort(ranges)
  return ranges
end

local cached_separators = {}
local cached_tick = nil

function M.foldexpr()
  local buf = 0
  local lnum = vim.v.lnum - 1
  local ct = vim.api.nvim_buf_get_changedtick(buf)

  if cached_tick ~= ct then
    cached_separators = get_separator_ranges(buf)
    cached_tick = ct
  end

  local node = ts_query.node_at_point(buf, lnum, 0)
  if not node then return "=" end

  local foldable = ts_query.parent_of_type(node,
    "json_body", "multiline_variable",
    "pre_script", "post_script", "multipart_boundary",
    "multipart_form_data", "form_body"
  )
  if foldable then
    local sr, _, er, _ = foldable:range()
    if lnum == sr then
      return ">" .. (er - sr)
    end
    if lnum < er then
      return "1"
    end
    return "="
  end

  for i, sep_line in ipairs(cached_separators) do
    if lnum == sep_line then
      local next_sep = cached_separators[i + 1]
      local fold_end = (next_sep and (next_sep - 1)) or vim.api.nvim_buf_line_count(buf) - 1
      local fold_size = fold_end - sep_line
      if fold_size > 0 then
        return ">" .. fold_size
      end
      return "="
    end
    if i < #cached_separators then
      local next_sep = cached_separators[i + 1]
      if lnum > sep_line and lnum < next_sep then
        return "1"
      end
    elseif lnum > sep_line then
      return "1"
    end
  end

  return "="
end

return M