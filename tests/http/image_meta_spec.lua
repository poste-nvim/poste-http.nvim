local image_meta = require("poste-http.http.format.image_meta")

local tmp_files = {}

local function le16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function le32(n)
  return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256,
    math.floor(n / 16777216) % 256)
end
local function be16(n) return string.char(math.floor(n / 256) % 256, n % 256) end
local function be32(n) return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
  math.floor(n / 256) % 256, n % 256) end

--- Write binary data to a temp file and return its path.
local function tmpfile(data)
  local t = vim.fn.tempname()
  local f = assert(io.open(t, "wb"))
  f:write(data)
  f:close()
  table.insert(tmp_files, t)
  return t
end

describe("image_meta", function()
  after_each(function()
    for _, p in ipairs(tmp_files) do
      pcall(os.remove, p)
    end
    tmp_files = {}
  end)

  describe("human_size", function()
    it("formats bytes", function()
      assert.equals("0 B", image_meta.human_size(0))
      assert.equals("512 B", image_meta.human_size(512))
    end)

    it("formats KB/MB/GB", function()
      assert.equals("1.0 KB", image_meta.human_size(1024))
      assert.equals("1.5 KB", image_meta.human_size(1536))
      assert.equals("1.5 MB", image_meta.human_size(1572864))
      assert.equals("1.5 GB", image_meta.human_size(1610612736))
    end)

    it("handles nil", function()
      assert.equals("?", image_meta.human_size(nil))
    end)
  end)

  describe("format_label", function()
    it("labels common image content types", function()
      assert.equals("PNG", image_meta.format_label("image/png"))
      assert.equals("JPEG", image_meta.format_label("image/jpeg; charset=binary"))
      assert.equals("SVG", image_meta.format_label("image/svg+xml"))
      assert.equals("ICO", image_meta.format_label("image/x-icon"))
    end)

    it("returns nil for nil/non-image", function()
      assert.is_nil(image_meta.format_label(nil))
      assert.is_nil(image_meta.format_label("application/json"))
    end)
  end)

  describe("read_image_dimensions", function()
    it("reads PNG IHDR", function()
      local png = "\137PNG\r\n\26\n" .. be32(13) .. "IHDR"
        .. be32(1024) .. be32(768) .. "\8\6\0\0\0"
      local w, h = image_meta.read_image_dimensions(tmpfile(png))
      assert.equals(1024, w)
      assert.equals(768, h)
    end)

    it("reads GIF logical screen size", function()
      local gif = "GIF89a" .. le16(640) .. le16(480) .. "\0\0\0\0\0\0"
      local w, h = image_meta.read_image_dimensions(tmpfile(gif))
      assert.equals(640, w)
      assert.equals(480, h)
    end)

    it("reads JPEG SOF marker", function()
      local jpeg = "\255\216" .. "\255\192" .. be16(17) .. "\8"
        .. be16(768) .. be16(1024) .. "\3" .. "\1\17\0" .. "\2\17\1" .. "\3\17\1"
      local w, h = image_meta.read_image_dimensions(tmpfile(jpeg))
      assert.equals(1024, w)
      assert.equals(768, h)
    end)

    it("reads WebP (VP8 lossy)", function()
      local data = "\155\1\42" .. le16(400) .. le16(300) .. "\0\0\0"
      local webp = "RIFF" .. le32(4 + 4 + 8 + #data) .. "WEBP" .. "VP8 " .. le32(#data) .. data
      local w, h = image_meta.read_image_dimensions(tmpfile(webp))
      assert.equals(400, w)
      assert.equals(300, h)
    end)

    it("reads BMP", function()
      local bmp = "BM" .. "\0\0\0\0" .. "\0\0\0\0" .. "\0\0\0\0"
        .. le32(40) .. le32(640) .. le32(480)
      local w, h = image_meta.read_image_dimensions(tmpfile(bmp))
      assert.equals(640, w)
      assert.equals(480, h)
    end)

    it("reads SVG width/height attributes", function()
      local svg = '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600"><rect/></svg>'
      local w, h = image_meta.read_image_dimensions(tmpfile(svg))
      assert.equals(800, w)
      assert.equals(600, h)
    end)

    it("falls back to SVG viewBox when attributes are percentage-based", function()
      local svg = '<svg width="100%" height="100%" viewBox="0 0 300 200"></svg>'
      local w, h = image_meta.read_image_dimensions(tmpfile(svg))
      assert.equals(300, w)
      assert.equals(200, h)
    end)

    it("returns nil for unknown content", function()
      local w, h = image_meta.read_image_dimensions(tmpfile("this is not an image"))
      assert.is_nil(w)
      assert.is_nil(h)
    end)
  end)

  describe("read_jpeg_exif", function()
    it("reads IFD0 Make/Model/Orientation", function()
      local data_start = 8 + 2 + 3 * 12 + 4
      local tiff = "II" .. le16(42) .. le32(8) .. le16(3)
        .. le16(0x0110) .. le16(2) .. le32(13) .. le32(data_start) -- Model (offset)
        .. le16(0x010F) .. le16(2) .. le32(4) .. "ACME"            -- Make (inline)
        .. le16(0x0112) .. le16(3) .. le32(1) .. le16(6) .. le16(0) -- Orientation
        .. le32(0) -- next IFD
        .. "ACME Cam X1"
      local payload = "Exif\0\0" .. tiff
      local jpeg = "\255\216" .. "\255\225" .. le16(2 + #payload) .. payload
      local exif = image_meta.read_jpeg_exif(tmpfile(jpeg))
      assert.is_table(exif)
      assert.equals("ACME", exif.Make)
      assert.equals("ACME Cam X1", exif.Model)
      assert.equals(6, exif.Orientation)
    end)

    it("returns nil when no EXIF APP1 present", function()
      local jpeg = "\255\216" .. "\255\192" .. be16(17) .. "\8" .. be16(768) .. be16(1024) .. "\3"
      assert.is_nil(image_meta.read_jpeg_exif(tmpfile(jpeg)))
    end)
  end)

  describe("read_image_meta", function()
    it("aggregates format, dimensions and human-readable size", function()
      local png = "\137PNG\r\n\26\n" .. be32(13) .. "IHDR"
        .. be32(1024) .. be32(768) .. "\8\6\0\0\0"
      local path = tmpfile(png)
      local meta = image_meta.read_image_meta(path, "image/png")
      assert.equals(1024, meta.width)
      assert.equals(768, meta.height)
      assert.equals(#png, meta.size)
      assert.equals("29 B", meta.size_human)
      assert.equals("PNG", meta.format)
    end)
  end)
end)