--- Scratch-buffer line writer.
---
--- "Make modifiable → write lines → lock again" used to be hand-rolled in
--- history.lua / view.lua / buffer.lua / json.lua / outline.lua; the
--- http/history-empty-list bug (empty branch skipping the write) came from
--- exactly that repetition.

local M = {}

--- Replace the full contents of buf with lines, toggling modifiable around
--- the write so locked scratch buffers stay writable from code only.
--- @param buf number
--- @param lines string[]
--- @param opts table|nil  { filetype = string } sets the buffer filetype
function M.set_lines(buf, lines, opts)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  opts = opts or {}
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  if opts.filetype then
    vim.bo[buf].filetype = opts.filetype
  end
end

return M
