--- Pure image metadata extraction: dimensions, file size, JPEG EXIF.
---
--- Window-free and unit-tested. Reads image files directly via io; no nvim
--- state required beyond the filesystem. Keep this module free of vim.* to
--- stay trivially testable.
local M = {}

--- Human-readable file size, e.g. 248.6 KB.
---@param bytes number|nil
---@return string
function M.human_size(bytes)
  if type(bytes) ~= "number" or bytes < 0 then return "?" end
  if bytes < 1024 then return string.format("%d B", bytes) end
  local v = bytes
  local unit = "B"
  for _, u in ipairs({ "KB", "MB", "GB", "TB" }) do
    v = v / 1024
    unit = u
    if v < 1024 then break end
  end
  return string.format("%.1f %s", v, unit)
end

--- Short format label from a content type, e.g. "image/png" -> "PNG".
---@param content_type string|nil
---@return string|nil
function M.format_label(content_type)
  if not content_type then return nil end
  local mime = content_type:match("^([^;]+)")
  if not mime then return nil end
  local fmt = mime:match("^image/(.+)$")
  if not fmt then return nil end
  local labels = {
    png = "PNG",
    jpeg = "JPEG",
    jpg = "JPEG",
    gif = "GIF",
    webp = "WEBP",
    ["svg+xml"] = "SVG",
    avif = "AVIF",
    bmp = "BMP",
    tiff = "TIFF",
    ["x-icon"] = "ICO",
    ["vnd.microsoft.icon"] = "ICO",
  }
  return labels[fmt:lower()] or fmt:upper()
end

----------------------------------------------------------------------------
-- Pragmatic big/little-endian readers.
----------------------------------------------------------------------------
local function be16(b1, b2) return b1 * 256 + b2 end
local function be32(b1, b2, b3, b4) return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4 end
local function le16(b1, b2) return b1 + b2 * 256 end
local function le24(b1, b2, b3) return b1 + b2 * 256 + b3 * 65536 end
local function le32(b1, b2, b3, b4) return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216 end

local function word(data, off, le)
  return le and le16(data:byte(off), data:byte(off + 1))
    or be16(data:byte(off), data:byte(off + 1))
end

local function dword(data, off, le)
  return le and le32(data:byte(off), data:byte(off + 1), data:byte(off + 2), data:byte(off + 3))
    or be32(data:byte(off), data:byte(off + 1), data:byte(off + 2), data:byte(off + 3))
end

----------------------------------------------------------------------------
-- Per-format dimension parsers. Each takes the file header bytes.
----------------------------------------------------------------------------
local function png_dimensions(data)
  if data:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil end
  if data:sub(13, 16) ~= "IHDR" then return nil end
  local w = be32(data:byte(17), data:byte(18), data:byte(19), data:byte(20))
  local h = be32(data:byte(21), data:byte(22), data:byte(23), data:byte(24))
  if w > 0 and h > 0 then return w, h end
  return nil
end

local function gif_dimensions(data)
  local sig = data:sub(1, 6)
  if sig ~= "GIF87a" and sig ~= "GIF89a" then return nil end
  local w = le16(data:byte(7), data:byte(8))
  local h = le16(data:byte(9), data:byte(10))
  if w > 0 and h > 0 then return w, h end
  return nil
end

local function bmp_dimensions(data)
  if data:sub(1, 2) ~= "BM" then return nil end
  local w = le32(data:byte(19), data:byte(20), data:byte(21), data:byte(22))
  local h = le32(data:byte(23), data:byte(24), data:byte(25), data:byte(26))
  if w > 0 and h > 0 then return w, math.abs(h) end
  return nil
end

