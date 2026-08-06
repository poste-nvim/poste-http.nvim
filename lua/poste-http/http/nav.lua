local state = require("poste-http.state")
local context_detector = require("poste-http.http.context_detector")
local data = require("poste-http.http.data")
local lua_docs = require("poste-http.http.lua_docs")
local nav_ts = require("poste-http.http.nav.ts")
local nav_text = require("poste-http.http.nav.text")

local M = {}

local _hover = nil

local function use_ts()
  return state.config.use_treesitter and state.config.use_treesitter.nav ~= false
end

function M.show_script_api_doc()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local col_1idx = cursor[2] + 1
  local line_text = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1] or ""

  local ctx = context_detector.detect_script_context(buf, line_num, col_1idx)
  if not ctx then return false end

  local ctx_key = ctx == "pre_script" and "pre" or "post"
  local docs = data.script_api_docs[ctx_key]
  if not docs then return false end

  local start = col_1idx
  while start > 1 do
    local ch = line_text:sub(start - 1, start - 1)
    if ch:match("[%w_]") or ch == "." then start = start - 1 else break end
  end

  local finish = col_1idx
  while finish < #line_text do
    local ch = line_text:sub(finish + 1, finish + 1)
    if ch:match("[%w_]") or ch == "." then finish = finish + 1 else break end
  end

  local identifier = start <= finish and line_text:sub(start, finish) or nil
  if not identifier then return false end

  if lua_docs.is_lua_identifier(identifier) then
    lua_docs.show_doc(buf, line_num, col_1idx, identifier)
    return true
  end

  local entry = nil
  local rel = col_1idx - start + 1
  local seg_start = 1
  local prefix_parts = {}

  for segment in identifier:gmatch("[^%.]+") do
    local seg_end = seg_start + #segment - 1
    table.insert(prefix_parts, segment)
    if rel >= seg_start and rel <= seg_end then
      local lookup_path = table.concat(prefix_parts, ".")
      entry = docs[lookup_path]
      while not entry and lookup_path:find("%.") do
        lookup_path = lookup_path:match("^(.+)%.[^%.]+$")
        entry = docs[lookup_path]
      end
      break
    end
    seg_start = seg_end + 2
  end
  if not entry then
    local cword = vim.fn.expand("<cword>")
    if cword and cword ~= "" then entry = docs[cword] end
  end
  if not entry then
    lua_docs.show_doc(buf, line_num, col_1idx, identifier)
    return true
  end

  local lines = {}
  table.insert(lines, entry.sig)
  table.insert(lines, "")
  table.insert(lines, entry.desc)

  local max_width = math.min(math.floor(vim.o.columns * 0.7), 80)
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 4, max_width)

  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.4))
  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
  vim.bo[float_buf].modifiable = false
  vim.bo[float_buf].bufhidden = "wipe"

  local title = ctx == "pre_script" and "Pre-script API" or "Post-script API"
  local win_opts = {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width, height = height, style = "minimal",
    border = "rounded", title = title, title_pos = "left",
  }
  local ok, win = pcall(vim.api.nvim_open_win, float_buf, true, win_opts)
  if not ok then
    win_opts.title = nil; win_opts.title_pos = nil
    ok, win = pcall(vim.api.nvim_open_win, float_buf, true, win_opts)
    if not ok then
      pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
      return true
    end
  end

  vim.keymap.set("n", "q", function() pcall(vim.api.nvim_win_close, win, true) end,
    { buffer = float_buf, noremap = true, silent = true })
  vim.keymap.set("n", "<Esc>", function() pcall(vim.api.nvim_win_close, win, true) end,
    { buffer = float_buf, noremap = true, silent = true })

  return true
end

function M.jump_next()
  local line = vim.fn.line(".")
  local total = vim.fn.line("$")
  for i = line + 1, total do
    local text = vim.fn.getline(i)
    if text:match("^###") then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      return
    end
  end
  vim.notify("No more requests", vim.log.levels.INFO)
end

function M.jump_prev()
  local line = vim.fn.line(".")
  for i = line - 1, 1, -1 do
    local text = vim.fn.getline(i)
    if text:match("^###") then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      return
    end
  end
  vim.notify("No previous requests", vim.log.levels.INFO)
end

function M.show_var_value()
  if M.show_script_api_doc() then return end

  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local col = cursor[2] + 1
  local line_text = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1] or ""

  local var_name = nil
  local s, e = line_text:find("{{(.-)}}")
  while s do
    if col >= s and col <= e then
      var_name = line_text:sub(s + 2, e - 2):gsub("^%s+", ""):gsub("%s+$", "")
      break
    end
    s, e = line_text:find("{{(.-)}}", e + 1)
  end

  if not var_name then
    vim.notify("Not on a {{variable}} reference", vim.log.levels.WARN, { title = "Poste" })
    return
  end

  if _hover and vim.api.nvim_win_is_valid(_hover.win) and _hover.buf == buf and _hover.var_name == var_name then
    vim.api.nvim_set_current_win(_hover.win)
    return
  end

  if _hover and vim.api.nvim_win_is_valid(_hover.win) then
    pcall(vim.api.nvim_win_close, _hover.win, true)
    _hover = nil
  end

  local buf_path = vim.api.nvim_buf_get_name(buf)
  local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cache = require("poste-http.http.cache")
  local block_start, block_end = cache.find_request_block_bounds(buf, line_num)
  local vars = require("poste-http.http.vars")
  local resolver = vars.build_resolver_from_state({
    buf = buf,
    lines = buf_lines,
    file_path = buf_path,
    block_start = block_start,
    block_end = block_end,
    env_name = state.current_env,
  })
  local value = resolver:resolve(var_name)
  local resolved = value or "(unresolved)"

  local title = " " .. var_name .. " "
  local lines = { resolved }

  local float_buf, win
  local ok
  ok, float_buf, win = pcall(vim.lsp.util.open_floating_preview, lines, "text", {
    border = "single",
    title = title,
    title_pos = "left",
    focusable = false,
  })
  if not ok or not float_buf then
    ok, float_buf, win = pcall(vim.lsp.util.open_floating_preview, lines, "text", {
      border = "single",
      focusable = false,
    })
    if not ok or not float_buf then
      return
    end
  end

  _hover = { win = win, buf = buf, var_name = var_name }

  local hover_group = vim.api.nvim_create_augroup("PosteHoverWin_" .. win, { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = hover_group,
    pattern = tostring(win),
    callback = function() _hover = nil end,
  })

  vim.keymap.set("n", "q", function()
    pcall(vim.api.nvim_win_close, win, true)
    _hover = nil
  end, { buffer = float_buf, noremap = true, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    pcall(vim.api.nvim_win_close, win, true)
    _hover = nil
  end, { buffer = float_buf, noremap = true, silent = true })
end

function M.goto_definition()
  if use_ts() then
    nav_ts.goto_definition()
  else
    nav_text.goto_definition()
  end
end

function M.goto_references()
  if use_ts() then
    nav_ts.goto_references()
  else
    nav_text.goto_references()
  end
end

return M