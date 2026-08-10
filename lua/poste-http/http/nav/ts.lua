local state = require("poste-http.state")
local util = require("poste-http.util")
local ts_query = require("poste-http.http.ts_query")
local nav_util = require("poste-http.http.nav.util")

local M = {}

function M.goto_definition()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local node = ts_query.node_at_point(buf, row, col)
  if not node then
    vim.notify("No tree-sitter node under cursor", vim.log.levels.INFO)
    return
  end

  local node_type = node:type()

  if node_type == "identifier" then
    local variable = ts_query.parent_of_type(node, "variable")
    if variable then
      local var_name = ts_query.node_text(node)
      local req_name = var_name:match("^([^%.]+)")
      if not req_name then req_name = var_name end

      local def_node = nav_util.find_var_def(buf, var_name, cursor[1])
      if def_node then
        local sr, sc = def_node:start()
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
        return
      end

      local req_blocks = ts_query.find_nodes_of_type(buf, "request_block")
      local req_node = nil
      for _, block in ipairs(req_blocks) do
        local name_node = block:named_child(1)
        if name_node and name_node:type() == "request_name" and vim.trim(ts_query.node_text(name_node)) == req_name then
          req_node = name_node
          break
        end
      end
      if req_node then
        local sr, sc = req_node:start()
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
        return
      end

      local buf_path = vim.api.nvim_buf_get_name(buf)
      if buf_path ~= "" then
        local search_dir = vim.fn.fnamemodify(buf_path, ":h")
        local env_file = util.find_file_upwards("env.json", search_dir)
        if env_file then
          local env_lines = vim.fn.readfile(env_file)
          local current_env = state.current_env
          local in_section = false
          local env_pat = '^%s*"' .. vim.pesc(current_env) .. '"%s*:'
          for i, l in ipairs(env_lines) do
            if l:match(env_pat) then in_section = true end
            if in_section and l:match('^%s*"' .. vim.pesc(var_name) .. '"%s*:') then
              vim.cmd("normal! m'")
              vim.cmd("edit " .. vim.fn.fnameescape(env_file))
              vim.api.nvim_win_set_cursor(0, { i, 0 })
              return
            end
            if in_section and l:match("^%s*}") then break end
          end
        end
      end

      local pre_line, pre_col = nav_util.find_var_in_pre_script(buf, var_name, cursor[1])
      if pre_line then
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(0, { pre_line, pre_col })
        return
      end

      vim.notify("Definition not found: " .. var_name, vim.log.levels.WARN)
      return
    end
  end

  if node_type == "variable" then
    local identifier_node = node:named_child(0)
    if not identifier_node then return end
    local var_name = ts_query.node_text(identifier_node)
    local req_name = var_name:match("^([^%.]+)")
    if not req_name then req_name = var_name end

    local def_node = nav_util.find_var_def(buf, var_name, cursor[1])
    if def_node then
      local sr, sc = def_node:start()
      vim.cmd("normal! m'")
      vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
      return
    end

    local req_blocks = ts_query.find_nodes_of_type(buf, "request_block")
    local req_node = nil
    for _, block in ipairs(req_blocks) do
      local name_node = block:named_child(1)
      if name_node and name_node:type() == "request_name" and vim.trim(ts_query.node_text(name_node)) == req_name then
        req_node = name_node
        break
      end
    end
    if req_node then
      local sr, sc = req_node:start()
      vim.cmd("normal! m'")
      vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
      return
    end

    local buf_path = vim.api.nvim_buf_get_name(buf)
    if buf_path ~= "" then
      local search_dir = vim.fn.fnamemodify(buf_path, ":h")
      local env_file = util.find_file_upwards("env.json", search_dir)
      if env_file then
        local env_lines = vim.fn.readfile(env_file)
        local current_env = state.current_env
        local in_section = false
        local env_pat = '^%s*"' .. vim.pesc(current_env) .. '"%s*:'
        for i, l in ipairs(env_lines) do
          if l:match(env_pat) then in_section = true end
          if in_section and l:match('^%s*"' .. vim.pesc(var_name) .. '"%s*:') then
            vim.cmd("normal! m'")
            vim.cmd("edit " .. vim.fn.fnameescape(env_file))
            vim.api.nvim_win_set_cursor(0, { i, 0 })
            return
          end
          if in_section and l:match("^%s*}") then break end
        end
      end
    end

    local pre_line, pre_col = nav_util.find_var_in_pre_script(buf, var_name, cursor[1])
    if pre_line then
      vim.cmd("normal! m'")
      vim.api.nvim_win_set_cursor(0, { pre_line, pre_col })
      return
    end

    vim.notify("Definition not found: " .. var_name, vim.log.levels.WARN)
    return
  end

  if node_type == "import_path" then
    local path = ts_query.node_text(node)
    local buf_name = vim.api.nvim_buf_get_name(buf)
    local buf_dir = buf_name ~= "" and vim.fn.fnamemodify(buf_name, ":h") or vim.fn.getcwd()
    local full_path = vim.fn.simplify(buf_dir .. "/" .. path)
    if vim.fn.filereadable(full_path) == 1 then
      vim.cmd("normal! m'")
      vim.cmd("edit " .. vim.fn.fnameescape(full_path))
    else
      vim.notify("File not found: " .. full_path, vim.log.levels.WARN)
    end
    return
  end

  if node_type == "var_name" then
    local var_name = ts_query.node_text(node)
    local var_defs = ts_query.find_nodes_of_type(buf, "variable_definition")
    local def_node = nil
    for _, def in ipairs(var_defs) do
      local name_node = def:named_child(0)
      if name_node and ts_query.node_text(name_node) == var_name then
        def_node = name_node
        break
      end
    end
    if def_node then
      local sr, sc = def_node:start()
      vim.cmd("normal! m'")
      vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
      return
    end
    vim.notify("Definition not found: @" .. var_name, vim.log.levels.WARN)
    return
  end

  local parent = ts_query.parent_of_type(node, "request_block", "run_directive")
  if parent and parent:type() == "run_directive" then
    local import_mod = require("poste-http.http.import")
    if node_type == "run_target_prefix" then
      local prefix_text = ts_query.node_text(node, buf)
      local alias_name = prefix_text:match("^#(.+)%.$") or prefix_text:match("^(.+)%.$")
      if alias_name then
        local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for i, l in ipairs(buf_lines) do
          local imp_alias = l:match("^import%s+%S+%s+as%s+(%S+)")
          if imp_alias == alias_name then
            local _, ae = l:find("as%s+")
            local col = ae or 0
            vim.cmd("normal! m'")
            vim.api.nvim_win_set_cursor(0, { i, col })
            return
          end
        end
      end
      vim.notify("Alias not found: " .. (alias_name or prefix_text), vim.log.levels.WARN)
      return
    end
    local resolved = import_mod.resolve_run_at_cursor(buf, cursor[1])
    if (resolved.action == "execute" or resolved.action == "execute_all") and resolved.path then
      vim.cmd("normal! m'")
      vim.cmd("edit " .. vim.fn.fnameescape(resolved.path))
      if resolved.line then
        vim.api.nvim_win_set_cursor(0, { resolved.line, 0 })
      end
    else
      vim.notify(resolved.error or "Cannot resolve reference", vim.log.levels.WARN)
    end
    return
  end

  if node_type == "var_value" then
    local text = ts_query.node_text(node, buf)
    local var_name = text:match("{{(.+)}}")
    if var_name then
      local req_name = var_name:match("^([^%.]+)")
      if not req_name then req_name = var_name end
      local def_node = nav_util.find_var_def(buf, var_name, cursor[1])
      if def_node then
        local sr, sc = def_node:start()
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
        return
      end
      local req_blocks = ts_query.find_nodes_of_type(buf, "request_block")
      for _, block in ipairs(req_blocks) do
        local name_node = block:named_child(1)
        if name_node and name_node:type() == "request_name" and vim.trim(ts_query.node_text(name_node)) == req_name then
          local sr, sc = name_node:start()
          vim.cmd("normal! m'")
          vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
          return
        end
      end
    end

    -- Lua import alias.keypath reference: @var = m.a_string
    local alias, keypath = text:match("^(%w+)%.(.+)$")
    if alias and keypath then
      local sr, sc, er, ec = node:range()
      local rel_col = col - sc
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local import_mod = require("poste-http.http.import")
      local import_path = nil
      local import_alias_line = nil
      for i, l in ipairs(buf_lines) do
        local imp = import_mod.parse_import_line(l)
        if imp and imp.type == "aliased" and imp.alias == alias then
          import_path = imp.path
          import_alias_line = i
          break
        end
      end
      if not import_path or not import_alias_line then
        vim.notify("Import not found for alias '" .. alias .. "'", vim.log.levels.WARN)
        return
      end
      if rel_col < #alias then
        local l = buf_lines[import_alias_line]
        local as_pos = l:find(" as " .. vim.pesc(alias) .. "%s*$")
        local target_col = (as_pos and as_pos + 3) or 0
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(0, { import_alias_line, target_col })
        return
      end
      local buf_name = vim.api.nvim_buf_get_name(buf)
      local buf_dir = buf_name ~= "" and vim.fn.fnamemodify(buf_name, ":h") or vim.fn.getcwd()
      local full_path = vim.fn.simplify(buf_dir .. "/" .. import_path)
      if vim.fn.filereadable(full_path) == 1 then
        vim.cmd("normal! m'")
        vim.cmd("edit " .. vim.fn.fnameescape(full_path))
        local first_key = keypath:match("^([^%.]+)")
        if first_key then
          local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
          for i, l in ipairs(lines) do
            if l:match('^%s*' .. vim.pesc(first_key) .. '%s*=') or l:match('^%s*%[' .. vim.pesc(first_key) .. '%]') then
              vim.api.nvim_win_set_cursor(0, { i, 0 })
              return
            end
          end
        end
      else
        vim.notify("File not found: " .. full_path, vim.log.levels.WARN)
      end
      return
    end

    vim.notify("Definition not found: " .. tostring(var_name), vim.log.levels.WARN)
    return
  end

  if node_type == "request_name" then
    vim.notify("Request name defined here", vim.log.levels.INFO)
    return
  end

  if node_type == "post_script" or node_type == "pre_script" or node_type == "script_block" then
    -- client.run("#alias.Name", ...) → jump to the imported request definition
    if nav_util.goto_client_run_definition(buf, cursor[1], col) then
      return
    end

    local ok_lua, lua_parser = pcall(vim.treesitter.get_parser, buf, "lua")
    local var_name = nil
    if ok_lua and lua_parser then
      local lua_trees = lua_parser:parse()
      if lua_trees and #lua_trees > 0 then
        local lua_node = lua_trees[1]:root():named_descendant_for_range(cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2])
        if lua_node then
          local lt = lua_node:type()
          if lt == "identifier" then
            var_name = ts_query.node_text(lua_node, buf)
          elseif lt == "variable" then
            local id = lua_node:named_child(0)
            if id then var_name = ts_query.node_text(id, buf) end
          end
        end
      end
    end
    if not var_name then
      local line_text = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
      local s = col
      while s > 0 and line_text:sub(s, s):match("[%w_]") do s = s - 1 end
      if s < col then s = s + 1 end
      local e = col + 1
      while e <= #line_text and line_text:sub(e, e):match("[%w_]") do e = e + 1 end
      var_name = line_text:sub(s, e - 1)
    end
    if var_name and var_name ~= "" then
      local ok_r, sr, sc, er, ec = pcall(node.range, node)
      if ok_r then
        for i = sr + 1, er + 1 do
          local l = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ""
          local def_text = l:match("^%s*local%s+" .. vim.pesc(var_name) .. "%s*=")
          if not def_text then
            def_text = l:match("^%s*" .. vim.pesc(var_name) .. "%s*=")
          end
          if def_text then
            local name_pos = l:find(vim.pesc(var_name), 1, true)
            if name_pos then
              vim.cmd("normal! m'")
              vim.api.nvim_win_set_cursor(0, { i, name_pos - 1 })
              return
            end
          end
        end
      end
    end
    vim.notify("Definition not found: " .. var_name, vim.log.levels.WARN)
    return
  end

  if node_type == "file_upload" or node_type == "file_upload_token" or node_type == "external_script" or node_type == "external_assertion" then
    local text = ts_query.node_text(node, buf)
    local path = text:match("^[<>][ \t]+(.+)$")
    if path then
      path = vim.trim(path)
      local buf_path = vim.api.nvim_buf_get_name(buf)
      local search_dir = buf_path ~= "" and vim.fn.fnamemodify(buf_path, ":h") or vim.fn.getcwd()
      local full_path
      if path:sub(1, 1) == "/" then
        full_path = path
      elseif path:sub(1, 1) == "~" then
        full_path = vim.fn.expand(path)
      else
        full_path = search_dir .. "/" .. path
      end
      if vim.fn.filereadable(full_path) == 1 then
        vim.cmd("normal! m'")
        vim.cmd("edit " .. vim.fn.fnameescape(full_path))
        return
      end
    end
    vim.notify("File not found: " .. tostring(path), vim.log.levels.WARN)
    return
  end

  local line_text = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
  local s, e = line_text:find("{{(.-)}}")
  while s do
    if col + 1 >= s and col + 1 <= e then
      local var_name = vim.trim(line_text:sub(s + 2, e - 2))
      local def_node = nav_util.find_var_def(buf, var_name, cursor[1])
      if def_node then
        local sr, sc = def_node:start()
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
        return
      end

      local pre_line, pre_col = nav_util.find_var_in_pre_script(buf, var_name, cursor[1])
      if pre_line then
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(0, { pre_line, pre_col })
        return
      end

      break
    end
    s, e = line_text:find("{{(.-)}}", e + 1)
  end

  vim.notify("No definition target under cursor", vim.log.levels.INFO)
