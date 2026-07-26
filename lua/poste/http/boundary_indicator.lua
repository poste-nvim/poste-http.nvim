local M = {}

local _prev_buf = nil
local _disabled = false
local _sign_ids = {}  -- { line_0 = sign_id, ... }
local _sign_group = "poste_boundary_sg"
local _sign_gen = 0

local function define_signs()
  pcall(vim.fn.sign_define, "PosteBoundaryTop",    { text = "┌", texthl = "PosteHttpBoundaryBorder" })
  pcall(vim.fn.sign_define, "PosteBoundaryMid",    { text = "│ ", texthl = "PosteHttpBoundaryBorder" })
  pcall(vim.fn.sign_define, "PosteBoundaryBot",    { text = "└", texthl = "PosteHttpBoundaryBorder" })
  pcall(vim.fn.sign_define, "PosteBoundarySingle", { text = "─", texthl = "PosteHttpBoundaryBorder" })
end
define_signs()

local function clear_all(buf)
  _sign_gen = _sign_gen + 1
  for _, sid in pairs(_sign_ids) do
    pcall(vim.fn.sign_unplace, _sign_group, { id = sid })
  end
  _sign_ids = {}
  _prev_buf = nil
end

local function apply_range(buf, start, stop)
  clear_all(_prev_buf)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  clear_all(buf)
  _sign_ids = {}
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count == 0 then return end
  start = math.max(0, math.min(start, line_count - 1))
  stop  = math.max(0, math.min(stop,  line_count - 1))
  for line = start, stop do
    local sign_name
    if start == stop then
      sign_name = "PosteBoundarySingle"
    elseif line == start then
      sign_name = "PosteBoundaryTop"
    elseif line == stop then
      sign_name = "PosteBoundaryBot"
    else
      sign_name = "PosteBoundaryMid"
    end
    local sid = vim.fn.sign_place(0, _sign_group, sign_name, buf, { lnum = line + 1 })
    if sid and sid > 0 then
      _sign_ids[line] = sid
    end
  end
  _prev_buf = buf
end

local function find_block(buf, cursor)
  local cache = require("poste.http.cache")
  local block = cache.get_semantic_block_at_line(buf, cursor)
  if block and block.line and block.end_line then
    return block.line, block.end_line
  end
  block = cache.get_block_at_line(buf, cursor)
  if not block then return nil, nil end
  local stop_line = block.last_content_line or block.end_line
  return block.start_line, stop_line
end

local function update(buf, cursor)
  if _disabled then return end
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local total = vim.api.nvim_buf_line_count(buf)
  if total == 0 then return end
  local start, stop = find_block(buf, cursor)
  if not start then clear_all(_prev_buf); return end
  apply_range(buf, start - 1, stop - 1)
end

function M.refresh(buf, cursor)
  if _disabled then return end
  update(buf, cursor)
end

function M.clear(buf)
  clear_all(buf)
end

function M.toggle()
  _disabled = not _disabled
  if _disabled then
    M.clear(vim.api.nvim_get_current_buf())
    vim.notify("HTTP boundary highlight: OFF", vim.log.levels.INFO, { title = "Poste" })
  else
    M.refresh(vim.api.nvim_get_current_buf(), vim.fn.line("."))
    vim.notify("HTTP boundary highlight: ON", vim.log.levels.INFO, { title = "Poste" })
  end
end

vim.api.nvim_create_user_command("PosteHttpBoundary", function()
  require("poste.http.boundary_indicator").toggle()
end, { desc = "Toggle HTTP request block boundary highlight" })

return M