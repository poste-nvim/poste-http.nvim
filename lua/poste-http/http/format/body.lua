--- HTTP response body formatting.
---
--- Handles body rendering for HTTP responses, including JSON pretty-printing,
--- URL-encoded form display, binary file display, and large body truncation.
--- Extracted from the former format.lua god module.
local state = require("poste-http.state")
local fmt_util = require("poste-http.http.format.util")

local M = {}

--- Try to pretty-print JSON body; return as-is if not JSON or if already formatted
function M.pretty_body(body, content_type)
  return fmt_util.pretty_body(body, content_type)
end

--- Format urlencoded form data (application/x-www-form-urlencoded) as key-value lines.
function M.format_urlencoded_body(body)
  return fmt_util.format_urlencoded_body(body)
end

--- Main body formatting entry point.
function M.format_body(r)
  if r._cached_body then return r._cached_body end

  -- Binary file response: show file info instead of mangled raw content
  if r.metadata and r.metadata.file_path and r.metadata.file_content_type
    and not r.metadata.file_content_type:find("text")
    and not r.metadata.file_content_type:find("json")
    and not r.metadata.file_content_type:find("xml")
    and not r.metadata.file_content_type:find("html") then
    local lines = {}
    local ct = r.metadata.file_content_type or r.content_type or ""
    local image_mod = require("poste-http.http.format.image")
    local is_image = image_mod.is_image_content_type(ct)
    local can_inline = is_image and image_mod.has_image_nvim() and not ct:match("^image/svg%+xml")
    local pad_lines = image_mod.inline_image_padding_lines()
    if is_image then
      table.insert(lines, "▸ Image Response")
    else
      table.insert(lines, "▸ Binary File Response")
    end
    table.insert(lines, "")
    table.insert(lines, string.format("  Path:         %s", r.metadata.file_path))
    table.insert(lines, string.format("  Size:         %s  (%s bytes)", fmt_util.human_size(r.metadata.file_size), r.metadata.file_size or "?"))
    table.insert(lines, string.format("  Content-Type: %s", ct))
    table.insert(lines, "")
    if is_image then
      if can_inline then
        table.insert(lines, string.format("  Open file:    %s", r.metadata.file_path))
        for _ = 1, pad_lines do
          table.insert(lines, "")
        end
        r._cached_body = lines
        return lines
      else
        table.insert(lines, "  Preview:      press K to open externally")
      end
    end
    table.insert(lines, string.format("  Open file:    %s", r.metadata.file_path))
    r._cached_body = lines
    return lines
  end

  -- Large text response: truncate and save to file
  if fmt_util.is_large_body(r.body) then
    return fmt_util.save_body_to_file(r.body, r.content_type, r)
  end

  local body = M.pretty_body(r.body, r.content_type)
  local result = fmt_util.split_lines(body)
  r._cached_body = result
  return result
end

--- Clean up stale response cache files.
function M.clean_response_cache(max_age_minutes)
  local cfg = state.config or {}
  local cache_dir = cfg.response_cache_dir or vim.fn.stdpath("cache") .. "/poste_res"
  max_age_minutes = max_age_minutes or (24 * 60) -- default 24 hours

  if vim.fn.isdirectory(cache_dir) ~= 1 then return 0 end

  local now = vim.fn.localtime()
  local max_age_seconds = max_age_minutes * 60
  local count = 0

  local handle = vim.fn.readdir(cache_dir)
  for _, name in ipairs(handle) do
    local full = cache_dir .. "/" .. name
    local mtime = vim.fn.getftime(full)
    if mtime > 0 and (now - mtime) > max_age_seconds then
      os.remove(full)
      count = count + 1
    end
  end

  return count
end

return M