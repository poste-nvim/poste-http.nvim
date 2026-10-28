local M = {}
local import_parser = require("poste-http.http.import_parser")

local function parse_servers(spec)
  local servers = spec.servers or {}
  return servers
end

-- server_url is accepted for signature parity with import_swagger; the
-- host is deliberately swapped for the {{base_url}} env variable.
local function build_url(server_url, path)
  local clean_path = path or ""
  if clean_path:sub(1, 1) ~= "/" then
    clean_path = "/" .. clean_path
  end
  -- Replace OpenAPI path params {param} with HTTP variable syntax {{param}}
  clean_path = clean_path:gsub("{([^}]+)}", "{{%1}}")
  return "{{base_url}}" .. clean_path
end

local function parse_request_body(operation, spec)
  local rb = operation.requestBody
  if not rb then return "" end
  -- Real specs commonly reference a shared body:
  -- "requestBody": {"$ref": "#/components/requestBodies/Pet"}. Without
  -- dereferencing, `.content` was nil and the request body was silently
  -- dropped (the parameters path already resolves its schemas).
  rb = import_parser.resolve_schema(rb, spec)
  if type(rb) ~= "table" then return "" end
  local content = rb.content
  if type(content) ~= "table" then return "" end
  local json_content = content["application/json"]
  if json_content and json_content.schema then
    local example = import_parser.schema_to_example(json_content.schema, spec)
    if type(example) == "table" and next(example) then
      return vim.json.encode(example)
    end
  end
  return ""
end

local function parse_operation(path, method, operation, spec, server_url)
  local name = (operation.summary or operation.operationId or (method:upper() .. " " .. path))
  local url = build_url(server_url, path)
  local headers = {}
  local body = ""
  local op_vars = {}

  local auth = import_parser.extract_auth_header(spec)
  if auth then
    table.insert(headers, auth)
  end

  local api_params = type(operation.parameters) == "table" and operation.parameters or {}
  local path_params = {}
  if type(spec.paths) == "table" and type(spec.paths[path]) == "table"
    and type(spec.paths[path].parameters) == "table" then
    path_params = spec.paths[path].parameters
  end
  local all_params = {}
  for _, p in ipairs(api_params) do table.insert(all_params, p) end
  for _, p in ipairs(path_params) do
    local found = false
    for _, ap in ipairs(all_params) do
      if ap.name == p.name and ap["in"] == p["in"] then found = true break end
    end
    if not found then table.insert(all_params, p) end
  end

  local hdrs, qs, vars, _, prompts = import_parser.collect_parameters(all_params, {}, spec)
  for _, h in ipairs(hdrs) do table.insert(headers, h) end
  for _, v in ipairs(vars) do
    if not op_vars[v.name] then
      op_vars[v.name] = v.value
    end
  end
  if #qs > 0 then
    url = url .. "?" .. table.concat(qs, "&")
  end

  if method:lower() == "post" or method:lower() == "put" or method:lower() == "patch" then
    body = parse_request_body(operation, spec)
  end

  return import_parser.generate_http_block(name, method:upper(), url, headers, body, prompts), op_vars
end

function M.import_spec(spec_path, out_dir)
  local spec, err = import_parser.read_spec(spec_path)
  if not spec then return nil, err end

  if spec.openapi == nil then
    return nil, "Not an OpenAPI 3.x spec (missing 'openapi' field)"
  end

  -- Drifted specs can carry servers as a scalar or a list of scalars; a
  -- bare `#servers > 0` reads a string's length and then indexes nil.
  local servers = parse_servers(spec)
  local server_url = "http://localhost"
  if type(servers) == "table" and type(servers[1]) == "table"
    and type(servers[1].url) == "string" then
    server_url = servers[1].url
  end

  local title = (spec.info and spec.info.title) or "api"
  local filename = import_parser.make_filename(title)

  local file_vars = {}
  table.insert(file_vars, { name = "base_url", value = server_url })

  local auth = import_parser.extract_auth_header(spec)
  if auth then
    table.insert(file_vars, { name = "token", value = "your-token-here" })
  end

  local blocks = {}
  local all_op_vars = {}
  local paths = spec.paths or {}
  -- Sorted path order: the generated file is committed and reviewed, so its
  -- block order must be a pure function of the spec — pairs() hash order
  -- differs between runs and nvim sessions.
  local sorted_paths = {}
  for path in pairs(paths) do
    table.insert(sorted_paths, path)
  end
  table.sort(sorted_paths)
  for _, path in ipairs(sorted_paths) do
    local path_item = paths[path]
    -- Malformed specs may carry a non-table path item (a number, string, or
    -- JSON null); skip it instead of erroring mid-import.
    if type(path_item) == "table" then
      local methods = { "get", "post", "put", "patch", "delete", "options", "head", "trace" }
      for _, method in ipairs(methods) do
        local operation = path_item[method]
        if type(operation) == "table" then
          local block, op_vars = parse_operation(path, method, operation, spec, server_url)
          if block then
            table.insert(blocks, block)
            for k, v in pairs(op_vars) do
              all_op_vars[k] = v
            end
          end
        end
      end
    end
  end

  -- Add operation-level variables as file-level @var definitions, sorted:
  -- the generated file is committed and reviewed, so its order must be a
  -- pure function of the spec (pairs() hash order differs between runs).
  local op_var_names = {}
  for name in pairs(all_op_vars) do
    table.insert(op_var_names, name)
  end
  table.sort(op_var_names)
  for _, name in ipairs(op_var_names) do
    table.insert(file_vars, { name = name, value = all_op_vars[name] })
  end

  local file_vars_str = import_parser.generate_file_vars(file_vars)
  local http_content = file_vars_str .. table.concat(blocks, "\n")
  local env_vars = {}
  env_vars["base_url"] = server_url
  local env_json = import_parser.generate_env_json("dev", env_vars)

  local ok, write_err = import_parser.write_output(out_dir, http_content, env_json, filename)
  if not ok then
    return nil, write_err
  end

  return { filename = filename, block_count = #blocks }
end

function M.run()
  import_parser.run_importer({
    mode = "both",
    -- read_spec is JSON-only; advertising yaml/yml here would let the picker
    -- offer files the importer then rejects.
    extensions = { "json" },
    title = "OpenAPI",
    import_fn = function(spec_path, out_dir)
      return M.import_spec(spec_path, out_dir)
    end,
  })
end

return M