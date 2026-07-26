local M = {}

local function get_node_text(node, lines)
  if not node then return "" end
  local ok, sr, sc, er, ec = pcall(node.range, node)
  if not ok then return "" end
  if sr == er then
    return lines[sr + 1]:sub(sc + 1, ec)
  end
  local parts = { lines[sr + 1]:sub(sc + 1) }
  for i = sr + 2, er + 1 do
    table.insert(parts, lines[i])
  end
  parts[#parts] = parts[#parts]:sub(1, ec)
  return table.concat(parts, "\n")
end

local function format_json_body(body)
  if not body or body == "" then return body end
  local trimmed = vim.trim(body)
  if trimmed:sub(1, 1) ~= "{" and trimmed:sub(1, 1) ~= "[" then return body end
  local ok, decoded = pcall(vim.json.decode, body)
  if not ok then return body end
  local ok2, encoded = pcall(vim.json.encode, decoded, { indent = 2 })
  if not ok2 then return body end
  return encoded
end

function M.format(content)
  if not content or content == "" then return content end

  local ok, parser = pcall(vim.treesitter.get_string_parser, content, "poste_http")
  if not ok or not parser then
    return content
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then return content end

  local root = trees[1]:root()
  local lines = vim.split(content, "\n", { plain = true })
  local result = {}
  local i = 1

  while i <= #lines do
    local line = lines[i]
    local trimmed = vim.trim(line)

    if trimmed:match("^###") then
      if #result > 0 and result[#result] ~= "" then
        table.insert(result, "")
      end
      local name = trimmed:match("^###%s*(.*)")
      if name and name ~= "" then
        table.insert(result, "### " .. vim.trim(name))
      else
        table.insert(result, "###")
      end
      i = i + 1
    elseif trimmed:match("^@") then
      local name, value = trimmed:match("^@(%S+)%s*=%s*(.+)")
      if not name then
        name, value = trimmed:match("^@(%S+)%s+(.+)")
      end
      if name and value then
        table.insert(result, "@" .. name .. " = " .. value)
      else
        table.insert(result, line)
      end
      i = i + 1
    elseif trimmed:match("^[A-Z]+%s+%S") and not trimmed:match(":") then
      local method = trimmed:match("^(%S+)")
      local rest = trimmed:match("^%S+%s+(.+)")
      if method and rest then
        table.insert(result, method .. " " .. rest)
      else
        table.insert(result, trimmed)
      end
      i = i + 1
    elseif trimmed:match("^[%w%-]+%s*:") and not trimmed:match("^###") then
      local key, value = trimmed:match("^([^:]+):%s*(.*)")
      if key then
        table.insert(result, vim.trim(key) .. ": " .. vim.trim(value))
      else
        table.insert(result, line)
      end
      i = i + 1
    elseif trimmed == "" then
      if #result > 0 and result[#result] ~= "" then
        table.insert(result, "")
      end
      i = i + 1
    else
      local body_lines = {}
      while i <= #lines do
        table.insert(body_lines, lines[i])
        i = i + 1
      end
      local body = table.concat(body_lines, "\n")
      body = body:gsub("^(\n*)", "")
      body = format_json_body(body)
      if body ~= "" then
        if #result > 0 and result[#result] ~= "" then
          table.insert(result, "")
        end
        table.insert(result, body)
      end
    end
  end

  local formatted = table.concat(result, "\n")
  formatted = formatted:gsub("\n\n\n+", "\n\n")
  formatted = formatted:gsub("^\n+", "")
  formatted = formatted:gsub("\n+$", "") .. "\n"

  return formatted
end

function M.format_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  local formatted = M.format(content)
  if formatted == content then
    return false
  end
  local new_lines = vim.split(formatted, "\n", { plain = true })
  if new_lines[#new_lines] == "" then
    table.remove(new_lines)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
  return true
end

return M