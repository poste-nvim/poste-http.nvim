local M = {}

local function parse_path_segments(path)
  local segments = {}
  local i = 1
  while i <= #path do
    if path:sub(i, i) == "." then
      i = i + 1
    else
      local start = i
      local depth = 0
      while i <= #path do
        local c = path:sub(i, i)
        if c == "[" then
          depth = depth + 1
        elseif c == "]" then
          depth = depth - 1
        elseif c == "." and depth == 0 then
          break
        end
        i = i + 1
      end
      table.insert(segments, path:sub(start, i - 1))
    end
  end
  return segments
end

local function resolve_segments(current, segments, idx)
  if idx > #segments then return current end
  if type(current) == "string" then
    local ok, parsed = pcall(vim.json.decode, current)
    if ok and type(parsed) == "table" then
      current = parsed
    else
      return nil
    end
  end
  if type(current) ~= "table" then return nil end
  local part = segments[idx]
  local array_field = part:match("^(.*)%[%]$")
  if array_field then
    local arr
    if array_field == "" then
      arr = current
    else
      arr = current[array_field]
      if arr == nil then arr = current[array_field .. "[]"] end
    end
    if type(arr) ~= "table" or not vim.tbl_islist(arr) then return nil end
    local results = {}
    for _, elem in ipairs(arr) do
      local r = resolve_segments(elem, segments, idx + 1)
      if r ~= nil then
        table.insert(results, r)
      end
    end
    return results
  end
  local field, idx_str = part:match("^(.*)%[(%d+)%]$")
  if field and idx_str then
    local arr
    if field == "" then
      arr = current
    else
      arr = current[field]
      if arr == nil then arr = current[field .. "[]"] end
    end
    if type(arr) ~= "table" then return nil end
    return resolve_segments(arr[tonumber(idx_str) + 1], segments, idx + 1)
  end
  local value = current[part]
  if value == nil then value = current[part .. "[]"] end
  return resolve_segments(value, segments, idx + 1)
end

function M.get_nested_value(obj, path)
  if not obj or path == "" then return nil end
  local segments = parse_path_segments(path)
  return resolve_segments(obj, segments, 1)
end

function M.parse_path_segments(path)
  return parse_path_segments(path)
end

M._test = {
  parse_path_segments = parse_path_segments,
  resolve_segments = resolve_segments,
}

return M