local cache = require("poste-http.http.cache")
local form_data = require("poste-http.http.form_data")
local prompt_vars = require("poste-http.http.prompt_vars")
local request_deps = require("poste-http.http.request_deps")

local M = {}

function M.process_form_data(src_buf, cursor_line, content)
  return form_data.process_form_data(src_buf, cursor_line, content)
end

function M.collect_requests(buf)
  local bc = cache.get_buffer_cache(buf)
  local requests = {}
  for _, block in ipairs(bc.blocks or {}) do
    table.insert(requests, {
      name = block.name or "",
      start_line = block.start_line,
      end_line = block.end_line,
    })
  end
  return requests
end

local function handle_prompt_variables_impl(buf, cursor_line, content, file, env_name, on_complete)
  prompt_vars.handle_prompt_variables(buf, cursor_line, content, file, env_name, on_complete, {
    execute_dep = request_deps.execute_dependent_request_async,
    resolve_req_var = request_deps._resolve_request_variable,
    collect_requests = M.collect_requests,
  })
end

request_deps.set_prompt_handler(handle_prompt_variables_impl)

function M.cache_response(req_name, response)
  request_deps.cache_response(req_name, response)
end

function M.is_response_cached(name)
  return request_deps.is_response_cached(name)
end

function M.collect_requests_from_content(content)
  return request_deps.collect_requests_from_content(content)
end

M.find_request_variable_refs = request_deps.find_request_variable_refs
M.find_dynamic_prompt_refs = request_deps.find_dynamic_prompt_refs

function M.get_dep_chain()
  return request_deps._dep_chain
end

function M.clear_dep_chain()
  request_deps._dep_chain = nil
end

M._handle_prompt_variables_impl = handle_prompt_variables_impl
M._resolve_request_variables_impl = request_deps._resolve_request_variables_impl
M._resolve_content_dependencies_impl = request_deps._resolve_content_dependencies_impl

function M.handle_prompt_variables(...)
  return handle_prompt_variables_impl(...)
end

function M.resolve_request_variables(buf, file, env_name, cursor_line, content, on_complete)
  request_deps.resolve_request_variables(buf, file, env_name, cursor_line, content, on_complete, {
    collect_requests = M.collect_requests,
    handle_prompt = handle_prompt_variables_impl,
  })
end

function M.resolve_content_dependencies(buf, file_path, env_name, content, block_line, on_complete)
  request_deps.resolve_content_dependencies(buf, file_path, env_name, content, block_line, on_complete, {
    handle_prompt = handle_prompt_variables_impl,
  })
end

return M