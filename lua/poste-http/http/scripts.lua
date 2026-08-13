--- Pre-request scripts (< {% ... %} syntax): extraction, sandboxed execution, variable injection.
--- Also handles external script references (< ./path.lua).
local state = require("poste-http.state")
local script_block = require("poste-http.http.script_block")

local M = {}

local md5 = require("poste-http.http.md5").md5

---------------------------------------------------------------------------
-- Variable and env collection for sandbox injection
---------------------------------------------------------------------------

--- Parse @var definitions from content (file-level and block-level).
--- Resolves {{var}} references iteratively within collected vars.
--- Returns a table of { varname = value }
local function parse_vars_from_content(content)
  local vars = {}
  local lines = vim.split(content, "\n", { plain = true })
  for _, line in ipairs(lines) do
    -- Stop at first request block (file-level vars only)
    if line:match("^%s*###") then break end
    local name, value = line:match("^%s*@(%w[%w_]*)%s*=%s*(.+)%s*$")
    if not name then
      name, value = line:match("^%s*@(%w[%w_]*)%s+(%S+)%s*$")
    end
    if name then
      value = vim.trim(value)
      vars[name] = value
    end
  end

  -- Resolve {{var}} references iteratively
  for _ = 1, 20 do
    local changed = false
    for k, v in pairs(vars) do
      local resolved = v:gsub("{{(%w[%w_]*)}}", function(ref)
        if vars[ref] ~= nil then
          changed = true
          return vars[ref]
        end
        return "{{" .. ref .. "}}"
      end)
      if resolved ~= v then
        vars[k] = resolved
        changed = true
      end
    end
    if not changed then break end
  end

  return vars
end

--- Find and read env.json, returning the current env's variables.
--- @param env_name string|nil  Current env name (nil = use state.current_env)
--- @return table  { key = value, ... }
local function read_env_vars(env_name)
  env_name = env_name or state.current_env
  if not env_name then return {} end

  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then return {} end

  local dir = vim.fn.fnamemodify(bufname, ":h")
  while dir and dir ~= "" and dir ~= "/" do
    local candidate = dir .. "/env.json"
    local f = io.open(candidate, "r")
    if f then
      local content = f:read("*a")
      f:close()
      local ok, data = pcall(vim.json.decode, content)
      if ok and type(data) == "table" and data[env_name] then
        return data[env_name]
      end
      return {}
    end
    dir = vim.fn.fnamemodify(dir, ":h")
  end

  return {}
end

--- Collect block-level @var definitions from a specific request block.
--- @param content string  Full buffer content
--- @param block_start number  1-indexed start line of block
--- @param block_end number    1-indexed end line of block
--- @return table  { varname = value }
local function collect_block_vars(content, block_start, block_end)
  local lines = vim.split(content, "\n", { plain = true })
  local vars = {}
  for i = block_start, block_end do
    local line = lines[i] or ""
    local name, value = line:match("^%s*@(%w[%w_]*)%s*=%s*(.+)%s*$")
    if not name then
      name, value = line:match("^%s*@(%w[%w_]*)%s+(%S+)%s*$")
    end
    if name then
      value = vim.trim(value)
      vars[name] = value
    end
  end
  return vars
end

--- Collect all script-available variables: file-level vars, block-level vars,
--- and env vars. Block-level vars override file-level vars.
--- Returns { variables = { name = value, ... }, env = { key = value, ... } }
function M.collect_script_variables(content, block_start, block_end)
  local file_vars = parse_vars_from_content(content)
  local block_vars = collect_block_vars(content, block_start, block_end)

  local variables = {}
  for k, v in pairs(file_vars) do
    variables[k] = v
  end
  for k, v in pairs(block_vars) do
    variables[k] = v
  end

  local env = read_env_vars()

  return { variables = variables, env = env }
end

---------------------------------------------------------------------------
-- Extract pre-request script blocks from request content
---------------------------------------------------------------------------

