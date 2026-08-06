local state = require("poste-http.state")
local format = require("poste-http.http.format")
local buffer = require("poste-http.http.buffer")

local M = {}

local list_buf = nil
local list_win = nil
local list_width = 46
local detail_buf = nil
local detail_win = nil
local current_index = nil
local detail_view = "body"
local _ = nil  -- detail_jq_query placeholder
local hiding = false
local list_ns = vim.api.nvim_create_namespace("poste_history_list")

local MAX_BODY_SAVE = 100 * 1024

local METHOD_HL = {
  GET = "PosteMethodGET",
  POST = "PosteMethodPOST",
  PUT = "PosteMethodPUT",
  DELETE = "PosteMethodDELETE",
  PATCH = "PosteMethodPATCH",
  HEAD = "PosteMethodHEAD",
  OPTIONS = "PosteMethodOPTIONS",
  SCRIPT = "PosteMethodScript",
}

local METHOD_WIDTH = 8
local STATUS_WIDTH = 3
-- Method (8) + status (3) + gap (1) + max elapsed "123.00 ms" (9)
-- + 2-space gap + timestamp (5).
local FIXED_WIDTH = METHOD_WIDTH + STATUS_WIDTH + 17

local function truncate_response(response)
  if not response or type(response) ~= "table" then return response end
  local r = vim.deepcopy(response)
  if r.body and type(r.body) == "string" and #r.body > MAX_BODY_SAVE then
    r.body = r.body:sub(1, MAX_BODY_SAVE) .. "\n... [truncated " .. #r.body .. " bytes]"
  end
  return r
end

function M.add_entry(name, response, assertion_results, script_logs, source_file)
  state.http_history_id_counter = state.http_history_id_counter + 1
  local entry = {
    id = state.http_history_id_counter,
    name = name,
    time = os.time(),
    source_file = source_file or "",
    response = truncate_response(response),
    assertion_results = assertion_results and vim.deepcopy(assertion_results) or nil,
    script_logs = script_logs and vim.deepcopy(script_logs) or nil,
  }
  table.insert(state.http_history, 1, entry)
  if #state.http_history > state.http_history_max then
    table.remove(state.http_history)
  end
end

function M.delete_entry(id)
  for i, entry in ipairs(state.http_history) do
    if entry.id == id then
      table.remove(state.http_history, i)
      return
    end
  end
end

local function format_timestamp(time)
  if not time then return "" end
  return os.date("%H:%M", time)
end

local function entry_method(entry)
  if not entry then return "" end
  local m = entry.method
  if (m == nil or m == "") and entry.response and entry.response.metadata then
    m = entry.response.metadata.method
  end
  if type(m) ~= "string" then return "" end
  return vim.trim(m):upper()
end

local function format_elapsed(ms)
  if type(ms) ~= "number" then return "-" end
  if ms >= 1000 then
    return string.format("%.2f s", ms / 1000)
  end
  return string.format("%.2f ms", ms)
end

local function status_hl(status)
  local sc = tonumber(status) or 0
  if sc > 0 then
    if sc < 300 then return "PosteStatus2xx"
    elseif sc < 400 then return "PosteStatus3xx"
    elseif sc < 500 then return "PosteStatus4xx"
    else return "PosteStatus5xx"
    end
  end
  return "Comment"
end

