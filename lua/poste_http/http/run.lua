local state = require("poste_http.state")
local util = require("poste_http.util")
local indicators = require("poste_http.indicators")
local cache = require("poste_http.http.cache")
local request_vars = require("poste_http.http.request_vars")
local resolve = require("poste_http.http.resolve")
local scripts = require("poste_http.http.scripts")
local assertions = require("poste_http.http.assertions")
local view = require("poste_http.http.view")
local response_buf = require("poste_http.http.buffer")
local import_mod = require("poste_http.http.import")
local history = require("poste_http.http.history")
local event = require("poste_http.event")
local session = require("poste_http.http.session")
local describe = require("poste_http.http.describe")
local curl_exec = require("poste_http.http.curl_exec")
local vars = require("poste_http.http.vars")

local uv = vim.uv or vim.loop

local M = {}

---------------------------------------------------------------------------
-- Pipeline helpers
---------------------------------------------------------------------------

--- Build a synthetic response for a script-only block.
local function make_script_response(req_text, req_block)
  return {
    protocol = "script",
    status = 200,
    status_text = "Script executed",
    latency_ms = 0,
    url = vim.trim(req_text),
    content_type = "text/plain",
    headers = req_block and req_block.headers or {},
    body = "Script executed. See Assertions or Script Logs tab for details.",
    cookies = {},
    metadata = {
      method = "SCRIPT",
      exit_code = "0",
      request_line = vim.trim(req_text),
      env = state.current_env,
    },
  }
end

--- Build an error response table for a failed request.
local function make_error_response(req_text, req_block, body_text, err_msg, exit_code)
  return {
    protocol = "error",
    status = 0,
    status_text = err_msg,
    latency_ms = 0,
    url = vim.trim(req_text),
    content_type = "text/plain",
    headers = req_block and req_block.headers or {},
    body = body_text,
    cookies = {},
    metadata = {
      method = "",
      error = body_text,
      exit_code = tostring(exit_code or "?"),
      request_line = vim.trim(req_text),
      env = state.current_env,
    },
  }
end

--- Emit response:ready event with the given data.
local function emit_response(response_data, request_name, file_path, assertion_results, script_logs)
  event.emit("response:ready", {
    response = response_data,
    request_name = request_name,
    file = file_path,
    assertion_results = assertion_results or nil,
    script_logs = script_logs or nil,
  })
end

--- Run assertions and update state.
local function run_and_store_assertions(parsed, assertion_code, script_vars)
  if not assertion_code then return nil end
  local results = assertions.run_assertions(parsed, assertion_code, script_vars)
  state.last_assertion_results = results
  state.log("INFO", string.format("Assertions: %d passed, %d failed", results.passed, results.failed))
  if results.logs and #results.logs > 0 then
    state.last_script_logs = state.last_script_logs or {}
    for _, msg in ipairs(results.logs) do
      table.insert(state.last_script_logs, msg)
    end
  end
  return results
end

--- Choose the appropriate view tab based on status and assertion results.
local function choose_view_tab(parsed, assertion_results)
  if assertion_results and assertion_results.failed > 0 then
    return "assertions"
  end
  if parsed.status and parsed.status >= 400 then
    return "verbose"
  end
  return state.config.default_view or "body"
end

--- Set indicator based on status and assertions.
local function set_result_indicator(src_buf, line_0, parsed, assertion_results)
  local is_error = parsed.status and parsed.status >= 400
  local has_failures = assertion_results and assertion_results.failed > 0

  if has_failures then
    indicators.set_indicator(src_buf, line_0, "success", parsed.latency_ms, assertion_results)
  elseif is_error then
    indicators.set_indicator(src_buf, line_0, "error", parsed.latency_ms, assertion_results)
  else
    indicators.set_indicator(src_buf, line_0, "success", parsed.latency_ms, assertion_results)
  end
end

--- Add entry to history.
local function add_to_history(name, response_data, file_path)
  history.add_entry(name, response_data, state.last_assertion_results, state.last_script_logs, file_path)
