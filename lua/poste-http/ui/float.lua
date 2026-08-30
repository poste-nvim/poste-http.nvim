--- Centered floating-window primitive.
---
--- Consolidates the scratch-buffer + nvim_open_win + close-keymap blocks that
--- used to be hand-rolled across help.lua, commands.lua, variable_inspector.lua,
--- outline.lua, select.lua, history.lua and format/image.lua — with guards
--- those copies applied unevenly (title-less fallback, failure cleanup,
--- WinClosed on_close). Geometry (center) is pure and unit-tested; open()
--- needs a real Neovim.
---
--- Callers with bespoke needs pass a pre-made `buf` and/or `close_keys = {}`
--- and keep full control (select.lua's picker, history's dual window).

local M = {}

--- Centered editor-relative row/col for a width×height float; clamps to 0
--- when the window is larger than the editor.
--- @param width number
--- @param height number
--- @return number row, number col
function M.center(width, height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  if row < 0 then row = 0 end
  if col < 0 then col = 0 end
  return row, col
end

--- Open a centered float.
--- opts:
---   buf         existing buffer (default: a new scratch buffer)
---   lines       initial lines for a newly created scratch buffer
---   filetype    filetype for a newly created scratch buffer
---   modifiable  keep the scratch buffer modifiable (default: locked)
---   width/height required window size
---   row/col     override the centered position
---   border      border style (default "rounded")
---   title       window title; opens titleless when the build rejects titles
---   title_pos   "center" (default) | "left" | "right"
---   focus       focus the window (default true)
---   cursorline  enable cursorline in the window
---   close_keys  normal-mode keys mapped to close (default { "q", "<Esc>" };
---               pass {} to skip — e.g. self-managed pickers)
---   on_close    fires exactly once when the window closes (any path)
---   win_opts    extra nvim_open_win options (merged over the defaults)
---
--- @return number|nil buf  scratch buffer (nil when the window failed to open;
---         a freshly created buffer is cleaned up)
--- @return number|nil win
function M.open(opts)
  opts = opts or {}
  local buf = opts.buf
  local created = false
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    created = true
    if opts.lines then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)
    end
    if opts.modifiable ~= true then
      vim.bo[buf].modifiable = false
    end
    if opts.filetype then
      vim.bo[buf].filetype = opts.filetype
    end
  end

  local row, col = M.center(opts.width, opts.height)
  if opts.row ~= nil then row = opts.row end
  if opts.col ~= nil then col = opts.col end

  local win_opts = {
    relative = "editor",
    width = opts.width,
    height = opts.height,
    row = row,
    col = col,
    style = "minimal",
    border = opts.border or "rounded",
  }
  if opts.title then
    win_opts.title = opts.title
    win_opts.title_pos = opts.title_pos or "center"
  end
  if opts.win_opts then
    for k, v in pairs(opts.win_opts) do win_opts[k] = v end
  end

  local ok, win = pcall(vim.api.nvim_open_win, buf, opts.focus ~= false, win_opts)
  if not ok and opts.title then
    win_opts.title = nil
    win_opts.title_pos = nil
    ok, win = pcall(vim.api.nvim_open_win, buf, opts.focus ~= false, win_opts)
  end
  if not ok then
    if created then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    return nil, nil
  end

  if opts.cursorline then
    vim.wo[win].cursorline = true
  end

  local closed = false
  local function close()
    if closed then return end
    closed = true
    pcall(vim.api.nvim_win_close, win, true)
    if opts.on_close then opts.on_close() end
  end

  local close_keys = opts.close_keys
  if close_keys == nil then close_keys = { "q", "<Esc>" } end
  for _, key in ipairs(close_keys) do
    vim.keymap.set("n", key, close, { buffer = buf, noremap = true, silent = true, nowait = true })
  end
  if opts.on_close then
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        if closed then return end
        closed = true
        opts.on_close()
      end,
    })
  end

  return buf, win
end

return M
