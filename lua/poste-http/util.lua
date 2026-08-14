local M = {}
local hover_tracker = nil

--- Recursively convert decoded JSON to pure Lua tables, avoiding userdata/cdata.
--- `vim.json.decode` may return `vim.NIL` or cdata wrappers depending on
--- the Neovim build; this normalizes to plain `nil` and plain Lua tables.
--- @param v any
--- @return any
function M.json_to_table(v)
  if v == vim.NIL then return nil end
  local t = type(v)
  if t == "table" then
    local r = {}
    for k, v2 in pairs(v) do
      r[k] = M.json_to_table(v2)
    end
    return r
  end
  return v
end

function M.clean_nil(t)
  if not t or type(t) ~= "table" then return t end
  for k, v in pairs(t) do
    if v == vim.NIL then
      t[k] = nil
    elseif type(v) == "table" then
      M.clean_nil(v)
    end
  end
  return t
end

function M.find_file_upwards(filename, start_dir)
  if not filename or filename == "" then return nil end
  local dir = start_dir or vim.fn.getcwd()
  while true do
    local candidate = dir .. "/" .. filename
    if vim.fn.filereadable(candidate) == 1 then
      return candidate
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      return nil
    end
    dir = parent
  end
end

function M.ensure_job_data(data)
  if not data or type(data) ~= "table" then return {} end
  while #data > 0 and data[#data] == "" do
    data[#data] = nil
  end
  return data
end

--- Current wall-clock timestamp with milliseconds: "YYYY-MM-DD HH:MM:SS.mmm".
--- Falls back to second precision when gettimeofday is unavailable.
function M.timestamp()
  local uv = vim.uv or vim.loop
  if uv and uv.gettimeofday then
    local sec, usec = uv.gettimeofday()
    if sec then
      local ms = math.floor((usec or 0) / 1000)
      return os.date("%Y-%m-%d %H:%M:%S", sec) .. string.format(".%03d", ms)
    end
  end
  return os.date("%Y-%m-%d %H:%M:%S")
end

--- Redact query-string parameter values from a URL for safe logging.
--- Preserves the path; masks every `key=` value as `key=[REDACTED]`.
--- Leaves URLs without a query unchanged.
function M.redact_url_query(url)
  if not url or url == "" then return url end
  local base, query = url:match("^([^?]+)%?(.*)$")
  if not base then return url end
  local parts = {}
  for kv in query:gmatch("[^&]+") do
    local k = kv:match("^([^=]*)=")
    if k then
      table.insert(parts, k .. "=[REDACTED]")
    else
      table.insert(parts, kv)
    end
  end
  return base .. "?" .. table.concat(parts, "&")
end

--- Open a markdown doc preview in a floating window.
--- Returns float_buf, win, reused (boolean — true if an existing tracked window was re-focused).
--- opts:
---   title     - window title (optional)
---   track_key - unique key for hover re-focus (optional)
---   on_close  - callback invoked when the window is closed via q/<Esc>
function M.open_doc_preview(lines, opts)
  opts = opts or {}

  if opts.track_key then
    if hover_tracker and vim.api.nvim_win_is_valid(hover_tracker.win) then
      if hover_tracker.key == opts.track_key then
        vim.api.nvim_set_current_win(hover_tracker.win)
        return hover_tracker.buf, hover_tracker.win, true
      end
      pcall(vim.api.nvim_win_close, hover_tracker.win, true)
      hover_tracker = nil
    end
  end

  local float_buf, win
  local ok
  ok, float_buf, win = pcall(vim.lsp.util.open_floating_preview, lines, "markdown", {
    border = "single",
    title = opts.title,
    title_pos = "left",
    focusable = false,
  })
  if not ok or not float_buf then
    ok, float_buf, win = pcall(vim.lsp.util.open_floating_preview, lines, "markdown", {
      border = "single",
      focusable = false,
    })
    if not ok or not float_buf then
      return nil, nil, false
    end
  end

  if opts.track_key then
    hover_tracker = { win = win, buf = float_buf, key = opts.track_key }
    local hover_group = vim.api.nvim_create_augroup("PosteHoverWin_" .. win, { clear = true })
    vim.api.nvim_create_autocmd("WinClosed", {
      group = hover_group,
      pattern = tostring(win),
      callback = function() hover_tracker = nil end,
    })
  end

  local function close()
    pcall(vim.api.nvim_win_close, win, true)
    if opts.track_key then hover_tracker = nil end
    if opts.on_close then opts.on_close() end
  end

  vim.keymap.set("n", "q", close, { buffer = float_buf, noremap = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = float_buf, noremap = true, silent = true })

  return float_buf, win, false
end

return M