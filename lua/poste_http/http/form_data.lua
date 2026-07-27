local cache = require("poste_http.http.cache")

local M = {}

local function generate_uuid()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return template:gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end)
end

local magic_vars = {
  timestamp = function() return tostring(os.time()) .. math.random(100000, 999999) end,
  uuid      = function() return generate_uuid() end,
  date      = function() return os.date("%Y-%m-%d") end,
  randomInt = function() return tostring(math.random(0, 9999999)) end,
}

function M.process_form_data(src_buf, cursor_line, content)
  local start_line, end_line = cache.find_request_block_bounds(src_buf, cursor_line)
  if not start_line then return content end

  local generated = {}
  for name, gen in pairs(magic_vars) do
    generated[name] = gen()
  end

  local lines = vim.split(content, "\n", { plain = true })
  local result = {}

  for i, line in ipairs(lines) do
    if i >= start_line and i <= end_line then
      local processed = line
      for name, value in pairs(generated) do
        processed = processed:gsub("{{%$" .. name .. "}}", value)
      end
      table.insert(result, processed)
    else
      table.insert(result, line)
    end
  end

  return table.concat(result, "\n")
end

return M