--- Build the display line for one history entry.
--- Returns the line text plus column metadata used for extmark highlighting.
local function format_list_line(entry, name_width)
  local method = entry_method(entry)
  if #method > METHOD_WIDTH then
    method = method:sub(1, METHOD_WIDTH)
  end
  if method == "" then method = "-" end

  local name = entry.name or ""
  if #name > name_width then
    name = name:sub(1, name_width - 3) .. "..."
  end

  local status = entry.response and entry.response.status
  local status_text = (tonumber(status) or 0) > 0 and tostring(status) or "-"
  local elapsed = format_elapsed(entry.response and entry.response.latency_ms)
  local ts = format_timestamp(entry.time)
  local line = string.format(
    "%-" .. METHOD_WIDTH .. "s%-" .. name_width .. "s%-" .. STATUS_WIDTH .. "s %s  %s",
    method, name, status_text, elapsed, ts
  )

  return line, {
    method = method,
    method_hl = METHOD_HL[method] or "PosteMethodOther",
    method_col = 0,
    method_end = #method,
    status = status_text,
    status_hl = status_hl(status),
    status_col = METHOD_WIDTH + name_width,
    status_end = METHOD_WIDTH + name_width + #status_text,
    elapsed_col = METHOD_WIDTH + name_width + STATUS_WIDTH + 1,
    elapsed_end = METHOD_WIDTH + name_width + STATUS_WIDTH + 1 + #elapsed,
    ts_col = METHOD_WIDTH + name_width + STATUS_WIDTH + 1 + #elapsed + 2,
  }
end

local function get_active_tabs()
  local entry = state.http_history[current_index]
  if not entry then return {} end
  local body_label = "Body [" .. state.format_keymap("http_response", "view_body") .. "]"
  if entry._jq and entry._jq.query then
    body_label = "Body [" .. state.format_keymap("http_response", "view_body") .. "] | jq: " .. entry._jq.query
  end
  local tabs = {
    { id = "body", label = body_label },
  }
  local r = entry.response
  if r and r.metadata and r.metadata.request_body and r.metadata.request_body ~= "" then
    table.insert(tabs, { id = "request", label = "Rqst [" .. state.format_keymap("http_response", "view_request") .. "]" })
  end
  table.insert(tabs, { id = "verbose", label = "Verb [" .. state.format_keymap("http_response", "view_verbose") .. "]" })
  if entry.assertion_results then
    table.insert(tabs, { id = "assertions", label = "Asserts [" .. state.format_keymap("http_response", "view_assertions") .. "]" })
  end
  if entry.script_logs and #entry.script_logs > 0 then
    table.insert(tabs, { id = "script_logs", label = "Script [" .. state.format_keymap("http_response", "view_script_logs") .. "]" })
  end
  return tabs
end

local function update_winbar()
  if not detail_win or not vim.api.nvim_win_is_valid(detail_win) then return end
  local tabs = get_active_tabs()
  local parts = {}
  for _, tab in ipairs(tabs) do
    if tab.id == detail_view then
      table.insert(parts, "%#TabLineSel# " .. tab.label .. " %*")
    else
      table.insert(parts, "%#TabLine# " .. tab.label .. " %*")
    end
  end
  vim.wo[detail_win].winbar = table.concat(parts)
end

local function render_detail()
  if not detail_buf or not vim.api.nvim_buf_is_valid(detail_buf) then return end
  local entry = state.http_history[current_index]
  if not entry then
    vim.api.nvim_set_option_value("modifiable", true, { buf = detail_buf })
    vim.api.nvim_buf_set_lines(detail_buf, 0, -1, false, { "(no history)" })
    vim.api.nvim_set_option_value("modifiable", false, { buf = detail_buf })
    vim.bo[detail_buf].filetype = "text"
    update_winbar()
    return
  end

  local r = entry.response
  local jq_lines = nil
  if detail_view == "body" and entry._jq and entry._jq.is_filtered then
    jq_lines = entry._jq.lines
  end

  local opts = {
    pending_request = nil,
    assertion_results = entry.assertion_results,
    script_logs = entry.script_logs,
    jq_lines = jq_lines,
  }
  local lines, filetype = format.format_view(detail_view, r, opts)

  lines = buffer.sanitize_lines(lines)

  vim.api.nvim_set_option_value("modifiable", true, { buf = detail_buf })
  vim.api.nvim_buf_set_lines(detail_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = detail_buf })
  vim.bo[detail_buf].filetype = filetype or "text"
  pcall(vim.api.nvim_win_set_cursor, detail_win, { 1, 0 })
  update_winbar()

  if filetype == "json" then
    if detail_win and vim.api.nvim_win_is_valid(detail_win) then
      vim.wo[detail_win].foldmethod = "indent"
      vim.wo[detail_win].foldlevel = 99
      vim.wo[detail_win].foldcolumn = "0"
    end
  end

  format.apply_view_highlights(detail_buf, detail_view, lines, r)
