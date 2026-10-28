local util = require("poste-http.util")

local M = {}

--- @return string  (never the gsub count — see vars.lua's twin)
local function generate_uuid()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (template:gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end))
end

local magic_vars = {
  timestamp = function() return tostring(os.time()) .. math.random(100000, 999999) end,
  uuid      = function() return generate_uuid() end,
  date      = function() return os.date("%Y-%m-%d") end,
  randomInt = function() return tostring(math.random(0, 9999999)) end,
}

function M.substitute_magic_vars(line, generated)
  for name, value in pairs(generated) do
    -- function replacement: a % in a generated value must stay literal,
    -- gsub would otherwise read it as a capture reference
    line = line:gsub("{{%$" .. name .. "}}", function() return value end)
  end
  return line
end

--- Substitute {{$magic}} vars across one request block.
---
--- Bounds arrive in CONTENT coordinates (the coordinates of `content` itself,
--- which injections may have shifted relative to the source buffer) from the
--- caller — run.lua tracks them as it injects. Reading them from the buffer
--- instead used to miss the block's tail lines: with a pre-script/global
--- injection inside the block, the buffer bounds stopped short and the tail's
--- {{$uuid}} fell through to the later VarResolver pass, which drew a SECOND,
--- different value for the same request.
---
--- @param start_line integer|nil  content-coord first line of the block
--- @param end_line integer|nil    content-coord last line of the block
--- @param content string          resolved request content
--- @return string
function M.process_form_data(start_line, end_line, content)
  if not start_line or not end_line then return content end

  local generated = {}
  util.seed_random() -- magic draws must differ across sessions (fixed LuaJIT seed)
  for name, gen in pairs(magic_vars) do
    generated[name] = gen()
  end

  local lines = vim.split(content, "\n", { plain = true })
  local result = {}

  for i, line in ipairs(lines) do
    if i >= start_line and i <= end_line then
      table.insert(result, M.substitute_magic_vars(line, generated))
    else
      table.insert(result, line)
    end
  end

  return table.concat(result, "\n")
end

return M