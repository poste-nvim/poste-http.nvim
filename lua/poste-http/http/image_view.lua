--- Image preview windows and the one-live-preview lifecycle.
---
--- Split out of `http/format/image.lua` (guardrails §2): format/ turns
--- response bodies into line data only — no windows. The float preview and
--- the shared preview-object registry live here, next to
--- `http/image_cache.lua` (download/cache) and `format/image.lua` (inline
--- response-buffer adapters, which register their preview objects through
--- `register_preview` so `close_preview` can reap them).

local M = {}

local float = require("poste-http.ui.float")
local render = require("poste-http.ui.render")
local image_cache = require("poste-http.http.image_cache")
local image_meta = require("poste-http.http.format.image_meta")

-- One live preview at a time, float or inline. float_win/float_buf are this
-- module's window; snacks_placement/image hold third-party preview objects
-- (ours from the float adapters, or ones registered by format/image.lua's
-- inline adapters) that close_preview() reaps.
local preview_state = {
  image = nil,
  snacks_placement = nil,
  float_win = nil,
  float_buf = nil,
}

local meta_ns = nil

local function meta_namespace()
  if not meta_ns then
    meta_ns = vim.api.nvim_create_namespace("poste_image_meta")
  end
  return meta_ns
end

--- Close the live image preview: the float window plus any registered
--- snacks/image.nvim preview object. Safe to call with nothing live.
function M.close_preview()
  -- Close floating image preview window
  if preview_state.float_win then
    local win = preview_state.float_win
    preview_state.float_win = nil
    preview_state.float_buf = nil
    pcall(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)
  end
  if preview_state.snacks_placement then
    local p = preview_state.snacks_placement
    preview_state.snacks_placement = nil
    pcall(function()
      if type(p.close) == "function" then
        p:close()
      end
    end)
  end
  if preview_state.image then
    local img = preview_state.image
    preview_state.image = nil
    pcall(function()
      if type(img) == "table" then
        if type(img.clear) == "function" then
          img:clear()
        elseif type(img.delete) == "function" then
          img:delete()
        end
      end
    end)
  end
end

--- Register an inline (response-buffer) preview object created by
--- format/image.lua's adapters, so close_preview() reaps it when the next
--- preview opens or the user closes the current one.
--- @param kind string "snacks_placement" | "image"
--- @param obj table|nil  the preview object; nil unregisters that kind
function M.register_preview(kind, obj)
  if kind == "snacks_placement" then
    preview_state.snacks_placement = obj
  elseif kind == "image" then
    preview_state.image = obj
  end
end

--- Try to render image in floating window using snacks.image.
--- @param start_row number 1-based row to anchor the header bottom; snacks
--- requires pos[1] <= buf line count, so the header must leave a real line there.
local function try_snacks_image_float(buf, win, file_path, start_row, img_width, img_height)
  local ok, snacks = pcall(require, "snacks")
  if not ok or type(snacks) ~= "table" then return false end
  if type(snacks.image) ~= "table" or type(snacks.image.supports) ~= "function" then
    return false
  end
  if not snacks.image.supports(file_path) then return false end

  local placement_ok, placement = pcall(snacks.image.placement.new, buf, file_path, {
    inline = true,
    conceal = false,
    pos = { start_row or 1, 0 },
    width = img_width,
    height = img_height,
  })
  if not placement_ok or not placement then
    return false
  end

  preview_state.snacks_placement = placement
  return true
end

--- Try to render image in floating window using image.nvim.
local function try_image_nvim_float(buf, win, file_path, start_row, img_width, img_height)
  local ok, image = pcall(require, "image")
  if not ok or type(image) ~= "table" or type(image.from_file) ~= "function" then
    return false
  end

  local image_obj
  local from_ok = pcall(function()
    image_obj = image.from_file(file_path, {
      buffer = buf,
      window = win,
      with_virtual_padding = true,
      inline = true,
      id = "poste_image_float_preview",
      y = start_row or 0,
      width = img_width,
      height = img_height,
    })
  end)
  if not from_ok or not image_obj then return false end

  preview_state.image = image_obj

  if type(image_obj.render) == "function" then
    local render_ok = pcall(function() image_obj:render() end)
    if render_ok then return true end
  end
  if type(image_obj.show) == "function" then
    local show_ok = pcall(function() image_obj:show() end)
    if show_ok then return true end
  end

  preview_state.image = nil
  return false
end