end

local function history_jq_filter(query)
  local entry = state.http_history[current_index]
  if not entry or not entry.response or not entry.response.body then return end

  if not entry._jq then entry._jq = {} end
  if not entry._jq.original_lines then
    entry._jq.original_lines = vim.api.nvim_buf_get_lines(detail_buf, 0, -1, false)
  end

  local result
  if vim.fn.executable("jq") == 1 then
    local ok, output = pcall(vim.fn.system, { "jq", query, "-r" }, entry.response.body)
    if ok then
      result = format.pretty_body(output, "application/json")
    else
      vim.notify("jq error: " .. (output or "unknown"), vim.log.levels.ERROR)
      return
    end
  else
    local json = require("poste-http.http.json")
    result = json._jsonpath_query(entry.response.body, query)
  end

  if not result then return end

  local lines = vim.split(result, "\n")
  entry._jq.query = query
  entry._jq.is_filtered = true
  entry._jq.lines = lines

  vim.api.nvim_set_option_value("modifiable", true, { buf = detail_buf })
  vim.api.nvim_buf_set_lines(detail_buf, 0, -1, false, buffer.sanitize_lines(lines))
  vim.api.nvim_set_option_value("modifiable", false, { buf = detail_buf })

  if detail_win and vim.api.nvim_win_is_valid(detail_win) then
    vim.wo[detail_win].foldmethod = "indent"
    vim.wo[detail_win].foldlevel = 99
    vim.wo[detail_win].foldcolumn = "0"
  end

  update_winbar()
end

local function history_jq_restore()
  local entry = state.http_history[current_index]
  if not entry or not entry._jq or not entry._jq.original_lines then return end

  vim.api.nvim_set_option_value("modifiable", true, { buf = detail_buf })
  vim.api.nvim_buf_set_lines(detail_buf, 0, -1, false, buffer.sanitize_lines(entry._jq.original_lines))
  vim.api.nvim_set_option_value("modifiable", false, { buf = detail_buf })

  entry._jq = nil

  local ft = "text"
  if entry.response and entry.response.content_type then
    ft = format.detect_filetype(entry.response.content_type)
  end
  vim.bo[detail_buf].filetype = ft
  update_winbar()
end

local function render_list()
  if not list_buf or not vim.api.nvim_buf_is_valid(list_buf) then return end
  local lines = {}
  local name_width = list_width - FIXED_WIDTH

  vim.api.nvim_buf_clear_namespace(list_buf, list_ns, 0, -1)

  if #state.http_history == 0 then
    lines = { "(no history)" }
  else
    local line_info = {}
    for _, entry in ipairs(state.http_history) do
      local line, info = format_list_line(entry, name_width)
      table.insert(lines, line)
      table.insert(line_info, info)
    end

    vim.api.nvim_set_option_value("modifiable", true, { buf = list_buf })
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = list_buf })
    vim.bo[list_buf].filetype = "poste_history_list"

    -- Colored method, elapsed, and gray timestamp via extmarks
    for i, line in ipairs(lines) do
      local info = line_info[i]
      vim.api.nvim_buf_set_extmark(list_buf, list_ns, i - 1, info.method_col, {
        end_col = info.method_end,
        hl_group = info.method_hl,
        priority = 100,
      })
      vim.api.nvim_buf_set_extmark(list_buf, list_ns, i - 1, info.status_col, {
        end_col = info.status_end,
        hl_group = info.status_hl,
        priority = 100,
      })
      vim.api.nvim_buf_set_extmark(list_buf, list_ns, i - 1, info.elapsed_col, {
        end_col = info.elapsed_end,
        hl_group = "PosteLatency",
        priority = 100,
      })
      if info.ts_col <= #line then
        vim.api.nvim_buf_set_extmark(list_buf, list_ns, i - 1, info.ts_col, {
          end_col = #line,
          hl_group = "Comment",
          priority = 100,
        })
      end
    end
  end

  if current_index == nil and #state.http_history > 0 then
    current_index = 1
  end

  if current_index and current_index <= #state.http_history then
    pcall(vim.api.nvim_win_set_cursor, list_win, { current_index, 0 })
  end