end

function M.goto_references()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local node = ts_query.node_at_point(buf, row, col)
  if not node then
    vim.notify("No tree-sitter node under cursor", vim.log.levels.INFO)
    return
  end

  local node_type = node:type()

  state.log("DEBUG", string.format("gd node_type=%s", node_type))
  local symbol_name = nil
  local is_request = false

  if node_type == "identifier" then
    local variable = ts_query.parent_of_type(node, "variable")
    if variable then
      symbol_name = ts_query.node_text(node)
    end
  end

  if not symbol_name and node_type == "variable" then
    local identifier_node = node:named_child(0)
    if identifier_node then
      symbol_name = ts_query.node_text(identifier_node)
    end
  elseif not symbol_name and node_type == "request_name" then
    symbol_name = ts_query.node_text(node)
    is_request = true
  elseif not symbol_name and node_type == "var_name" then
    symbol_name = ts_query.node_text(node)
  end

  if not symbol_name then
    local parent = ts_query.parent_of_type(node, "import_directive", "run_directive")
    if parent then
      if parent:type() == "import_directive" then
        local alias_node = parent:named_child(1)
        if alias_node then
          local alias_text = ts_query.node_text(alias_node)
          local _, _, alias = alias_text:find("as%s+(%S+)")
          if alias then symbol_name = alias end
        end
      elseif parent:type() == "run_directive" then
        local target_node = parent:child_by_field_name("target")
        if target_node then
          symbol_name = vim.trim(ts_query.node_text(target_node))
        end
      end
    end
  end

  if not symbol_name then
    vim.notify("No reference target under cursor", vim.log.levels.INFO)
    return
  end

  local results = {}
  local total = vim.api.nvim_buf_line_count(buf)
  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local esc = vim.pesc(symbol_name)

  if is_request then
    local def_pat = "^%s*###%s*" .. esc .. "%s*$"
    local ref_pat = "{{" .. esc .. "[%}%.]"
    for i = 1, total do
      local text = all_lines[i] or ""
      if text:match(def_pat) then
        table.insert(results, { line = i, col = 0, text = vim.trim(text) })
      elseif not text:match("^%s*[#%-]") then
        local ref_col = text:find(ref_pat)
        if ref_col then
          table.insert(results, { line = i, col = ref_col - 1, text = vim.trim(text) })
        end
      end
    end
  else
    local def_pat = "^%s*@" .. esc .. "[%s=]"
    local prompt_def_pat = "^%s*<<" .. esc .. "%s"
    local ref_pat = "{{" .. esc .. "[%}%.]"
    for i = 1, total do
      local text = all_lines[i] or ""
      if text:match(def_pat) or text:match(prompt_def_pat) then
        table.insert(results, { line = i, col = 0, text = vim.trim(text) })
      elseif not text:match("^%s*[#%-]") then
        local ref_col = text:find(ref_pat)
        if ref_col then
          table.insert(results, { line = i, col = ref_col - 1, text = vim.trim(text) })
        end
      end
    end
  end

  local filtered = {}
  for _, r in ipairs(results) do
    if r.line ~= cursor[1] then
      table.insert(filtered, r)
    end
  end
  results = filtered

  if #results == 0 then
    vim.notify("No other references found for: " .. symbol_name, vim.log.levels.INFO)
    return
  end

  table.sort(results, function(a, b) return a.line < b.line end)

  if #results == 1 then
    local r = results[1]
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(0, { r.line, r.col })
    return
  end

  local items = {}
  for _, r in ipairs(results) do
    table.insert(items, string.format("L%d:%d: %s", r.line, r.col, r.text))
  end

  local selector = require("poste-http.select")
  selector.select(items, "References to '" .. symbol_name .. "'", function(selected)
    if selected then
      local target_line, target_col = selected:match("^L(%d+):(%d+):")
      if target_line then
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(0, { tonumber(target_line), tonumber(target_col) })
      end
    end
  end)
end

return M
