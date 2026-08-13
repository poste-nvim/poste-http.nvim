--- Shared HTTP request-variable resolution pipeline.
---
--- This module centralizes the async orchestration that used to be split across
--- `run.lua`, `import.lua`, and `request_vars.lua` call sites.
local state = require("poste-http.state")
local request_vars = require("poste-http.http.request_vars")

local M = {}

local handlers = {}

local function default_prompt_handler(content, opts, on_complete)
  if not opts.buf or not opts.cursor_line or not opts.file then
    on_complete(content)
    return
  end

  request_vars._handle_prompt_variables_impl(
    opts.buf,
    opts.cursor_line,
    content,
    opts.file,
    opts.env_name or state.current_env,
    on_complete
  )
end

local function default_dependency_handler(content, opts, on_complete)
  if not opts.file or not opts.block_line then
    on_complete(content)
    return
  end

  request_vars._resolve_content_dependencies_impl(
    opts.buf,
    opts.file,
    opts.env_name or state.current_env,
    content,
    opts.block_line,
    function(resolved_content)
      on_complete(resolved_content or content)
    end
  )
end

handlers.prompts = default_prompt_handler
handlers.dependencies = default_dependency_handler

local function run_stage(stage, content, opts, on_complete, stage_handlers)
  local handler = stage_handlers[stage]
  if not handler then
    on_complete(content)
    return
  end
  handler(content, opts, on_complete)
end

--- Resolve request content through the shared async pipeline.
---
--- @param content string
--- @param opts table
---   - mode: "request" (default) or "import"
---   - buf: number|nil
---   - cursor_line: number|nil
---   - block_line: number|nil
---   - binary: string|nil
---   - file: string|nil
---   - env_name: string|nil
---   - handlers: table|nil  Optional { prompts, dependencies } overrides
---     (used for testing; defaults come from this module)
--- @param on_complete function|string|nil
function M.resolve(content, opts, on_complete)
  opts = opts or {}
  local mode = opts.mode or "request"
  local stage_handlers = opts.handlers or handlers

  local function finish(resolved)
    if on_complete then
      on_complete(resolved)
    end
  end

  if mode == "import" then
    run_stage("dependencies", content, opts, function(dep_resolved)
      if dep_resolved == nil then
        finish(nil)
        return
      end
      run_stage("prompts", dep_resolved, opts, finish, stage_handlers)
    end, stage_handlers)
    return
  end

  run_stage("prompts", content, opts, function(prompt_resolved)
    if prompt_resolved == nil then
      finish(nil)
      return
    end
    run_stage("dependencies", prompt_resolved, opts, finish, stage_handlers)
  end, stage_handlers)
end

return M
