local M = {}
local import_parser = require("poste_http.http.import_parser")

local function read_spec(path)
  local fd = io.open(path, "r")
  if not fd then return nil, "Cannot read file: " .. path end
  local content = fd:read("*a")
  fd:close()
  local ok, spec = pcall(vim.json.decode, content)
  if not ok then return nil, "Invalid JSON: " .. tostring(spec) end
  return spec, nil
end

local function parse_servers(spec)
  local servers = spec.servers or {}
  return servers
end

local function build_url(server_url, path)
  local base = server_url or ""
  if base:sub(-1) == "/" then
    base = base:sub(1, -2)
  end
  local clean_path = path or ""
  if clean_path:sub(1, 1) ~= "/" then
    clean_path = "/" .. clean_path
  end
  return "{{base_url}}" .. clean_path
end

local function parse_request_body(operation, spec)
  if not operation.requestBody then return "" end
  local content = operation.requestBody.content or {}
  local json_content = content["application/json"]
  if json_content and json_content.schema then
    local example = import_parser.schema_to_example(json_content.schema, spec)
    if example and example ~= "{}" then
      return example
    end
  end
  return ""
end

local function parse_operation(path, method, operation, spec, server_url)
  local name = (operation.summary or operation.operationId or (method:upper() .. " " .. path))
  local url = build_url(server_url, path)
  local headers = {}
  local body = ""

  local auth = import_parser.extract_auth_header(spec)
  if auth then
    table.insert(headers, auth)
  end

  local api_params = operation.parameters or {}
  local path_params = spec.paths and spec.paths[path] and spec.paths[path].parameters or {}
  local all_params = {}
  for _, p in ipairs(api_params) do table.insert(all_params, p) end
  for _, p in ipairs(path_params) do
    local found = false
    for _, ap in ipairs(all_params) do
      if ap.name == p.name and ap["in"] == p["in"] then found = true break end
    end
    if not found then table.insert(all_params, p) end
  end

  local hdrs, qs, vars = import_parser.collect_parameters(all_params, {}, spec)
  for _, h in ipairs(hdrs) do table.insert(headers, h) end
  if #qs > 0 then
    url = url .. "?" .. table.concat(qs, "&")
  end

  if method:lower() == "post" or method:lower() == "put" or method:lower() == "patch" then
    body = parse_request_body(operation, spec)
  end

  return import_parser.generate_http_block(name, method:upper(), url, headers, body)
end

function M.import_spec(spec_path, out_dir)
  local spec, err = read_spec(spec_path)
  if not spec then return nil, err end

  if spec.openapi == nil then
    return nil, "Not an OpenAPI 3.x spec (missing 'openapi' field)"
  end

  local servers = parse_servers(spec)
  local server_url = (#servers > 0 and servers[1].url) or "http://localhost"

  local title = (spec.info and spec.info.title) or "api"
  local filename = title:lower():gsub("%s+", "_"):gsub("[^%w_]", "") .. ".http"

  local file_vars = {}
  table.insert(file_vars, { name = "base_url", value = server_url })

  local auth = import_parser.extract_auth_header(spec)
  if auth then
    table.insert(file_vars, { name = "token", value = "your-token-here" })
  end

  local blocks = {}
  local paths = spec.paths or {}
  for path, path_item in pairs(paths) do
    local methods = { "get", "post", "put", "patch", "delete", "options", "head", "trace" }
    for _, method in ipairs(methods) do
      local operation = path_item[method]
      if operation then
        local block = parse_operation(path, method, operation, spec, server_url)
        if block then
          table.insert(blocks, block)
        end
      end
    end
  end

  local file_vars_str = import_parser.generate_file_vars(file_vars)
  local http_content = file_vars_str .. table.concat(blocks, "\n")
  local env_vars = {}
  env_vars["base_url"] = server_url
  local env_json = import_parser.generate_env_json("dev", env_vars)

  import_parser.write_output(out_dir, http_content, env_json, filename)

  return { filename = filename, block_count = #blocks }
end

function M.run()
  local ok, finder = pcall(require, "finder")
  if not ok then
    vim.notify("beyondlex/finder plugin required for file selection", vim.log.levels.ERROR)
    return
  end
  finder.open({
    mode = "both",
    initial_path = vim.fn.getcwd(),
    extensions = { "json", "yaml", "yml" },
    on_confirm = function(spec_path)
      if not spec_path then return end
      local default_dir = vim.fn.fnamemodify(spec_path, ":h")
      vim.schedule(function()
        finder.open({
          mode = "dir",
          initial_path = default_dir,
          title = " Select output directory ",
          on_confirm = function(out_dir)
            if not out_dir then return end
            local result, err = M.import_spec(spec_path, out_dir)
            if result then
              vim.notify(string.format("OpenAPI import: %d blocks → %s/%s",
                result.block_count, out_dir, result.filename),
                vim.log.levels.INFO, { title = "Import OpenAPI" })
            else
              vim.notify("OpenAPI import failed: " .. (err or "unknown"),
                vim.log.levels.ERROR, { title = "Import OpenAPI" })
            end
          end,
          on_cancel = function() end,
        })
      end)
    end,
    on_cancel = function() end,
  })
end

return M