--- Single source of truth for HTTP request block boundary rules.
--- Used by both describe.lua (tree-sitter semantic blocks) and cache.lua
--- (UI block index) so the two can never diverge again.

local M = {}

local function trimmed(line)
  return vim.trim(line)
end

--- A `###` separator line starts a new request block.
function M.is_separator(line)
  return line:match("^%s*###") ~= nil
end

--- A comment line (`# ...` or `-- ...`). Empty lines are not comments.
function M.is_comment(line)
  local t = trimmed(line)
  return t ~= "" and (t:match("^#") or t:match("^%-%-")) ~= nil
end

--- Content line: non-empty and not a comment.
function M.is_content(line)
  if not line then return false end
  local t = trimmed(line)
  return t ~= "" and not M.is_comment(line)
end

--- Compute a request block's range.
--- @param lines string[] 1-indexed array of buffer lines
--- @param start number 1-indexed line of the block's `###` separator
--- @return integer end_line  line before the next separator, or #lines
--- @return integer last_content_line  last non-empty, non-comment line in [start, end_line]
function M.compute_block_range(lines, start)
  local n = #lines
  local end_line = n
  for i = start + 1, n do
    if M.is_separator(lines[i]) then
      end_line = i - 1
      break
    end
  end

  local last_content = start
  for i = end_line, start, -1 do
    if M.is_content(lines[i]) then
      last_content = i
      break
    end
  end

  return end_line, last_content
end

return M
