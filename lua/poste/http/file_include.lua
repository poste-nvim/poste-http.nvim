local M = {}

local function resolve_file_path(path, buf_dir)
  if not path or path == "" then return nil end
  path = vim.trim(path)
  if path:sub(1, 1) == "~" then
    return vim.fn.expand("~") .. path:sub(2)
  elseif path:sub(1, 1) ~= "/" then
    return vim.fn.simplify(buf_dir .. "/" .. path)
  end
  return path
end

function M.expand_file_includes(content, buf_dir)
  if not content or content == "" then
    return content, nil
  end
  local lines = vim.split(content, "\n", { plain = true })
  local result = {}
  local had_include = false
  for _, line in ipairs(lines) do
    local ref = line:match("^%s*<(%s+.+)$")
    if ref then
      local path = vim.trim(ref)
      local resolved = resolve_file_path(path, buf_dir)
      if not resolved then
        return nil, "Invalid file path: " .. path
      end
      local fd = io.open(resolved, "r")
      if not fd then
        return nil, "File not found: " .. resolved .. " (referenced from body line)"
      end
      local file_content = fd:read("*a")
      fd:close()
      file_content = file_content:gsub("\r\n", "\n")
      file_content = file_content:gsub("\n$", "")
      table.insert(result, file_content)
      had_include = true
    else
      table.insert(result, line)
    end
  end
  if not had_include then
    return content, nil
  end
  return table.concat(result, "\n"), nil
end

return M