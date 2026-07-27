local request_vars = require("poste_http.http.request_vars")
local ts_query = require("poste_http.http.ts_query")

local M = {}

function M.find_var_def(buf, var_name, cursor_line)
  local current_req = nil
  local requests = request_vars.collect_requests(buf)
  for _, req in ipairs(requests) do
    if cursor_line >= req.start_line and cursor_line <= req.end_line then
      current_req = req
      break
    end
  end

  local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local first_block_line = nil
  for i, l in ipairs(buf_lines) do
    if l:match("^%s*###") then
      first_block_line = i
      break
    end
  end

  if current_req then
    local prompt_defs = ts_query.find_nodes_of_type(buf, "prompt_variable")
    for _, def in ipairs(prompt_defs) do
      local name_node = def:named_child(0)
      if name_node and ts_query.node_text(name_node) == var_name then
        local sr = def:start()
        local def_line = sr + 1
        if def_line >= current_req.start_line and def_line <= current_req.end_line then
          return name_node
        end
      end
    end
  end

  if current_req then
    local var_defs = ts_query.find_nodes_of_type(buf, "variable_definition")
    for _, def in ipairs(var_defs) do
      local name_node = def:named_child(0)
      if name_node and ts_query.node_text(name_node) == var_name then
        local sr = def:start()
        local def_line = sr + 1
        if def_line >= current_req.start_line and def_line <= current_req.end_line then
          return name_node
        end
      end
    end
  end

  local var_defs = ts_query.find_nodes_of_type(buf, "variable_definition")
  for _, def in ipairs(var_defs) do
    local name_node = def:named_child(0)
    if name_node and ts_query.node_text(name_node) == var_name then
      local sr = def:start()
      local def_line = sr + 1
      if not first_block_line or def_line < first_block_line then
        return name_node
      end
    end
  end

  return nil
end

function M.find_var_in_pre_script(buf, var_name, cursor_line)
  local cache = require("poste_http.http.cache")
  local requests = request_vars.collect_requests(buf)
  local current_req = nil
  for _, req in ipairs(requests) do
    if cursor_line >= req.start_line and cursor_line <= req.end_line then
      current_req = req
      break
    end
  end
  if not current_req then return nil end

  local esc_name = vim.pesc(var_name)
  local set_pattern = 'request%.variables%.set%("' .. esc_name .. '%"'
  local set_pattern_single = "request%.variables%.set%('" .. esc_name .. "%'"

  for i = current_req.start_line, current_req.end_line do
    local t = cache.get_line_type(buf, i)
    if t == "pre_script" then
      local text = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ""
      if text:match(set_pattern) then
        local q = text:find('"' .. esc_name .. '"', 1, true)
        return i, (q and q - 1) or 0
      elseif text:match(set_pattern_single) then
        local q = text:find("'" .. esc_name .. "'", 1, true)
        return i, (q and q - 1) or 0
      end
    end
  end
  return nil
end

return M