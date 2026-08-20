--- Image preview for response buffers.
---
--- Supports image.nvim, snacks.image, Kitty protocol, and external viewer fallback.
--- Extracted from the former format.lua god module.
local M = {}

local image_preview_state = {
  image = nil,
  snacks_placement = nil,
  temp_files = {},
}
local INLINE_IMAGE_PADDING_LINES = 2

local image_url_exts = {
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  webp = "image/webp",
  svg = "image/svg+xml",
  avif = "image/avif",
  bmp = "image/bmp",
  tiff = "image/tiff",
  tif = "image/tiff",
  ico = "image/x-icon",
}

--- Image content type detection.
local image_content_types = {
  ["image/png"] = true,
  ["image/jpeg"] = true,
  ["image/gif"] = true,
  ["image/webp"] = true,
  ["image/svg+xml"] = true,
  ["image/avif"] = true,
  ["image/bmp"] = true,
  ["image/tiff"] = true,
  ["image/x-icon"] = true,
  ["image/vnd.microsoft.icon"] = true,
}

function M.is_image_content_type(content_type)
  if not content_type then return false end
  local mime = content_type:match("^([^;]+)") or content_type
  return image_content_types[mime] == true
end

--- Detect terminal support for Kitty graphics protocol.
function M.supports_kitty_protocol()
  if vim.env.KITTY_WINDOW_ID then return true end
  if (vim.env.TERM or ""):match("kitty") then return true end
  if vim.env.TERM_PROGRAM == "WezTerm" then return true end
  return false
end

--- Open an image file in the system viewer (macOS `open` / Linux `xdg-open`).
function M.open_image_external(file_path)
  if not file_path or vim.fn.filereadable(file_path) ~= 1 then
    vim.notify("Image file not found: " .. tostring(file_path), vim.log.levels.WARN, { title = "Poste" })
    return
  end
  local opener = vim.fn.has("mac") == 1 and "open" or "xdg-open"
  vim.fn.jobstart({ opener, file_path }, { detach = true })
  vim.notify(string.format("Opening image: %s", file_path), vim.log.levels.INFO, { title = "Poste" })
end

function M.close_image_preview()
  if image_preview_state.snacks_placement then
    local p = image_preview_state.snacks_placement
    image_preview_state.snacks_placement = nil
    pcall(function()
      if type(p.close) == "function" then
        p:close()
      end
    end)
  end
  if image_preview_state.image then
    local img = image_preview_state.image
    image_preview_state.image = nil
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

local function try_snacks_image(buf, file_path, cursor_line)
  local ok, snacks = pcall(require, "snacks")
  if not ok or type(snacks) ~= "table" then
    return false
  end
  if type(snacks.image) ~= "table" or type(snacks.image.supports) ~= "function" then
    return false
  end
  if not snacks.image.supports(file_path) then
    return false
  end
  local win = vim.fn.bufwinid(buf)
  if win < 0 then return false end

  local pos_row = (cursor_line or 1)

  M.close_image_preview()

  local placement_ok, placement = pcall(snacks.image.placement.new, buf, file_path, {
    pos = { pos_row, 0 },
    inline = true,
    conceal = false,
  })
  if not placement_ok then
    vim.notify("snacks.image preview failed: " .. tostring(placement), vim.log.levels.WARN, { title = "Poste" })
    return false
  end
  if not placement then
    return false
  end

  image_preview_state.snacks_placement = placement
  vim.schedule(function()
    vim.defer_fn(function()
      if placement.img and placement.img:failed() then
        vim.notify("snacks.image async load failed for: " .. file_path, vim.log.levels.WARN, { title = "Poste" })
      end
    end, 2000)
  end)
  return true
end

local function try_image_nvim(buf, file_path, cursor_line)
  local ok, image = pcall(require, "image")
  if not ok or type(image) ~= "table" or type(image.from_file) ~= "function" then
    return false
  end

  local win = vim.fn.bufwinid(buf)
  if win < 0 then
    return false
  end

  local restore_cursor = nil
  if cursor_line and vim.api.nvim_win_is_valid(win) then
    restore_cursor = vim.api.nvim_win_get_cursor(win)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local target_line = math.max(1, math.min(cursor_line, math.max(1, line_count)))
    pcall(vim.api.nvim_win_set_cursor, win, { target_line, 0 })
  end

  local opts = {
    buffer = buf,
    window = win,
    with_virtual_padding = true,
    inline = true,
    id = "poste_image_preview",
    overlap = 0,
    x = 0,
    y = cursor_line and math.max(cursor_line - 1, 0) or 0,
  }

  local image_obj
  local from_ok, from_err = pcall(function()
    image_obj = image.from_file(file_path, opts)
  end)
  if not from_ok or not image_obj then
    if restore_cursor then
      pcall(vim.api.nvim_win_set_cursor, win, restore_cursor)
    end
    return false, from_err
  end

  M.close_image_preview()
  image_preview_state.image = image_obj

  if type(image_obj) == "table" then
    if type(image_obj.render) == "function" then
      local render_ok = pcall(function() image_obj:render() end)
      if render_ok then
        if restore_cursor then
          pcall(vim.api.nvim_win_set_cursor, win, restore_cursor)
        end
        return true
      end
    end
    if type(image_obj.show) == "function" then
      local show_ok = pcall(function() image_obj:show() end)
      if show_ok then
        if restore_cursor then
          pcall(vim.api.nvim_win_set_cursor, win, restore_cursor)
        end
        return true
      end
    end
  end

  image_preview_state.image = nil
  if type(image.render) == "function" then
    local render_ok = pcall(function()
      image.render(image_obj)
    end)
    if render_ok then
      if restore_cursor then
        pcall(vim.api.nvim_win_set_cursor, win, restore_cursor)
      end
      return true
    end
  end

  if restore_cursor then
    pcall(vim.api.nvim_win_set_cursor, win, restore_cursor)
  end

  return false