--- Extract `< {% ... %}` inline pre-script blocks and `< ./path.lua` external
--- script references from request content.
--- Returns (stripped_content, script_code_or_nil).
function M.extract_pre_script_blocks(content, start_line, end_line)
  return script_block.extract_script_blocks(content, "<", start_line, end_line)
end

---------------------------------------------------------------------------
-- Run pre-request script in a sandboxed environment
---------------------------------------------------------------------------

--- Run pre-request script code in a sandboxed environment.
--- @param code string  Script code to execute
--- @param script_vars table|nil  { variables = { name = value }, env = { key = value } }
--- Returns: { variables = {...}, logs = {...}, error = nil|string }
function M.run_pre_script(code, script_vars)
  local variables = {}
  local logs = {}

  script_vars = script_vars or { variables = {}, env = {} }

  -- Build request object (no response available pre-request)
  local request = {
    variables = {
      set = function(name, value)
        variables[name] = tostring(value)
        local ctx = state._exec_context
        local line = ctx and ctx.set_lines and ctx.set_lines[name] or (ctx and ctx.line)
        if line then
          state.script_variables_sources[name] = { file = ctx.file, line = line }
        end
        state.log("INFO", string.format("Pre-script: request.variables.set('%s', '%s')", name, tostring(value)))
      end,
      get = function(name)
        return variables[name]
      end,
    },
  }

  local client = {
    global = {
      set = function(name, value)
        local ctx = state._exec_context
        local line = ctx and ctx.set_lines and ctx.set_lines[name] or (ctx and ctx.line)
        state.set_global_var(name, tostring(value))
        if line then
          state.global_vars_sources[name] = { file = ctx.file, line = line }
        end
        state.log("INFO", string.format("Pre-script: client.global.set('%s', '%s')", name, tostring(value)))
      end,
      get = function(name)
        return state.global_vars[name]
      end,
    },
    log = function(msg)
      table.insert(logs, tostring(msg))
    end,
  }

  -- Build sandbox environment
  local sandbox_env = {
    request = request,
    client = client,
    variables = script_vars.variables,
    env = script_vars.env,
    error = error,
    pcall = pcall,
    tostring = tostring,
    tonumber = tonumber,
    next = next,
    type = type,
    string = string,
    table = table,
    math = math,
    os = os,
    io = io,
    ipairs = ipairs,
    pairs = pairs,
    md5 = md5,
  }

  -- Execute code in sandbox
  local fn, load_err = load(code, "pre_script", "t", sandbox_env)
  if not fn then
    return {
      variables = {},
      logs = logs,
      error = "Pre-script syntax error: " .. tostring(load_err),
    }
  end

  local ok, run_err = pcall(fn)
  if not ok then
    return {
      variables = variables,
      logs = logs,
      error = "Pre-script runtime error: " .. tostring(run_err),
    }
  end

  return {
    variables = variables,
    logs = logs,
    error = nil,
  }
end

---------------------------------------------------------------------------
-- Inject pre-script variables into request content
---------------------------------------------------------------------------

--- Inject pre-script variables as @var = value lines after the ### header.
--- This ensures the Rust parser picks them up as request-scoped variables
--- with highest substitution priority.
--- Returns modified content (line count increases by number of variables).
function M.inject_pre_script_vars(content, block_start, variables)
  if not variables or not next(variables) then
    return content
  end

  local lines = vim.split(content, "\n", { plain = true })
  local result = {}

  for i, line in ipairs(lines) do
    table.insert(result, line)
    -- Insert variables right after the ### header line (block_start is 1-indexed)
    if i == block_start then
      for name, value in pairs(variables) do
        table.insert(result, string.format("@%s = %s", name, value))
      end
    end
  end

  return table.concat(result, "\n")
end

---------------------------------------------------------------------------
-- Format script logs for display
---------------------------------------------------------------------------

function M.format_script_logs(logs)
  if not logs or #logs == 0 then
    return { "No script output" }
  end

  local lines = {
    "## Script Output",
    "",
  }

  for _, msg in ipairs(logs) do
    for line in msg:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end
  end

  return lines
end

return M
