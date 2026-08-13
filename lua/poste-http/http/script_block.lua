--- Shared extraction for `< {% ... %}` pre-script and `> {% ... %}` assertion blocks.
--- scripts.lua and assertions.lua used to duplicate ~80 lines each; only the leading
--- marker character (`<` vs `>`) and the log label differed. This module is the
--- single implementation both delegate to.
local state = require("poste-http.state")

local M = {}

--- Human-readable label derived from the block marker, used in logs and the
--- generated error() for unreadable external scripts.
--- @param marker string  "<" for pre-scripts, ">" for assertions
local function script_label(marker)
  if marker == "<" then
    return "pre-script"
  end
  return "assertion script"
end

--- Extract `< {% ... %}`/`> {% ... %}` inline script blocks and external
--- `./path.lua` script references from request content.
--- Always strips ALL matching blocks (replacing with empty lines to preserve line count).
--- Only collects script code within the optional start_line/end_line range (1-indexed).
--- When start_line/end_line are nil, collects from all blocks.
--- @param content string  Full buffer content
--- @param marker string  Block prefix: "<" for pre-scripts, ">" for assertions
--- @param start_line integer|nil  1-indexed lower bound (inclusive)
--- @param end_line integer|nil    1-indexed upper bound (inclusive)
--- @return string stripped_content
--- @return string|nil script_code  Concatenated collected code, nil when no blocks match
function M.extract_script_blocks(content, marker, start_line, end_line)
  local lines = vim.split(content, "\n", { plain = true })
  local result = {}
  local code_parts = {}
  local in_block = false
  local block_lines = {}
  local block_start_line = 0
  local label = script_label(marker)

  -- Determine the .http file directory for resolving external scripts
  local file_dir = vim.fn.expand("%:p:h")

  for i, line in ipairs(lines) do
    local trimmed = vim.trim(line)

    if not in_block then
      -- Single-line inline: < {% code %} or > {% code %}
      local code = trimmed:match("^" .. marker .. "%s*{%%(.-)%%}$")
      if code then
        if not start_line or (i >= start_line and i <= end_line) then
          table.insert(code_parts, code)
        end
        table.insert(result, "")  -- preserve line count

      -- External script: < ./path.lua or < ../path.lua
      elseif trimmed:match("^" .. marker .. "%s*%.?%.") and trimmed:match("%.lua%s*$") then
        local path = trimmed:match("^" .. marker .. "%s*(%S+)%s*$")
        if path and (not start_line or (i >= start_line and i <= end_line)) then
          -- Resolve relative path against .http file directory
          if path:sub(1, 1) == "." then
            path = file_dir .. "/" .. path
          end
          -- Read external script file
          local f = io.open(path, "r")
          if f then
            local script_content = f:read("*a")
            f:close()
            table.insert(code_parts, "-- external: " .. path .. "\n" .. script_content)
            state.log("INFO", "Loaded external " .. label .. ": " .. path)
          else
            state.log("ERROR", "Cannot open " .. label .. " file: " .. path)
            table.insert(code_parts, 'error("Cannot open ' .. label .. ' file: ' .. path .. '")')
          end
        end
        table.insert(result, "")  -- preserve line count

      -- Multi-line start: < {%
      elseif trimmed:match("^" .. marker .. "%s*{%%") then
        in_block = true
        block_lines = {}
        block_start_line = i
        table.insert(result, "")  -- preserve line count

      else
        table.insert(result, line)
      end
    else
      -- Inside multi-line block
      if trimmed == "%}" then
        -- End of block
        if not start_line or (block_start_line >= start_line and i <= end_line) then
          table.insert(code_parts, table.concat(block_lines, "\n"))
        end
        in_block = false
        block_lines = {}
      else
        table.insert(block_lines, line)
      end
      table.insert(result, "")  -- preserve line count
    end
  end

  if #code_parts == 0 then
    return table.concat(result, "\n"), nil
  end

  return table.concat(result, "\n"), table.concat(code_parts, "\n")
end

return M