end

--- Handle the parsed response from curl_exec.
local function handle_curl_response(response, src_buf, req_line, req_block, req_text, assertion_code, script_vars, current_req_name, file, start_hires)
  vim.schedule(function()
    state._json.query = nil
    state._json.original_lines = nil
    state._json.is_filtered = false

    -- Update pending_request with actual response data (keep URL/headers/body)
    if state.pending_request then
      state.pending_request = vim.tbl_extend("keep", {
        method = (response.metadata and response.metadata.method) or "",
        url = response.url or "",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
      }, state.pending_request)
    end

    if response.error then
      indicators.set_indicator(src_buf, req_line, "error")
      local error_response = {
        protocol = "error", status = 0, status_text = response.error,
        latency_ms = 0, url = "", content_type = "text/plain",
        headers = {}, body = response.error, cookies = {},
        metadata = { method = "", error = response.error, exit_code = "1" },
      }
      state.last_response = error_response
      state.last_responses = nil
      state.response_index = nil
      response_buf.reset_multi_response()
      emit_response(error_response, current_req_name, file, nil, nil)
      view.show_view("verbose")
      local err_name = (current_req_name or "") ~= "" and current_req_name or ("Request #" .. req_line + 1)
      add_to_history(err_name, state.last_response, file)
      return
    end

    if response.status == 0 and response.protocol == "error" then
      indicators.set_indicator(src_buf, req_line, "error")
      state.last_responses = nil
      state.response_index = nil
      response_buf.reset_multi_response()
      state.last_response = response
      emit_response(response, current_req_name, file, nil, nil)
      view.show_view("verbose")
      local err_name = (current_req_name or "") ~= "" and current_req_name or ("Request #" .. req_line + 1)
      add_to_history(err_name, state.last_response, file)
      return
    end

    state.last_response = response
    -- Carry request data into response metadata so Request/Verbose tabs can display it
    if state.pending_request then
      response.metadata = response.metadata or {}
      if not response.metadata.request_headers then
        response.metadata.request_headers = state.pending_request.headers_str or ""
      end
      if not response.metadata.request_body then
        response.metadata.request_body = state.pending_request.body or ""
      end
      if not response.metadata.timestamp then
        response.metadata.timestamp = state.pending_request.timestamp or ""
      end
      if not response.metadata.env then
        response.metadata.env = state.pending_request.env or ""
      end
    end
    response.request_name = current_req_name
    request_vars.cache_response(current_req_name, response)

    if request_vars._dep_chain and #request_vars._dep_chain > 0 then
      local chain = {}
      for _, item in ipairs(request_vars._dep_chain) do
        table.insert(chain, {name = item.name, response = item.response})
        history.add_entry(item.name, item.response, nil, nil, file)
      end
      table.insert(chain, {name = current_req_name or "Request", response = response})
      response_buf.reset_multi_response()
      state.last_responses = chain
      state.response_index = #chain
      request_vars._dep_chain = nil
      pcall(response_buf.prepare_multi_responses, chain)
    else
      state.last_responses = nil
      state.response_index = nil
      response_buf.reset_multi_response()
    end

    emit_response(response, current_req_name, file, nil, nil)

    local assertion_results = run_and_store_assertions(response, assertion_code, script_vars)
    local view_name = choose_view_tab(response, assertion_results)
    view.show_view(view_name)
    set_result_indicator(src_buf, req_line, response, assertion_results)
    local hist_name = (current_req_name or "") ~= "" and current_req_name or ("Request #" .. req_line + 1)
    add_to_history(hist_name, state.last_response, file)
  end)
end