end

local function hide()
  if hiding then return end
  hiding = true
  if list_win and vim.api.nvim_win_is_valid(list_win) then
    pcall(vim.api.nvim_win_close, list_win, true)
  end
  if detail_win and vim.api.nvim_win_is_valid(detail_win) then
    pcall(vim.api.nvim_win_close, detail_win, true)
  end
  list_buf = nil
  list_win = nil
  detail_buf = nil
  detail_win = nil
  current_index = nil
  detail_view = "body"
  hiding = false
end

local function navigate_list(direction)
  if #state.http_history == 0 then return end
  if current_index == nil then
    current_index = direction > 0 and 1 or #state.http_history
  else
    current_index = current_index + direction
    if current_index < 1 then current_index = #state.http_history
    elseif current_index > #state.http_history then current_index = 1 end
  end
  pcall(vim.api.nvim_win_set_cursor, list_win, { current_index, 0 })
  render_detail()
end

local function delete_at_cursor()
  if #state.http_history == 0 or not current_index then return end
  local entry = state.http_history[current_index]
  M.delete_entry(entry.id)
  if current_index > #state.http_history then
    current_index = #state.http_history
  end
  render_list()
  render_detail()
end

local function switch_tab(tab_id)
  detail_view = tab_id
  render_detail()
end

