--- ```http code-block execution for the "http" AI context — runs an
--- AI-authored block through the regular poste-http pipeline (env resolution,
--- prompt vars, scripts, assertions, response panel, history) from the chat.
--- Safety: only clearly read-only methods run without confirmation.
--- Prompt hygiene: blocks are executed exactly as written — {{var}}
--- placeholders are resolved by the pipeline from env.json, never inlined
--- into chat content.

local M = {}

--- Read-only methods (Lua patterns have no alternation, hence the table).
local READONLY_METHODS = {
  GET = true, HEAD = true, OPTIONS = true,
}

--- Heuristic read-only check for the confirm gate.
--- @param text string block text
--- @return boolean
function M.is_readonly(text)
  local method = require("poste-http.ai.blocks").method_of_text(text)
  return method ~= nil and READONLY_METHODS[method] == true
end

--- Confirm gate used by poste-ai's codeblock action. GET/HEAD/OPTIONS pass;
--- everything else asks (mirrors the family's destructive-op dialogs).
--- @param text string
--- @return boolean proceed
function M.confirm_http(text)
  if M.is_readonly(text) then return true end
  local method = require("poste-http.ai.blocks").method_of_text(text) or "REQUEST"
  local choice = vim.fn.confirm(
    ("AI wants to execute a %s request — run it?"):format(method),
    "&Yes\n&No", 2, "Warning")
  return choice == 1
end

--- Header line for appending an AI-authored block into a `.http` origin
--- buffer (poste-ai's `ga` action): a `### Title` separator, without which
--- the block would merge into the previous request. Nil when the origin is
--- not a `.http` buffer or the block carries its own `###` header.
--- @param _scope table|nil chat scope snapshot (unused)
--- @param text string block text
--- @return string[]|nil
function M.append_header(_scope, text)
  local ok_ai, ai_state = pcall(require, "poste-ai.state")
  local origin = ok_ai and ai_state.origin_buf or nil
  if not origin or not vim.api.nvim_buf_is_valid(origin) then return nil end
  if vim.bo[origin].filetype ~= "poste_http" then return nil end
  if type(text) == "string" and text:match("^%s*###") then return nil end
  return { "### " .. require("poste-http.ai.blocks").title_of_text(text or "") }
end

--- Directory anchoring env.json discovery: mention file → chat scope file
--- → cwd.
--- @param refs table|nil mention refs of the user turn
--- @param scope table|nil chat scope snapshot
--- @return string
function M.resolve_target_dir(refs, scope)
  for _, ref in ipairs(refs or {}) do
    if ref.type == "context" and ref.context == "http"
      and type(ref.data) == "table" and type(ref.data.file) == "string" then
      return vim.fn.fnamemodify(ref.data.file, ":h")
    end
  end
  if scope and type(scope.file) == "string" and scope.file ~= "" then
    return vim.fn.fnamemodify(scope.file, ":h")
  end
  return vim.fn.getcwd()
end

local SCRATCH_TAIL = ".poste-ai-request.http"

--- Create the execution scratch buffer: a named nofile buffer whose path
--- lives in `dir` so env.json walk-up discovery works, while `nofile` keeps
--- `:w` refused. Previous scratch buffers with the same name are removed.
--- @param dir string anchor directory
--- @return number buf, string file_path
function M._fresh_scratch(dir)
  local file_path = vim.fs.joinpath(dir, SCRATCH_TAIL)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == file_path then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.bo[buf].filetype = "poste_http"
  pcall(vim.api.nvim_buf_set_name, buf, file_path)
  return buf, file_path
end

--- Completion detection: the run pipeline has terminal paths that emit no
--- event (pre-request errors, silent bail on a missing request line), so poll
--- state instead — busy flag plus last_response / last_errors. `finish` fires
--- exactly once.
local function poll_completion(finish, timeout_ms)
  local uv = vim.uv or vim.loop
  local timer = uv.new_timer()
  local started = uv.now()
  timer:start(250, 250, vim.schedule_wrap(function()
    local state = require("poste-http.state")
    if state._busy then return end
    if state.last_response then
      finish(nil, state.last_response)
    elseif state.last_errors and #state.last_errors > 0 then
      finish("pre-request error — see the response panel's Error tab", nil)
    elseif uv.now() - started < (timeout_ms or 40000) then
      return
    else
      finish("request did not run — the block did not parse as a request", nil)
    end
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end))
  return timer
end

--- Execute an AI-authored .http block. Called by poste-ai's codeblock action.
--- @param text string block text
--- @param refs table mention refs of the user turn
--- @param cb function(err, note)
function M.execute_http(text, refs, cb)
  local state = require("poste-http.state")
  local blocks_mod = require("poste-http.ai.blocks")

  if state._busy then
    cb("a request is already running — wait for it to finish", nil)
    return
  end
  local method = blocks_mod.method_of_text(text)
  if not method then
    cb("block does not look like an HTTP request — expected a request line like `GET https://…`", nil)
    return
  end

  local ok_ai, poste_ai = pcall(require, "poste-ai")
  local scope = ok_ai and poste_ai.scope and poste_ai.scope() or nil
  local dir = M.resolve_target_dir(refs, scope)
  local buf = M._fresh_scratch(dir)
  local lines = vim.split(vim.trim(text), "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- The pipeline runs on the current buffer/cursor, so surface the scratch
  -- in a split and leave it open for editing/saving after the run. Split
  -- from the chat origin window when visible — the chat sidebar is too
  -- narrow to split from.
  local ok_state, ai_state = pcall(require, "poste-ai.state")
  local origin = ok_state and ai_state.origin_buf or nil
  if origin then
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == origin then
        pcall(vim.api.nvim_set_current_win, w)
        break
      end
    end
  end
  vim.cmd(state.config.split_direction == "horizontal" and "split" or "vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })

  local done = false
  local function finish(exec_err, response)
    if done then return end
    done = true
    if exec_err then
      cb(exec_err, nil)
    elseif response.protocol == "error" or (response.status or 0) == 0 then
      local msg = (response.metadata and response.metadata.error)
        or response.status_text or "request failed"
      cb("request failed: " .. tostring(msg), nil)
    else
      local label = (response.metadata and response.metadata.method) or method
      local status = ("%d %s"):format(response.status or 0, response.status_text or "")
      cb(nil, ("✓ ran %s %s → %s — details in the response panel")
        :format(label, response.url or "", vim.trim(status)))
    end
  end
  poll_completion(finish, (state.config.timeout or 30000) + 10000)

  require("poste-http.http.run").run_request()
end

M._test = {
  is_readonly = M.is_readonly,
  resolve_target_dir = M.resolve_target_dir,
  append_header = M.append_header,
  READONLY_METHODS = READONLY_METHODS,
}

return M