--- Build the meta lines rendered below a floating image preview (gray text).
local function build_meta_lines(meta)
  local summary = {}
  if meta.format then table.insert(summary, meta.format) end
  if meta.width and meta.height then
    table.insert(summary, string.format("%d*%d", meta.width, meta.height))
  end
  if meta.size_human then table.insert(summary, meta.size_human) end

  local lines = { " " }
  table.insert(lines,  " " .. table.concat(summary, "  ") )
  if meta.exif then
    if meta.exif.Make then
      local model = meta.exif.Model and (" " .. meta.exif.Model) or ""
      table.insert(lines, " Camera: " .. meta.exif.Make .. model)
    end
    if meta.exif.DateTime then
      table.insert(lines, " Taken:  " .. meta.exif.DateTime)
    end
    if meta.exif.Orientation and meta.exif.Orientation ~= 1 then
      local labels = { [3] = "Rotate 180", [6] = "Rotate 90 CW", [8] = "Rotate 270 CW" }
      table.insert(lines, " Orient: " .. (labels[meta.exif.Orientation] or tostring(meta.exif.Orientation)))
    end
  end
  return lines
end

--- Pick a float window size that hugs the image while fitting on screen.
--- The image sits at the top; `meta_rows` extra rows are reserved below it.
--- Also returns the image render area (cells) for the backend renderers.
local function calc_float_size(meta, meta_rows)
  meta_rows = meta_rows or 0
  local max_w = math.max(20, vim.o.columns - 2)
  local max_h = math.max(4, vim.o.lines - 2)
  local img_cols, img_rows = 80, math.max(1, max_h - meta_rows - 2)
  if meta.width and meta.height and meta.width > 0 and meta.height > 0 then
    local cols = math.max(1, meta.width / 9)
    local rows = math.max(1, meta.height / 18)
    local avail_h = math.max(1, max_h - meta_rows - 2)
    local scale = math.min(max_w / cols, avail_h / rows, 1)
    img_cols = math.max(1, math.floor(cols * scale))
    img_rows = math.max(1, math.floor(rows * scale))
  end
  local width = math.max(20, math.min(img_cols, max_w))
  local height = math.min(1 + img_rows + meta_rows, max_h)
  return width, height, img_cols, img_rows
end

--- Render an image file in a floating window.
--- The image fills the top; meta info (format, dimensions, size, JPEG EXIF)
--- is shown below it in gray. Tries snacks.image first, then image.nvim, then
--- fallback to file info. Closable with <Esc> or q.
---@param file_path string
---@param content_type string
---@return boolean
function M.render_image_float(file_path, content_type)
  if not file_path or vim.fn.filereadable(file_path) ~= 1 then return false end
  if not image_cache.is_image_content_type(content_type) then return false end

  local meta = image_meta.read_image_meta(file_path, content_type)
  local meta_lines = build_meta_lines(meta)
  local width, height, img_cols, img_rows = calc_float_size(meta, #meta_lines)

  -- Floating window: row 0 is a blank anchor below which the image renders;
  -- meta text follows. modifiable stays open for the external-viewer fallback
  -- that appends file info below (render.set_lines locks it again).
  -- q/<Esc> close via on_close → close_preview (also covers :q/<C-w>c
  -- through the WinClosed autocmd inside ui/float).
  local lines = { "" }
  for _, l in ipairs(meta_lines) do
    table.insert(lines, l)
  end

  local title_parts = { "Preview" }
  if meta.format then table.insert(title_parts, meta.format) end
  if meta.width and meta.height then
    table.insert(title_parts, string.format("%d*%d", meta.width, meta.height))
  end
  if meta.size_human then table.insert(title_parts, meta.size_human) end

  local buf, win = float.open({
    lines = lines,
    width = width,
    height = height,
    title = " " .. table.concat(title_parts, "  ") .. " ",
    modifiable = true,
    on_close = function() M.close_preview() end,
  })
  if not win then return false end

  preview_state.float_win = win
  preview_state.float_buf = buf

  -- Gray meta lines below the image (PosteImageMeta is defined with the other
  -- highlight groups in http/highlights.lua).
  for i = 1, #meta_lines do
    vim.api.nvim_buf_set_extmark(buf, meta_namespace(), i, 0, {
      hl_group = "PosteImageMeta",
      end_row = i + 1,
      end_col = 0,
    })
  end

  -- Try snacks.image first (image anchored on the blank row 0)
  if try_snacks_image_float(buf, win, file_path, 1, img_cols, img_rows) then
    return true
  end

  -- Try image.nvim (draw below the meta lines so it never covers them)
  if try_image_nvim_float(buf, win, file_path, #lines, img_cols, img_rows) then
    return true
  end

  -- Fallback: show file info in the buffer
  vim.list_extend(lines, {
    "File: " .. file_path,
    "Type: " .. (content_type or "unknown"),
  })
  render.set_lines(buf, lines)
  return true
end

return M
