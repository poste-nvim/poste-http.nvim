local M = {}

M.config = {
  poste_binary = vim.fn.stdpath("data") .. "/poste/bin/poste",
  default_env = "dev",
  split_direction = "vertical",
  split_size = 80,
  log_file = vim.fn.stdpath("cache") .. "/poste.log",
  import_chunk_size = 100,
  response_cache_dir = vim.fn.stdpath("cache") .. "/poste_res",
  max_body_bytes = 100 * 1024,
  max_body_lines = 500,
  body_preview_lines = 20,
  default_view = "body",
  sql_formatters = { "sqlfluff", "sqlfmt", "sql-formatter", "pg_format" },
  keymaps = {
    http_source = {
      run = "<CR>",
      run_hsplit = "<M-CR>",
      jump_next = "]]",
      jump_prev = "[[",
      goto_definition = "gd",
      goto_references = "grr",
      quickfix_next = "]q",
      quickfix_prev = "[q",
      paste_curl = "<leader>rp",
      copy_as_curl = "<leader>rc",
      toggle_outline = "gs",
      pick_env = "<leader>vv",
      show_var_value = "K",
      show_history = "<leader>l",
      help = "g?",
    },
    http_response = {
      close = "q",
      view_body = "B",
      view_request = "R",
      view_verbose = "E",
      view_assertions = "A",
      view_script_logs = "S",
      next_tab = "<Tab>",
      prev_tab = "<S-Tab>",
      rerun = "r",
      next_response = "]",
      prev_response = "[",
      json_filter = "<leader>j",
      json_restore = "<leader>jc",
      json_toggle_raw = "<leader>jr",
      json_outline = "<leader>jo",
      image_preview = "K",
    },
    http_history = {
      close = "q",
      delete_entry = "dd",
      focus_detail = "<CR>",
    },
  },
  highlights = {},
}

M.current_env = M.config.default_env
M.last_response = nil
M.last_responses = nil
M.response_index = nil
M.last_assertion_results = nil
M.last_script_logs = nil
M.last_request = nil
M.pending_request = nil
M.current_view = "body"
M._split_override = nil
M._http_session = nil
M.http_history = {}
M.http_history_max = 100
M.http_history_id_counter = 0
M.global_vars = {}
M.script_variables = {}

M._json = {
  original_lines = nil,
  query = nil,
  is_filtered = false,
  pretty_mode = true,
}

function M.get_keymap(section, action, default)
  local km = M.config.keymaps
  if not km then return default end
  local sec = km[section]
  if not sec then return default end
  local key = sec[action]
  if key == nil then return default end
  if key == false then return nil end
  return key
end

local KEY_DISPLAY_NAMES = {
  ["<Tab>"] = "Tab",
  ["<S-Tab>"] = "S-Tab",
  ["<CR>"] = "Enter",
  ["<Esc>"] = "Esc",
  ["<Space>"] = "<Space>",
  ["<Up>"] = "Up",
  ["<Down>"] = "Down",
  ["<Left>"] = "Left",
  ["<Right>"] = "Right",
  ["<C-Space>"] = "C-Space",
  ["<BS>"] = "BS",
}

function M.format_key_string(key)
  if not key or key == "" then return "" end
  if KEY_DISPLAY_NAMES[key] then return KEY_DISPLAY_NAMES[key] end
  if key:sub(1, 8) == "<leader>" then
    local leader = vim.g.mapleader or "\\"
    if leader == " " then leader = "<Space>"
    elseif leader == "\t" then leader = "<Tab>"
    elseif leader == "\r" then leader = "<CR>"
    end
    leader = KEY_DISPLAY_NAMES[leader] or leader
    return leader .. key:sub(9)
  end
  return key
end

function M.format_keymap(section, action)
  local key = M.get_keymap(section, action)
  if not key then return "" end
  return M.format_key_string(key)
end

function M.apply_highlight_overrides(group_names)
  local overrides = M.config.highlights
  if not overrides or vim.tbl_isempty(overrides) then return end
  for _, name in ipairs(group_names) do
    local attr = overrides[name]
    if attr then
      vim.api.nvim_set_hl(0, name, attr)
    end
  end
end

function M.log(level, msg)
  if not M.config.log_file or M.config.log_file == "" then return end
  local ts = os.date("%Y-%m-%d %H:%M:%S")
  local line = string.format("[%s] [%s] %s\n", ts, level, msg)
  local f = io.open(M.config.log_file, "a")
  if f then
    f:write(line)
    f:close()
  end
end

return M