local function cycle_tab(direction)
  local tabs = get_active_tabs()
  if #tabs == 0 then return end
  local idx = 1
  for i, tab in ipairs(tabs) do
    if tab.id == detail_view then idx = i end
  end
  local next = ((idx - 1 + direction) % #tabs) + 1
  detail_view = tabs[next].id
  render_detail()
end

local function focus_detail()
  if detail_win and vim.api.nvim_win_is_valid(detail_win) then
    vim.api.nvim_set_current_win(detail_win)
  end
end

local function wincmd_list()
  if list_win and vim.api.nvim_win_is_valid(list_win) then
    vim.api.nvim_set_current_win(list_win)
  end
end

local function wincmd_detail()
  if detail_win and vim.api.nvim_win_is_valid(detail_win) then
    vim.api.nvim_set_current_win(detail_win)
  end
end

local function setup_detail_keymaps()
  local opts = { buffer = detail_buf, noremap = true, silent = true }

  local k = state.get_keymap("http_response", "close", "q")
  if k then vim.keymap.set("n", k, hide, opts) end

  k = state.get_keymap("http_response", "view_body", "B")
  if k then vim.keymap.set("n", k, function() switch_tab("body") end, opts) end

  k = state.get_keymap("http_response", "view_request", "R")
  if k then vim.keymap.set("n", k, function() switch_tab("request") end, opts) end

  k = state.get_keymap("http_response", "view_verbose", "E")
  if k then vim.keymap.set("n", k, function() switch_tab("verbose") end, opts) end

  k = state.get_keymap("http_response", "view_assertions", "A")
  if k then vim.keymap.set("n", k, function() switch_tab("assertions") end, opts) end

  k = state.get_keymap("http_response", "view_script_logs", "S")
  if k then vim.keymap.set("n", k, function() switch_tab("script_logs") end, opts) end

  k = state.get_keymap("http_response", "next_tab", "<Tab>")
  if k then vim.keymap.set("n", k, function() cycle_tab(1) end, opts) end

  k = state.get_keymap("http_response", "prev_tab", "<S-Tab>")
  if k then vim.keymap.set("n", k, function() cycle_tab(-1) end, opts) end

  local nopts = { buffer = detail_buf, noremap = true, silent = true, nowait = true }
  vim.keymap.set("n", "<C-h>", wincmd_list, nopts)

  k = state.get_keymap("http_response", "json_filter", "<leader>j")
  if k then
    vim.keymap.set("n", k, function()
      if vim.bo[detail_buf].filetype ~= "json" then return end
      local entry = state.http_history[current_index]
      if not entry then return end
      local saved_response = state.last_response
      state.last_response = entry.response
      local json = require("poste-http.http.json")
      local paths = json.get_key_paths()
      state.last_response = saved_response
      if #paths > 0 then
        vim.ui.select(paths, {
          prompt = "jq filter",
          format_item = function(item) return item end,
        }, function(choice)
          if choice then history_jq_filter(choice) end
        end)
      else
        local hist_entry = state.http_history[current_index]
        local default_q = (hist_entry and hist_entry._jq and hist_entry._jq.query) or ""
        vim.ui.input({ prompt = "jq> ", default = default_q }, function(q)
          if q and q ~= "" then history_jq_filter(q) end
        end)
      end
    end, opts)
  end

  k = state.get_keymap("http_response", "json_restore", "<leader>jc")
  if k then
    vim.keymap.set("n", k, function()
      history_jq_restore()
    end, opts)
  end
end

local function setup_list_keymaps()
  local opts = { buffer = list_buf, noremap = true, silent = true }

  local k = state.get_keymap("http_history", "close", "q")
  if k then vim.keymap.set("n", k, hide, opts) end

  k = state.get_keymap("http_history", "delete_entry", "dd")
  if k then vim.keymap.set("n", k, delete_at_cursor, opts) end

  k = state.get_keymap("http_history", "focus_detail", "<CR>")
  if k then vim.keymap.set("n", k, focus_detail, opts) end

  vim.keymap.set("n", "j", function() navigate_list(1) end, opts)
  vim.keymap.set("n", "k", function() navigate_list(-1) end, opts)

  local nopts = { buffer = list_buf, noremap = true, silent = true, nowait = true }
  vim.keymap.set("n", "<C-l>", wincmd_detail, nopts)

  vim.api.nvim_buf_attach(list_buf, false, {
    on_detach = function()
      hide()
    end,
  })
end

function M.show()

  if list_win and vim.api.nvim_win_is_valid(list_win) then
    pcall(vim.api.nvim_set_current_win, list_win)
    return
  end

  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  local total_width = math.floor(editor_width * 0.92)
  local total_height = math.floor(editor_height * 0.88)
  local top = math.floor((editor_height - total_height) / 2)
  local left = math.floor((editor_width - total_width) / 2)
  list_width = 46
  local gap = 1

  list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[list_buf].bufhidden = "wipe"
  local ok, lw = pcall(vim.api.nvim_open_win, list_buf, true, {
    relative = "editor",
    width = list_width,
    height = total_height,
    row = top,
    col = left,
    style = "minimal",
    border = "single",
    title = " Poste HTTP History ",
    title_pos = "center",
  })
  if not ok then
    pcall(vim.api.nvim_buf_delete, list_buf, { force = true })
    list_buf = nil
    return
  end
  list_win = lw
  vim.wo[list_win].cursorline = true

  local detail_width = total_width - list_width - gap - 1
  detail_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[detail_buf].bufhidden = "wipe"
  local ok2, dw = pcall(vim.api.nvim_open_win, detail_buf, false, {
    relative = "editor",
    width = detail_width,
    height = total_height,
    row = top,
    col = left + list_width + gap,
    style = "minimal",
    border = "single",
  })
  if not ok2 then
    pcall(vim.api.nvim_win_close, list_win, true)
    pcall(vim.api.nvim_buf_delete, detail_buf, { force = true })
    detail_buf = nil
    list_buf = nil
    list_win = nil
    return
  end
  detail_win = dw

  current_index = nil
  detail_view = "body"

  setup_list_keymaps()
  setup_detail_keymaps()

  render_list()
  render_detail()

  pcall(vim.api.nvim_set_current_win, list_win)
end

M._test = {
  format_list_line = format_list_line,
  entry_method = entry_method,
  format_elapsed = format_elapsed,
  status_hl = status_hl,
}

return M