end

function M.has_image_nvim()
  local ok, image = pcall(require, "image")
  return ok and type(image) == "table" and type(image.from_file) == "function"
end

function M.has_snacks_image()
  local ok, snacks = pcall(require, "snacks")
  if not ok or type(snacks) ~= "table" then return false end
  if type(snacks.image) ~= "table" or type(snacks.image.supports) ~= "function" then return false end
  return snacks.image.supports_terminal()
end

function M.inline_image_padding_lines()
  return INLINE_IMAGE_PADDING_LINES
end

--- Render image inline in the current response buffer/window.
function M.render_image_preview(buf, file_path, content_type, cursor_line)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return false end
  if not file_path or vim.fn.filereadable(file_path) ~= 1 then return false end
  if not M.is_image_content_type(content_type) then return false end

  -- snacks supports SVG via imagemagick conversion, try it first
  if try_snacks_image(buf, file_path, cursor_line) then
    return true
  end

  -- image.nvim doesn't support SVG, skip those
  if content_type and content_type:match("^image/svg%+xml") then return false end
  if try_image_nvim(buf, file_path, cursor_line) then
    return true
  end
  return false
end

function M.render_response_image(buf, r, cursor_line)
  if not r or not r.metadata then return false end
  local file_path = r.metadata.file_path
  local content_type = r.metadata.file_content_type or r.content_type
  return M.render_image_preview(buf, file_path, content_type, cursor_line)
end

--- Get the URL under the cursor position.
--- Returns the URL string or nil.
function M.get_url_under_cursor()
  local line = vim.fn.getline(".")
  local col = vim.fn.col(".") - 1
  local url_pattern = "https?://[^\"'%s>%)%]]+"
  local urls = {}
  for u in line:gmatch(url_pattern) do
    table.insert(urls, u)
  end
  for _, u in ipairs(urls) do
    local start_idx, end_idx = line:find(u, 1, true)
    if start_idx and col >= start_idx - 1 and col < end_idx then
      return u
    end
  end
  local expanded = vim.fn.expand("<cfile>")
  if expanded then
    expanded = expanded:match("^https?://[^\"'%s>%,%)%]]+")
  end
  if expanded then
    return expanded
  end
  return nil
end

--- Check if a URL looks like an image URL based on its extension.
---@param url string
---@return string|nil content_type
function M.guess_image_content_type(url)
  local ext = (url:match(".*%.([^%.%?/]+)") or ""):lower()
  return image_url_exts[ext]
end

--- Download an image URL to a temp file.
--- Returns the file path and content type, or nil on failure.
function M.download_image_url(url)
  local ct = M.guess_image_content_type(url) or "image/png"
  local ext = ({
    ["image/png"] = ".png",
    ["image/jpeg"] = ".jpg",
    ["image/gif"] = ".gif",
    ["image/webp"] = ".webp",
    ["image/svg+xml"] = ".svg",
    ["image/avif"] = ".avif",
    ["image/bmp"] = ".bmp",
    ["image/tiff"] = ".tiff",
    ["image/x-icon"] = ".ico",
  })[ct] or ".bin"

  local state = require("poste-http.state")
  local cfg = state.config or {}
  local cache_dir = cfg.response_cache_dir or vim.fn.stdpath("cache") .. "/poste_res"
  vim.fn.mkdir(cache_dir, "p")
  local ms = math.floor(((vim.uv or vim.loop).hrtime() / 1e6) % 1000)
  local tmp = cache_dir .. "/url_" .. os.date("%Y%m%d_%H%M%S") .. string.format("_%03d", ms) .. ext
  table.insert(image_preview_state.temp_files, tmp)
  local cmd = { "curl", "-s", "-S", "-L", "--max-time", "15", "-o", tmp, url }
  vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    table.remove(image_preview_state.temp_files)
    pcall(os.remove, tmp)
    return nil, ct
  end
  return tmp, ct
end

--- Download and preview an image URL.
--- Shows a notification while downloading, then renders inline.
---@param buf number
---@param url string
---@param cursor_line number
---@return boolean
function M.preview_image_url(buf, url, cursor_line)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return false end
  if not url or not url:match("^https?://") then return false end
  local ct = M.guess_image_content_type(url)
  if not ct then return false end

  M.cleanup_url_preview()
  vim.notify("Downloading image...", vim.log.levels.INFO, { title = "Poste" })
  local file_path, content_type = M.download_image_url(url)
  if not file_path then
    vim.notify("Failed to download image from URL", vim.log.levels.WARN, { title = "Poste" })
    return false
  end
  return M.render_image_preview(buf, file_path, content_type or ct, cursor_line)
end

--- Clean up temp files created for URL preview.
function M.cleanup_url_preview()
  for _, f in ipairs(image_preview_state.temp_files) do
    pcall(os.remove, f)
  end
  image_preview_state.temp_files = {}
end

return M