--- Build pending request info for the Verbose tab.
--- Variable resolution via `poste resolve`; method/path/headers via `poste run --describe`
--- (single parse authority — no Lua re-parse of request blocks).
local function build_pending_request(src_buf, buf_content, req_block, block_start, block_end, file)
  -- Fallback headers from req_block (Lua indicators extract, used only if describe fails)
  local fallback_headers_str = describe.headers_str(req_block and { headers = req_block.headers } or nil)
  if fallback_headers_str == "" and req_block and req_block.headers then
    local parts = {}
    for _, h in ipairs(req_block.headers) do
      table.insert(parts, h[1] .. ": " .. h[2])
    end
    fallback_headers_str = table.concat(parts, "\n")
  end

  -- 1. Resolve variables via Lua VarResolver
  local resolved_content = nil
  if file and file ~= "" then
    local vars = require("poste_http.http.vars")
    local resolver = vars.build_resolver_from_state({
      buf = src_buf,
      file_path = file,
      block_start = block_start,
      block_end = block_end,
      env_name = state.current_env,
    })
    resolved_content = resolver:substitute(buf_content)
  end

  -- 2. Describe resolved (or raw) content via CLI — single parse authority
  local content = resolved_content or buf_content
  local req_method = ""
  local req_url = ""
  local body = ""
  local headers_str = fallback_headers_str
  local name = req_block and req_block.name or ""

  local blocks, desc_err = describe.describe_content(content, file)
  if blocks and #blocks > 0 then
    -- Resolved content is often a single-block slice; take first block, or
    -- the block matching block_start when full file content was described.
    local meta = blocks[1]
    if block_start and #blocks > 1 then
      meta = describe.block_at_line(blocks, block_start) or blocks[1]
    end
    if meta then
      req_method = meta.method or ""
      req_url = meta.path or ""
      body = meta.body or ""
      headers_str = describe.headers_str(meta)
      if headers_str == "" then
        headers_str = fallback_headers_str
      end
      if meta.name and meta.name ~= "" then
        name = meta.name
      end
    end
  elseif desc_err then
    state.log("WARN", "describe for pending request failed: " .. tostring(desc_err))
    if req_block then
      req_method = req_block.method or ""
      req_url = req_block.path or ""
      if req_block.request_line and (req_method == "" or req_url == "") then
        req_method, req_url = req_block.request_line:match("^(%S+)%s+(.+)$")
        req_method = req_method or ""
        req_url = req_url or ""
      end
      body = req_block.body or ""
      name = (req_block.name ~= "" and req_block.name) or name
      local h_parts = {}
      for _, h in ipairs(req_block.headers or {}) do
        table.insert(h_parts, h[1] .. ": " .. h[2])
      end
      if #h_parts > 0 then
        headers_str = table.concat(h_parts, "\n")
      end
    end
  else
    state.log("WARN", "describe returned no blocks, falling back to req_block")
    if req_block then
      req_method = req_block.method or ""
      req_url = req_block.path or ""
      if req_block.request_line and (req_method == "" or req_url == "") then
        req_method, req_url = req_block.request_line:match("^(%S+)%s+(.+)$")
        req_method = req_method or ""
        req_url = req_url or ""
      end
      body = req_block.body or ""
      name = (req_block.name ~= "" and req_block.name) or name
      local h_parts = {}
      for _, h in ipairs(req_block.headers or {}) do
        table.insert(h_parts, h[1] .. ": " .. h[2])
      end
      if #h_parts > 0 then
        headers_str = table.concat(h_parts, "\n")
      end
    end
  end

  state.pending_request = {
    method = req_method,
    url = req_url,
    headers_str = headers_str,
    body = body,
    name = name,
    env = state.current_env,
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    start_hires = uv.hrtime(),
  }
end