local function webp_dimensions(data)
  if data:sub(1, 4) ~= "RIFF" or data:sub(9, 12) ~= "WEBP" then return nil end
  local i = 13
  local n = #data
  while i < n - 8 do
    local tag = data:sub(i, i + 3)
    local size = le32(data:byte(i + 4), data:byte(i + 5), data:byte(i + 6), data:byte(i + 7))
    local d = i + 8
    if tag == "VP8 " then
      local w = le16(data:byte(d + 3), data:byte(d + 4)) % 16384
      local h = le16(data:byte(d + 5), data:byte(d + 6)) % 16384
      if w > 0 and h > 0 then return w, h end
      return nil
    elseif tag == "VP8L" then
      local b0, b1, b2, b3 = data:byte(d), data:byte(d + 1), data:byte(d + 2), data:byte(d + 3)
      if not b0 or b0 % 2 ~= 1 then return nil end
      local wm1 = (b1 % 128) * 128 + math.floor(b0 / 2)
      local hm1 = math.floor(b1 / 128) + (b2 or 0) * 2 + (b3 or 0) % 64 * 512
      local w, h = wm1 + 1, hm1 + 1
      if w > 0 and h > 0 then return w, h end
      return nil
    elseif tag == "VP8X" then
      local w = le24(data:byte(d + 4), data:byte(d + 5), data:byte(d + 6)) + 1
      local h = le24(data:byte(d + 7), data:byte(d + 8), data:byte(d + 9)) + 1
      if w > 0 and h > 0 then return w, h end
      return nil
    end
    if size <= 0 or size > n then return nil end
    i = i + 8 + size
  end
  return nil
end

-- SOFn markers carry frame dimension info in JPEG.
local SOF_MARKERS = {
  [0xC0] = true, [0xC1] = true, [0xC2] = true, [0xC3] = true, [0xC5] = true,
  [0xC6] = true, [0xC7] = true, [0xC9] = true, [0xCA] = true, [0xCB] = true,
  [0xCD] = true, [0xCE] = true, [0xCF] = true,
}

local function jpeg_dimensions(data)
  if data:sub(1, 2) ~= "\255\216" then return nil end
  local i = 3
  local n = #data
  while i < n - 8 do
    local ff = data:byte(i)
    if ff ~= 255 then
      i = i + 1
    else
      local marker = data:byte(i + 1)
      if not marker then return nil end
      if marker == 0 or marker == 255 or marker == 1 or (marker >= 0xD0 and marker <= 0xD7) then
        i = i + 2
      elseif marker == 0xD9 or marker == 0xDA then
        return nil
      else
        local len = be16(data:byte(i + 2), data:byte(i + 3))
        if len < 2 then return nil end
        if SOF_MARKERS[marker] then
          local h = be16(data:byte(i + 5), data:byte(i + 6))
          local w = be16(data:byte(i + 7), data:byte(i + 8))
          if w > 0 and h > 0 then return w, h end
          return nil
        end
        i = i + 2 + len
      end
    end
  end
  return nil
end

-- TIFF IFD0 width/height for bare TIFF images.
local function tiff_dimensions(data)
  local le
  if data:sub(1, 2) == "II" then le = true
  elseif data:sub(1, 2) == "MM" then le = false
  else return nil end
  if word(data, 3, le) ~= 42 then return nil end
  local off = 1 + dword(data, 5, le)
  local count = word(data, off, le)
  if count > 128 then return nil end
  local w, h
  for i = 1, count do
    local e = off + 2 + (i - 1) * 12
    local tag = word(data, e, le)
    local typ = word(data, e + 2, le)
    local v
    if typ == 3 then v = word(data, e + 8, le)
    elseif typ == 4 then v = dword(data, e + 8, le) end
    if v then
      if tag == 0x100 then w = v end
      if tag == 0x101 then h = v end
    end
  end
  if w and h then return w, h end
  return nil
end

local function svg_dimensions(data)
  if not data:match("<svg") then return nil end
  local function attr_num(name)
    local v = data:match('<svg[^>]*%s+' .. name .. '%s*=%s*["\'](%d+%.?%d*)px["\']')
    if not v then
      v = data:match('<svg[^>]*%s+' .. name .. '%s*=%s*["\'](%d+%.?%d*)["\']')
    end
    return v and tonumber(v) or nil
  end
  local w, h = attr_num("width"), attr_num("height")
  if w and h then return w, h end
  local vb = data:match("viewBox%s*=%s*[\"']([^\"']+)[\"']")
  if vb then
    local nums = {}
    for v in vb:gmatch("[%-%d%.]+") do
      table.insert(nums, tonumber(v))
    end
    if nums[3] and nums[4] then
      return math.abs(nums[3]), math.abs(nums[4])
    end
  end
  return nil
end

----------------------------------------------------------------------------
-- JPEG EXIF (TIFF) — best-effort common tags from IFD0.
----------------------------------------------------------------------------
local EXIF_TAGS = {
  [0x010F] = "Make",
  [0x0110] = "Model",
  [0x0112] = "Orientation",
  [0x0131] = "Software",
  [0x0132] = "DateTime",
}

