local state = require("poste-http.state")
local curl_exec = require("poste-http.http.curl_exec")
local describe = require("poste-http.http.describe")
local vars = require("poste-http.http.vars")
local nested_access = require("poste-http.http.nested_access")
local jq_mapping = require("poste-http.http.jq_mapping")

local M = {}

local get_nested_value = nested_access.get_nested_value

local request_response_cache = {}
local _chain_dep_set = {}
local _chain_dep_order = {}

local handle_prompt_fn = nil

function M.set_prompt_handler(fn)
  handle_prompt_fn = fn
end

local function resolve_request_variable(pattern, cached_responses)
  local req_name, source, target = pattern:match("^([^%.]+)%.([^%.]+)%.([^%.]+)")
  if not req_name or not source or not target then
    return nil
  end

  local full_match = req_name .. "." .. source .. "." .. target
  local path = pattern:sub(#full_match + 2)

  local response = cached_responses[req_name]
  if not response then
    state.log("WARN", string.format("Request variable: '%s' not found in cache", req_name))
    return nil
  end

  if source == "response" then
    if target == "body" then
      local body = response.body
      if not body or body == "" then return nil end
      if path == "" then return body end
      local ok, parsed = pcall(vim.json.decode, body)
      if not ok then
        state.log("WARN", string.format("Cannot parse response body as JSON for '%s'", req_name))
        return nil
      end
      return get_nested_value(parsed, path)
    elseif target == "headers" then
      if not response.headers then return nil end
      for _, h in ipairs(response.headers) do
        if h[1]:lower() == path:lower() then
          return h[2]
        end
      end
    end
  elseif source == "request" then
    if target == "body" then
      local body = response.metadata and response.metadata.request_body
      if not body or body == "" or path == "" then return body end
      local ok, parsed = pcall(vim.json.decode, body)
      if ok then return get_nested_value(parsed, path) end
    elseif target == "headers" then
      local headers_str = response.metadata and response.metadata.request_headers
      if not headers_str then return nil end
      for line in headers_str:gmatch("[^\r\n]+") do
        local key, value = line:match("^([^:]+):%s*(.+)$")
        if key and value and vim.trim(key):lower() == path:lower() then
          return vim.trim(value)
        end
      end
    end
  end
  return nil
end

local function find_request_variable_refs(block_text)
  local refs = {}
  for full_ref in block_text:gmatch("{{(.-)}}") do
    if full_ref:match("%.response%.") or full_ref:match("%.request%.") then
      local req_name = full_ref:match("^([^%.]+)%.")
      if req_name then
        table.insert(refs, { full = "{{" .. full_ref .. "}}", request_name = req_name })
      end
    end
  end
  return refs
end

local function find_dynamic_prompt_refs(block_text)
  local refs = {}
  for line in block_text:gmatch("[^\n]+") do
    local options_str = line:match("^%s*<<[%a_][%w_]*%s*%[(.+)%]")
    if options_str then
      local full_ref = options_str:match("{{(.+%.response%..+)}}")
      if full_ref then
        local req_name = full_ref:match("^([^%.]+)%.")
        if req_name then
          table.insert(refs, { full = "{{" .. full_ref .. "}}", request_name = req_name })
        end
      end
    end
  end
  return refs
end

M.find_request_variable_refs = find_request_variable_refs

local function read_file_vars_from_path(file_path)
  local ok, content = pcall(vim.fn.readfile, file_path)
  if not ok or type(content) ~= "table" then return "", 0 end
  local lines = {}
  for _, line in ipairs(content) do
    local trimmed = vim.trim(line)
    if trimmed:match("^@") then
      table.insert(lines, trimmed)
    elseif trimmed:match("^###") then
      break
    end
  end
  return table.concat(lines, "\n"), #lines
end

local function execute_dependent_request_async(buf, file, env_name, dep_req, dep_block_text, on_complete)
  if request_response_cache[dep_req.name] then
    state.log("INFO", string.format("Using cached response for '%s'", dep_req.name))
    vim.schedule(function() on_complete(request_response_cache[dep_req.name]) end)
    return
  end

  state.log("INFO", string.format("Executing dependency '%s' via curl", dep_req.name))

  local blocks = describe.describe_content(dep_block_text, file)
  if not blocks or #blocks == 0 then
    state.log("WARN", string.format("Failed to parse dependency '%s' block", dep_req.name))
    vim.schedule(function() on_complete(nil) end)
    return
  end
  local meta = blocks[1]
  local method = meta.method or "GET"
  local url = meta.path or ""
  local headers = meta.headers or {}
  local body = meta.body or ""

  if not url or url == "" then
    state.log("WARN", string.format("Dependency '%s' has no URL", dep_req.name))
    vim.schedule(function() on_complete(nil) end)
    return
  end

  local dep_lines = vim.split(dep_block_text, "\n", { plain = true })
  local resolver = vars.build_resolver_from_state({
    lines = dep_lines,
    file_path = file,
    block_start = 1,
    block_end = #dep_lines,
    env_name = env_name,
  })

  url = resolver:substitute(url)
  local resolved_headers = {}
  for _, h in ipairs(headers) do
    table.insert(resolved_headers, { h[1], resolver:substitute(h[2]) })
  end
  if body ~= "" then
    body = resolver:substitute(body)
  end

  local buf_dir = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()

  curl_exec.execute({
    method = method,
    url = url,
    headers = resolved_headers,
    body = body,
    buf_dir = buf_dir,
  }, function(response)
    if response.error then
      state.log("WARN", string.format("Dependency '%s' failed: %s", dep_req.name, response.error))
      on_complete(nil)
      return
    end
    request_response_cache[dep_req.name] = response
    response.request_name = dep_req.name
    state.log("INFO", string.format("Cached response for '%s'", dep_req.name))
    on_complete(response)
  end)
end

local function build_dep_order(refs, requests, content)
  local order = {}
  local seen = {}

  local function collect(dep_req)
    if seen[dep_req.name] or request_response_cache[dep_req.name] then
      return
    end
    seen[dep_req.name] = true

    local all_lines = vim.split(content, "\n", { plain = true })
    local dep_lines = {}
    for i = dep_req.start_line, dep_req.end_line do
      table.insert(dep_lines, all_lines[i] or "")
    end
    local dep_block_text = table.concat(dep_lines, "\n")
    local dep_refs = find_request_variable_refs(dep_block_text)

    for _, ref in ipairs(dep_refs) do
      if not seen[ref.request_name] and not request_response_cache[ref.request_name] then
        for _, req in ipairs(requests) do
          if req.name == ref.request_name then
            collect(req)
            break
          end
        end
      end
    end

    table.insert(order, dep_req)
  end

  for _, ref in ipairs(refs) do
    if not request_response_cache[ref.request_name] then
      for _, req in ipairs(requests) do
        if req.name == ref.request_name then
          collect(req)
          break
        end
      end
    end
  end

  return order
end

local function execute_deps_sequential(buf, file, env_name, dep_order, content, requests, idx, on_complete)
  idx = idx or 1
  if idx > #dep_order then
    on_complete()
    return
  end

  local dep_req = dep_order[idx]

  local all_lines = vim.split(content, "\n", { plain = true })
  local dep_lines = {}
  for i = dep_req.start_line, dep_req.end_line do
    table.insert(dep_lines, all_lines[i] or "")
  end
  local dep_block_text = table.concat(dep_lines, "\n")
  local dep_refs = find_request_variable_refs(dep_block_text)

  local resolved_dep_block = dep_block_text
  for _, ref in ipairs(dep_refs) do
    local value = resolve_request_variable(ref.full:sub(3, -3), request_response_cache)
    if value then
      resolved_dep_block = resolved_dep_block:gsub(vim.pesc(ref.full), tostring(value))
    end
  end

  local resolved_lines = vim.split(resolved_dep_block, "\n", { plain = true })
  for i, line in ipairs(resolved_lines) do
    all_lines[dep_req.start_line + i - 1] = line
  end
  local resolved_content = table.concat(all_lines, "\n")

  execute_dependent_request_async(buf, file, env_name, dep_req, resolved_dep_block, function(_response)
    execute_deps_sequential(buf, file, env_name, dep_order, content, requests, idx + 1, on_complete)
  end)
end

function M.cache_response(req_name, response)
  if req_name then
    request_response_cache[req_name] = response
  end
end

function M.is_response_cached(name)
  return request_response_cache[name] ~= nil
end

function M.collect_requests_from_content(content)
  local requests = {}
  local lines = vim.split(content, "\n", { plain = true })
  local i = 1
  while i <= #lines do
    local name = lines[i]:match("^%s*###%s+(%S.*)$")
    if name then
      name = vim.trim(name)
      local start_line = i
      local end_line = #lines
      for j = i + 1, #lines do
        if lines[j]:match("^%s*###") then
          end_line = j - 1
          break
        end
      end
      table.insert(requests, { name = name, start_line = start_line, end_line = end_line })
    end
    i = i + 1
  end
  return requests
end

local function resolve_request_variables_impl(buf, file, env_name, cursor_line, content, on_complete, deps)
  deps = deps or {}
  local collect_requests = deps.collect_requests
  local handle_prompt = deps.handle_prompt or handle_prompt_fn

  _chain_dep_set = {}
  _chain_dep_order = {}

  local requests = collect_requests(buf)

  local current_req = nil
  for _, req in ipairs(requests) do
    if cursor_line >= req.start_line and cursor_line <= req.end_line then
      current_req = req
      break
    end
  end

  if not current_req then
    on_complete(content)
    return
  end

  local all_lines = vim.split(content, "\n", { plain = true })
  local block_lines = {}
  for i = current_req.start_line, current_req.end_line do
    table.insert(block_lines, all_lines[i] or "")
  end
  local block_text = table.concat(block_lines, "\n")

  local refs = find_request_variable_refs(block_text)
  if #refs == 0 then
    on_complete(content)
    return
  end

  state.log("INFO", string.format("Found %d request variable reference(s)", #refs))

  local pending_deps = {}
  for _, ref in ipairs(refs) do
    if request_response_cache[ref.request_name] then
    else
      for _, req in ipairs(requests) do
        if req.name == ref.request_name then
          table.insert(pending_deps, req)
          break
        end
      end
    end
  end

  local function substitute_and_finish()
    local resolved_block = block_text
    for _, ref in ipairs(refs) do
      local value = resolve_request_variable(ref.full:sub(3, -3), request_response_cache)
      if value then
        resolved_block = resolved_block:gsub(vim.pesc(ref.full), tostring(value))
      else
        state.log("WARN", string.format("Could not resolve variable: %s", ref.full))
      end
    end
    local result_lines = {}
    local resolved_split = vim.split(resolved_block, "\n", { plain = true })
    for i, l in ipairs(all_lines) do
      if i >= current_req.start_line and i <= current_req.end_line then
        table.insert(result_lines, resolved_split[i - current_req.start_line + 1] or l)
      else
        table.insert(result_lines, l)
      end
    end
    return table.concat(result_lines, "\n")
  end

  if #pending_deps == 0 then
    on_complete(substitute_and_finish())
    return
  end

  local dep_idx = 1
  local function execute_next_dep()
    if dep_idx > #pending_deps then
      table.sort(_chain_dep_order, function(a, b) return a.depth > b.depth end)
      M._dep_chain = {}
      for _, entry in ipairs(_chain_dep_order) do
        local resp = request_response_cache[entry.name]
        if resp then
          table.insert(M._dep_chain, {name = entry.name, response = resp})
        end
      end
      on_complete(substitute_and_finish())
      return
    end

    local dep_req = pending_deps[dep_idx]
    dep_idx = dep_idx + 1

    if not _chain_dep_set[dep_req.name] then
      _chain_dep_set[dep_req.name] = true
      table.insert(_chain_dep_order, { name = dep_req.name, depth = 0 })
    end

    state.log("INFO", string.format("Auto-executing dependency '%s'", dep_req.name))

    local dep_raw_lines = {}
    for i = dep_req.start_line, dep_req.end_line do
      table.insert(dep_raw_lines, all_lines[i] or "")
    end
    local dep_raw_text = table.concat(dep_raw_lines, "\n")
    local has_prompts = dep_raw_text:match("<<[%a_][%w_]")

    local function do_execute(resolved_content)
      if not resolved_content then resolved_content = content end
      local resolved_lines = vim.split(resolved_content, "\n", { plain = true })
      local dep_lines = {}
      for i = dep_req.start_line, dep_req.end_line do
        table.insert(dep_lines, resolved_lines[i] or "")
      end
      local dep_block_text = table.concat(dep_lines, "\n")

      execute_dependent_request_async(buf, file, env_name, dep_req, dep_block_text, function(response)
        if response then
          state.log("INFO", string.format("Dependency '%s' executed and cached", dep_req.name))
        else
          state.log("WARN", string.format("Dependency '%s' failed to execute", dep_req.name))
        end
        execute_next_dep()
      end)
    end

    local function after_subdep_resolve(subdep_resolved)
      if not subdep_resolved then subdep_resolved = content end
      if has_prompts and handle_prompt then
        handle_prompt(buf, dep_req.start_line, subdep_resolved, file, env_name, function(prompt_resolved)
          if not prompt_resolved then
            state.log("WARN", string.format("Dependency '%s' prompt cancelled, skipping", dep_req.name))
            execute_next_dep()
            return
          end
          do_execute(prompt_resolved)
        end)
      else
        do_execute(subdep_resolved)
      end
    end

    resolve_content_dependencies_impl(buf, file, env_name, content, dep_req.start_line, after_subdep_resolve, 1, deps)
  end

  execute_next_dep()
end

local function resolve_content_dependencies_impl(buf, file_path, env_name, content, block_line, on_complete, _depth, deps)
  deps = deps or {}
  local handle_prompt = deps.handle_prompt or handle_prompt_fn

  _depth = _depth or 0
  if _depth > 10 then
    state.log("ERROR", string.format("Max dependency depth (10) reached at block line %d, aborting resolution", block_line))
    on_complete(content)
    return
  end

  local requests = M.collect_requests_from_content(content)

  local lines = vim.split(content, "\n", { plain = true })
  local block_end = #lines
  for i = block_line + 1, #lines do
    if lines[i]:match("^%s*###") then
      block_end = i - 1
      break
    end
  end
  local block_lines = {}
  for i = block_line, block_end do
    table.insert(block_lines, lines[i] or "")
  end
  local block_text = table.concat(block_lines, "\n")

  local refs = find_request_variable_refs(block_text)
  local dyn_refs = find_dynamic_prompt_refs(block_text)
  for _, dr in ipairs(dyn_refs) do
    local found = false
    for _, r in ipairs(refs) do
      if r.request_name == dr.request_name then
        found = true
        break
      end
    end
    if not found then
      table.insert(refs, dr)
    end
  end
  if #refs == 0 then
    on_complete(content)
    return
  end

  state.log("INFO", string.format("Found %d request variable reference(s) in target block (depth %d)", #refs, _depth))

  local pending_deps = {}
  for _, ref in ipairs(refs) do
    if request_response_cache[ref.request_name] then
    else
      for _, req in ipairs(requests) do
        if req.name == ref.request_name then
          table.insert(pending_deps, req)
          break
        end
      end
    end
  end

  local function substitute_and_finish()
    local resolved_block = block_text
    local all_resolved = true
    for _, ref in ipairs(refs) do
      local value = resolve_request_variable(ref.full:sub(3, -3), request_response_cache)
      if value then
        resolved_block = resolved_block:gsub(vim.pesc(ref.full), tostring(value))
      else
        state.log("WARN", string.format("Could not resolve variable: %s — value may be missing from the response", ref.full))
        all_resolved = false
      end
    end
    local result_lines = {}
    local resolved_split = vim.split(resolved_block, "\n", { plain = true })
    for i, l in ipairs(lines) do
      if i >= block_line and i <= block_end then
        table.insert(result_lines, resolved_split[i - block_line + 1] or l)
      else
        table.insert(result_lines, l)
      end
    end
    return table.concat(result_lines, "\n")
  end

  if #pending_deps == 0 then
    on_complete(substitute_and_finish())
    return
  end

  local dep_idx = 1
  local function execute_next_dep()
    if dep_idx > #pending_deps then
      table.sort(_chain_dep_order, function(a, b) return a.depth > b.depth end)
      M._dep_chain = {}
      for _, entry in ipairs(_chain_dep_order) do
        local resp = request_response_cache[entry.name]
        if resp then
          table.insert(M._dep_chain, {name = entry.name, response = resp})
        end
      end
      on_complete(substitute_and_finish())
      return
    end

    local dep_req = pending_deps[dep_idx]
    dep_idx = dep_idx + 1

    if not _chain_dep_set[dep_req.name] then
      _chain_dep_set[dep_req.name] = true
      table.insert(_chain_dep_order, { name = dep_req.name, depth = _depth })
    end

    state.log("INFO", string.format("Resolving dependency '%s' (depth %d)", dep_req.name, _depth))

    local function do_execute(resolved_content)
      if not resolved_content then resolved_content = content end
      local resolved_lines = vim.split(resolved_content, "\n", { plain = true })
      local dep_lines = {}
      for i = dep_req.start_line, dep_req.end_line do
        table.insert(dep_lines, resolved_lines[i] or "")
      end
      local dep_block_text = table.concat(dep_lines, "\n")

      local has_prompts = dep_block_text:match("<<[%a_][%w_]")

      if has_prompts and handle_prompt then
        handle_prompt(buf, dep_req.start_line, resolved_content, file_path, env_name, function(prompt_resolved)
          if not prompt_resolved then
            state.log("WARN", string.format("Dependency '%s' prompt cancelled, skipping", dep_req.name))
            execute_next_dep()
            return
          end
          local prompt_lines = vim.split(prompt_resolved, "\n", { plain = true })
          local dep_lines2 = {}
          for i = dep_req.start_line, dep_req.end_line do
            table.insert(dep_lines2, prompt_lines[i] or "")
          end
          local dep_block_text2 = table.concat(dep_lines2, "\n")
          execute_dependent_request_async(buf, file_path, env_name, dep_req, dep_block_text2, function(response)
            if response then
              state.log("INFO", string.format("Dependency '%s' executed and cached", dep_req.name))
            else
              state.log("WARN", string.format("Dependency '%s' failed to execute", dep_req.name))
            end
            execute_next_dep()
          end)
        end)
      else
        execute_dependent_request_async(buf, file_path, env_name, dep_req, dep_block_text, function(response)
          if response then
            state.log("INFO", string.format("Dependency '%s' executed and cached", dep_req.name))
          else
            state.log("WARN", string.format("Dependency '%s' failed to execute", dep_req.name))
          end
          execute_next_dep()
        end)
      end
    end

    resolve_content_dependencies_impl(buf, file_path, env_name, content, dep_req.start_line, do_execute, _depth + 1, deps)
  end

  execute_next_dep()
end

M._dep_chain = nil
M._resolve_request_variable = resolve_request_variable

M._test = {
  find_request_variable_refs = find_request_variable_refs,
  find_dynamic_prompt_refs = find_dynamic_prompt_refs,
  collect_requests_from_content = M.collect_requests_from_content,
  execute_dependent_request_async = execute_dependent_request_async,
}

M._resolve_request_variables_impl = resolve_request_variables_impl
M._resolve_content_dependencies_impl = resolve_content_dependencies_impl

function M.resolve_request_variables(buf, file, env_name, cursor_line, content, on_complete, deps)
  resolve_request_variables_impl(buf, file, env_name, cursor_line, content, on_complete, deps)
end

function M.resolve_content_dependencies(buf, file_path, env_name, content, block_line, on_complete, deps)
  resolve_content_dependencies_impl(buf, file_path, env_name, content, block_line, on_complete, nil, deps)
end

return M