--- Handle the import/run directive response callback.
local function handle_directive_response(success, response, src_buf, indicator_line, assertion_code, script_vars, resolved, file)
  vim.schedule(function()
    if not (success and response) then
      indicators.set_indicator(src_buf, indicator_line, "error")
      return
    end

    -- Batch execution: response is an array of {name, response}
    if type(response) == "table" and response[1] and response[1].response then
      state.last_responses = response
      state.response_index = 1
      state.last_response = response[1].response
    else
      state.last_responses = nil
      state.response_index = 1
      state.last_response = response
    end

    emit_response(state.last_response, resolved.request_name, resolved.path or file, nil, nil)

    if assertion_code then
      run_and_store_assertions(state.last_response, assertion_code, script_vars)
      local view_name = choose_view_tab(state.last_response, state.last_assertion_results)
      view.show_view(view_name)
      set_result_indicator(src_buf, indicator_line, state.last_response, state.last_assertion_results)
    else
      local view_name = choose_view_tab(state.last_response, nil)
      view.show_view(view_name)
      set_result_indicator(src_buf, indicator_line, state.last_response, nil)
    end

    if type(response) == "table" and response[1] and response[1].response then
      for _, item in ipairs(response) do
        local item_name = (item.name or "") ~= "" and item.name or ("Request #" .. (item.line or ""))
        add_to_history(item_name, item.response, resolved.path or file)
      end
    else
      add_to_history(resolved.request_name or "Import", response, resolved.path or file)
    end
  end)
end

--- Inject global variables into buf_content after the block start line.
local function inject_global_vars(buf_content, block_start, global_vars)
  if not block_start or not global_vars or not next(global_vars) then
    return buf_content, 0
  end
  local glines = vim.split(buf_content, "\n", { plain = true })
  local result = {}
  local gcount = 0
  for _ in pairs(global_vars) do gcount = gcount + 1 end
  for i, line_text in ipairs(glines) do
    table.insert(result, line_text)
    if i == block_start then
      for name, value in pairs(global_vars) do
        table.insert(result, string.format("@%s = %s", name, value))
      end
    end
  end
  return table.concat(result, "\n"), gcount
end

--- Resolve the current request name from collected requests.
local function resolve_current_req_name(src_buf, line)
  local requests = request_vars.collect_requests(src_buf)
  for _, req in ipairs(requests) do
    if line >= req.start_line and line <= req.end_line then
      return req.name
    end
  end
  return nil
end

--- Prepare request: resolve prompt variables and request deps → modified content.
--- Returns (modified_content, req_line, block_start, block_end) via callback.
local function prepare_request(src_buf, line, buf_content, file, callback)
  local req_line = cache.find_request_line(src_buf, line)
  if not req_line then
    indicators.clear_all(src_buf)
    return
  end
  indicators.clear_other_requests(src_buf, req_line)
  indicators.set_indicator(src_buf, req_line, "running")

  local block_start, block_end = cache.find_request_block_bounds(src_buf, line)
  resolve.resolve(buf_content, {
    mode = "request",
    buf = src_buf,
    cursor_line = line,
    block_line = block_start,
    file = file,
    env_name = state.current_env,
  }, function(modified_content)
    if not modified_content then
      indicators.clear_all(src_buf)
      state.pending_request = nil
      return
    end
    callback(modified_content, req_line, block_start, block_end)
  end)
end

