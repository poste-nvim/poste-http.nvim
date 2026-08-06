local request_vars = require("poste-http.http.request_vars")
local ts_query = require("poste-http.http.ts_query")

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
  local cache = require("poste-http.http.cache")
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

--- Jump to the definition of a client.run("#target", ...) reference inside a
--- SCRIPT block. Resolves the target through the buffer's imports and opens
--- the imported file at the request block.
--- @param buf number
--- @param line_num number  1-based cursor line
--- @param col number       0-based cursor column
--- @return boolean  true when the line contains a client.run call (handled or
---                  failed); false when this is not a client.run reference
function M.goto_client_run_definition(buf, line_num, col)
  local line_text = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1] or ""
  local pos = col + 1

  local call_s, call_e = line_text:find("client%.run%s*%(")
  if not call_s then return false end

  -- First quoted "#target" after the call: "#alias.Name" or "#Name"
  local qs, qe, target = line_text:find('["\']#([^"\']+)["\']', call_e + 1)
  if not qs then return false end

  -- Only handle when the cursor is on the quoted reference
  if pos < qs or pos > qe then return false end

  local import_mod = require("poste-http.http.import")
  local resolved, err = import_mod.resolve_request_reference(target, buf)
  if not resolved then
    vim.notify(err or ("Cannot resolve request '%s'"):format(target), vim.log.levels.WARN)
    return true
  end

  vim.cmd("normal! m'")
  vim.cmd("edit " .. vim.fn.fnameescape(resolved.path))
  local target_text = (vim.api.nvim_buf_get_lines(0, resolved.line - 1, resolved.line, false) or {})[1] or ""
  local name_col = (target_text:find(vim.pesc(resolved.request_name)) or 2) - 1
  vim.api.nvim_win_set_cursor(0, { resolved.line, name_col })
  return true
end

return M
