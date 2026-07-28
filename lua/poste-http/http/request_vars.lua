local state = require("poste-http.state")
local cache = require("poste-http.http.cache")
local form_data = require("poste-http.http.form_data")
local jq_mapping = require("poste-http.http.jq_mapping")
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
    execute_dep = request_deps._test.execute_dependent_request_async,
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

M._dep_chain = request_deps._dep_chain

M._handle_prompt_variables_impl = handle_prompt_variables_impl
M._resolve_request_variables_impl = request_deps._resolve_request_variables_impl
M._resolve_content_dependencies_impl = request_deps._resolve_content_dependencies_impl

M._test = {
  parse_structured_options = jq_mapping.parse_structured_options,
  parse_dynamic_mapping    = jq_mapping.parse_dynamic_mapping,
  apply_jq_mapping         = jq_mapping.apply_jq_mapping,
  find_request_variable_refs = request_deps._test.find_request_variable_refs,
  find_dynamic_prompt_refs = request_deps._test.find_dynamic_prompt_refs,
  collect_requests_from_content = request_deps._test.collect_requests_from_content,
  execute_dependent_request_async = request_deps._test.execute_dependent_request_async,
}

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