--- Execute request: run scripts, inject vars, build curl cmd, start job.
local function execute_request(src_buf, line, file, modified_content, req_line, block_start, block_end, callback)
  local buf_content = modified_content
  local pre_script_code
  local script_vars = nil
  if block_start then
    buf_content, pre_script_code = scripts.extract_pre_script_blocks(buf_content, block_start, block_end)
    script_vars = scripts.collect_script_variables(buf_content, block_start, block_end)
  end

  -- Run pre-request script if present
  if pre_script_code then
    local pre_result = scripts.run_pre_script(pre_script_code, script_vars)
    if pre_result.error then
      state.log("ERROR", pre_result.error)
      indicators.set_indicator(src_buf, req_line, "error")
      local err_resp = make_error_response("", nil, pre_result.error, "Pre-script error", 1)
      state.last_response = err_resp
      emit_response(err_resp, nil, file, nil, nil)
      view.show_view("verbose")
      return
    end
    if #pre_result.logs > 0 then
      state.last_script_logs = pre_result.logs
    end
    if next(pre_result.variables) then
      local injected_count = 0
      for _ in pairs(pre_result.variables) do injected_count = injected_count + 1 end
      buf_content = scripts.inject_pre_script_vars(buf_content, block_start, pre_result.variables)
      block_end = block_end + injected_count
      line = line + injected_count
      for name, value in pairs(pre_result.variables) do
        state.script_variables[name] = value
      end
    end
  end

  -- Inject global vars
  local global_count
  buf_content, global_count = inject_global_vars(buf_content, block_start, state.global_vars)
  block_end = block_end + global_count

  -- Process form data and extract assertion blocks
  buf_content = request_vars.process_form_data(src_buf, line, buf_content)
  local assertion_code
  buf_content, assertion_code = assertions.extract_assertion_blocks(buf_content, block_start, block_end)

  local current_req_name = resolve_current_req_name(src_buf, line)

  -- Prefer CLI describe for request semantics; fall back to indicators extract
  local req_block
  local meta = nil
  local blocks = describe.describe_content(buf_content, file)
  if blocks then
    meta = describe.block_at_line(blocks, block_start or line)
  end
  if meta then
    req_block = describe.to_req_block(meta)
  else
    req_block = cache.extract_request_block(src_buf, line)
  end
  local req_text = req_block.request_line

  -- Resolve Lua import references (@var = m.key, {{m.key}})
  local import_mod = require("poste_http.http.import")
  local buf_dir = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
  buf_content = import_mod.resolve_lua_imports(buf_content, buf_dir)

  callback(buf_content, req_block, req_text, assertion_code, script_vars, current_req_name, block_start, block_end)
end