local function parse_tiff_sub(data, tiff_off)
  local le
  if data:sub(tiff_off, tiff_off + 1) == "II" then le = true
  elseif data:sub(tiff_off, tiff_off + 1) == "MM" then le = false
  else return nil end
  if word(data, tiff_off + 2, le) ~= 42 then return nil end
  local off = tiff_off + dword(data, tiff_off + 4, le)
  local count = word(data, off, le)
  if count > 64 then return nil end
  local out = {}
  for i = 1, count do
    local e = off + 2 + (i - 1) * 12
    local tag = word(data, e, le)
    local name = EXIF_TAGS[tag]
    if name then
      local typ = word(data, e + 2, le)
      local cnt = dword(data, e + 4, le)
      if typ == 2 and cnt > 0 and cnt <= 64 then -- ASCII
        local str_off
        if cnt <= 4 then
          str_off = e + 8
        else
          str_off = tiff_off + dword(data, e + 8, le)
        end
        local s = data:sub(str_off, str_off + cnt - 1)
        out[name] = (s:gsub("%z+$", ""))
      elseif typ == 3 then -- SHORT
        out[name] = word(data, e + 8, le)
      elseif typ == 4 then -- LONG
        out[name] = dword(data, e + 8, le)
      end
    end
  end
  if next(out) then return out end
  return nil
end

--- Read common EXIF tags from a JPEG file (best effort).
---@param file_path string
---@return table|nil { Make, Model, Software, Guidelines, Orientation }
function M.read_jpeg_exif(file_path)
  local f = io.open(file_path, "rb")
  if not f then return nil end
  local data = f:read(65536)
  f:close()
  if not data or data:sub(1, 2) ~= "\255\216" then return nil end
  local i = 3
  local n = #data
  local found
  while i < n - 8 do
    local ff = data:byte(i)
    if ff ~= 255 then
      i = i + 1
    else
      local marker = data:byte(i + 1)
      if not marker then break end
      if marker == 0 or marker == 255 or marker == 1 or (marker >= 0xD0 and marker <= 0xD7) then
        i = i + 2
      elseif marker == 0xD9 or marker == 0xDA then
        break
      else
        local len = be16(data:byte(i + 2), data:byte(i + 3))
        if len < 2 then break end
        if marker == 0xE1 and data:sub(i + 4, i + 9) == "Exif\0\0" then
          found = i + 10
          break
        end
        i = i + 2 + len
      end
    end
  end
  if not found then return nil end
  local ok, res = pcall(parse_tiff_sub, data, found)
  if ok and res then return res end
  return nil
end

----------------------------------------------------------------------------
-- Higher-level helpers.
----------------------------------------------------------------------------
local function file_size(file_path)
  local f = io.open(file_path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

local function read_head(file_path)
  local f = io.open(file_path, "rb")
  if not f then return nil end
  local data = f:read(65536)
  f:close()
  return data
end

--- Read pixel dimensions from any supported image header.
---@param file_path string
---@return number|nil width
---@return number|nil height
function M.read_image_dimensions(file_path)
  local data = read_head(file_path)
  if not data or #data < 8 then return nil end
  local ok, w, h = pcall(function()
    local wi, hi = png_dimensions(data)
    if wi then return wi, hi end
    wi, hi = gif_dimensions(data)
    if wi then return wi, hi end
    wi, hi = bmp_dimensions(data)
    if wi then return wi, hi end
    wi, hi = tiff_dimensions(data)
    if wi then return wi, hi end
    wi, hi = webp_dimensions(data)
    if wi then return wi, hi end
    wi, hi = svg_dimensions(data)
    if wi then return wi, hi end
    wi, hi = jpeg_dimensions(data)
    if wi then return wi, hi end
    return nil
  end)
  if not ok then return nil end
  if w and h then return w, h end
  return nil
end

--- Gather display metadata for an image file.
---@param file_path string
---@param content_type string|nil
---@return table fields width, height, size, size_human, format, exif (optional)
function M.read_image_meta(file_path, content_type)
  local meta = {}
  local size = file_size(file_path)
  if size then
    meta.size = size
    meta.size_human = M.human_size(size)
  end
  meta.format = M.format_label(content_type)
  local w, h = M.read_image_dimensions(file_path)
  if w then meta.width = w end
  if h then meta.height = h end
  if M.format_label(content_type) == "JPEG" then
    local exif = M.read_jpeg_exif(file_path)
    if exif then meta.exif = exif end
  end
  return meta
end

return M