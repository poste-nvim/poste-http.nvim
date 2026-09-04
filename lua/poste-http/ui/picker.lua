--- Minimal floating list picker with incremental search.
---
--- Extracted from select.lua (2026-08-30 review U8): the fallback picker used
--- when snacks.picker is unavailable. Items are the normalized
--- `{ key, name, description }` tables produced by select.lua. Every close
--- path — <CR>, <Esc>, q, or closing the window by any external means —
--- resolves on_select exactly once with the chosen key (nil on cancel).
---
--- The float is created through ui/float with close_keys = {}: this module
--- owns the keymaps (normal + insert modes) and the search flow.

local M = {}
local float = require("poste-http.ui.float")

--- Open the picker and call on_select once with the chosen key or nil.
--- @param items table[]  { key, name, description } entries
--- @param prompt string|nil  window title
--- @param on_select function
function M.open(items, prompt, on_select)
  local list_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = list_buf })
  vim.api.nvim_set_option_value("filetype", "PosteSelect", { buf = list_buf })
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(24, #items + 2)

  local selected_idx = 1
  local search_text = ""
  local filtered = vim.deepcopy(items)
  local resolved = false
  local win

  local function resolve(result)
    if resolved then return end
    resolved = true
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    vim.schedule(function() pcall(on_select, result) end)
  end

  local function render()
    local display = {}
    for _, item in ipairs(filtered) do
      local label = item.name
      if item.description ~= "" then
        label = label .. "  (" .. item.description .. ")"
      end
      table.insert(display, label)
    end
    local lines = { "\239\134\133 " .. search_text }
    for idx, label in ipairs(display) do
      local prefix = (idx == selected_idx) and "▶ " or "  "
      table.insert(lines, prefix .. label)
    end
    while #lines < height do table.insert(lines, "") end
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(list_buf, -1, 0, -1)
    if selected_idx > 0 and selected_idx <= #filtered then
      vim.api.nvim_buf_add_highlight(list_buf, -1, "Visual", selected_idx, 0, -1)
    end
  end

  local function filter_items()
    filtered = {}
    if search_text == "" then
      filtered = vim.deepcopy(items)
      selected_idx = 1
    else
      local lower = search_text:lower()
      for _, item in ipairs(items) do
        if item.name:lower():find(lower, 1, true)
          or item.description:lower():find(lower, 1, true) then
          table.insert(filtered, item)
        end
      end
      selected_idx = 1
    end
    render()
  end

  local function move(delta)
    if #filtered == 0 then return end
    selected_idx = math.max(1, math.min(selected_idx + delta, #filtered))
    render()
  end

  local function choose()
    resolve(#filtered > 0 and filtered[selected_idx].key or nil)
  end

  local function cancel()
    resolve(nil)
  end

  local function start_insert()
    vim.cmd("startinsert!")
  end

  local _, win2 = float.open({
    buf = list_buf,
    width = width, height = height,
    border = "rounded",
    title = prompt,
    close_keys = {},
    -- external closes (":q", "<C-w>c", ...) resolve as cancel
    on_close = function() resolve(nil) end,
  })
  if not win2 then
    pcall(vim.api.nvim_buf_delete, list_buf, { force = true })
    vim.schedule(function() pcall(on_select, nil) end)
    return
  end
  win = win2

  local function map(mode, key, action)
    vim.keymap.set(mode, key, action, { buffer = list_buf, nowait = true })
  end
  map("n", "j", function() move(1) end)
  map("n", "k", function() move(-1) end)
  map("n", "<Down>", function() move(1) end)
  map("n", "<Up>", function() move(-1) end)
  map("n", "<CR>", choose)
  map("n", "<Esc>", cancel)
  map("n", "q", cancel)
  map("n", "i", start_insert)
  map("n", "a", start_insert)
  map("i", "<CR>", function() vim.cmd("stopinsert"); choose() end)
  map("i", "<Esc>", function() vim.cmd("stopinsert"); cancel() end)
  map("i", "<Down>", function() move(1) end)
  map("i", "<Up>", function() move(-1) end)

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = list_buf,
    callback = function()
      if resolved then return end
      local lines = vim.api.nvim_buf_get_lines(list_buf, 0, 1, false)
      local new_search = (lines[1] or ""):match("^\239\134\133 (.*)$") or ""
      if new_search ~= search_text then
        search_text = new_search
        filter_items()
      end
    end,
  })

  render()
  start_insert()
end

return M