--- Start curl execution via curl_exec, passing parsed request details.
local function start_curl_exec(file, buf_content, req_line, src_buf, req_block, req_text, assertion_code, script_vars, current_req_name, block_start, block_end)
  local buf_dir = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()

  -- Resolve variables in the content (use buf_content lines, not buffer, so
  -- prompt-injected @var lines like @method = value are visible to the resolver)
  local resolver = vars.build_resolver_from_state({
    lines = vim.split(buf_content, "\n", { plain = true }),
    file_path = file,
    block_start = block_start,
    block_end = block_end,
    env_name = state.current_env,
  })
  local resolved_content = resolver:substitute(buf_content)

  -- Describe the resolved content to extract method, url, headers, body
  local blocks = describe.describe_content(resolved_content, file)
  local meta = blocks and describe.block_at_line(blocks, block_start or 1)
  local method = "GET"
  local url = ""
  local headers = {}
  local body = ""

  if meta then
    method = meta.method or "GET"
    url = meta.path or ""
    headers = meta.headers or {}
    body = meta.body or ""
  elseif req_block then
    local rl = req_block.request_line or ""
    method = vim.trim(rl:match("^(%S+)") or "GET")
    url = vim.trim(rl:match("^%S+%s+(%S+)") or "")
    headers = req_block.headers or {}
    body = req_block.body or ""
  end

  -- Resolve any remaining {{var}} in the URL
  url = resolver:substitute(url)

  if not url or url == "" then
    indicators.set_indicator(src_buf, req_line, "error")
    vim.notify("Could not determine request URL", vim.log.levels.ERROR, { title = "Poste" })
    return
  end

  if url:find("{{") then
    state.log("WARN", "URL has unresolved variables: " .. url)
  end

  state.log("INFO", string.format("curl: %s %s (%d headers)", method, url, #headers))

  local start_hires = (vim.uv or vim.loop).hrtime()

  curl_exec.execute({
    method = method,
    url = url,
    headers = headers,
    body = body,
    buf_dir = buf_dir,
  }, function(response)
    handle_curl_response(response, src_buf, req_line, req_block, req_text, assertion_code, script_vars, current_req_name, file, start_hires)
  end)

  -- Set pending request from values we already have (no re-parse)
  local h_parts = {}
  for _, h in ipairs(headers) do
    table.insert(h_parts, h[1] .. ": " .. h[2])
  end
  state.pending_request = {
    method = method,
    url = url,
    headers_str = #h_parts > 0 and table.concat(h_parts, "\n") or "",
    body = body,
    name = (meta and meta.name) or (req_block and req_block.name) or "",
    env = state.current_env,
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    start_hires = start_hires,
  }
  view.show_view("verbose")
end

---------------------------------------------------------------------------
-- Main entry point
---------------------------------------------------------------------------

--- Run the HTTP request at the current cursor position.
function M.run_request()
  local src_buf = vim.api.nvim_get_current_buf()
  local line = vim.fn.line(".")
  local file = vim.api.nvim_buf_get_name(src_buf)
  if file == "" then
    file = vim.fn.getcwd() .. "/untitled.http"
  end

  -- Fresh session: clears all request-scoped state (Phase 2b)
  session.begin({ buf = src_buf, line = line, file = file })
  state.last_request = { buf = src_buf, line = line }

  local buf_lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
  local buf_content = table.concat(buf_lines, "\n")

  -- Check if this is a `run` directive (import/run cross-file execution)
  local resolved = import_mod.resolve_run_at_cursor(src_buf, line)
  if resolved.action ~= "none" then
    if resolved.warnings and #resolved.warnings > 0 then
      for _, w in ipairs(resolved.warnings) do
        state.log("WARN", w)
      end
    end

    if resolved.error then
      vim.notify(resolved.error, vim.log.levels.ERROR, { title = "Poste" })
      indicators.set_indicator(src_buf, (resolved.run_line or line) - 1, "error")
      return
    end

    state.log("INFO", string.format("Import/run directive resolved: %s -> %s line %d",
      resolved.action, resolved.path or "", resolved.line or 0))

    -- Extract assertion blocks from the run directive's block in the source buffer
    local block_start, block_end = cache.find_request_block_bounds(src_buf, line)
    local script_vars
    local assertion_code
    if block_start then
      script_vars = scripts.collect_script_variables(buf_content, block_start, block_end)
      _, assertion_code = assertions.extract_assertion_blocks(buf_content, block_start, block_end)
    end

    -- Place indicator on the run directive line itself
    local indicator_line = (resolved.run_line or line) - 1
    indicators.set_indicator(src_buf, indicator_line, "running")

    import_mod.execute_run_directive(resolved, function(success, response)
      handle_directive_response(success, response, src_buf, indicator_line, assertion_code, script_vars, resolved, file)
    end)
    return
  end

  -- Standard request pipeline
  prepare_request(src_buf, line, buf_content, file, function(modified_content, req_line, block_start, block_end)
    execute_request(src_buf, line, file, modified_content, req_line, block_start, block_end,
      function(inner_content, req_block, req_text, assertion_code, script_vars, current_req_name, blk_start, blk_end)
        if req_text and vim.trim(req_text):upper() == "SCRIPT" then
          local script_response = make_script_response(req_text, req_block)
          state.last_response = script_response
          state._json.query = nil
          state._json.original_lines = nil
          state._json.is_filtered = false
          emit_response(script_response, current_req_name, file, nil, nil)

          local assertion_results = run_and_store_assertions(script_response, assertion_code, script_vars)

          if assertion_results and assertion_results.total > 0 then
            view.show_view("assertions")
          elseif state.last_script_logs and #state.last_script_logs > 0 then
            view.show_view("script_logs")
          else
            view.show_view("verbose")
          end

          set_result_indicator(src_buf, req_line, script_response, assertion_results)
          local hist_name = (current_req_name or "") ~= "" and current_req_name or ("Script #" .. tostring(req_line + 1))
          add_to_history(hist_name, script_response, file)
          return
        end

        start_curl_exec(file, inner_content, req_line, src_buf, req_block, req_text,
          assertion_code, script_vars, current_req_name, blk_start, blk_end)
      end)
  end)
end

return M
