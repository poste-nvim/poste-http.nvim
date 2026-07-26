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

local function build_url(spec, path)
  local scheme = "https"
  if spec.schemes and #spec.schemes > 0 then
    scheme = spec.schemes[1]
  end
  local host = spec.host or "localhost"
  local base_path = spec.basePath or ""
  return "{{base_url}}" .. base_path .. path
end

local function parse_swagger_parameter(param, spec)
  local resolved = import_parser.resolve_schema(param, spec)
  if not resolved then return nil end
  return resolved
end

local function parse_operation(spec, path, method, operation)
  local name = operation.summary or operation.operationId or (method:upper() .. " " .. path)
  local url = build_url(spec, path)
  local headers = {}
  local body = ""

  local security_defs = spec.securityDefinitions or {}
  local security = operation.security or spec.security or {}
  for _, req in ipairs(security) do
    for name, _ in pairs(req) do
      local def = security_defs[name]
      if def then
        if def.type == "apiKey" and def["in"] == "header" then
          table.insert(headers, { key = def.name or "X-API-Key", value = "{{api_key}}" })
        elseif def.type == "basic" then
          table.insert(headers, { key = "Authorization", value = "Basic {{credentials}}" })
        end
      end
    end
  end

  local params = operation.parameters or {}
  local query_parts = {}
  for _, p in ipairs(params) do
    local resolved = parse_swagger_parameter(p, spec)
    if resolved then
      if resolved["in"] == "header" then
        table.insert(headers, { key = resolved.name, value = "{{" .. resolved.name .. "}}" })
      elseif resolved["in"] == "query" then
        local example = resolved["x-example"] or (resolved.type == "string" and "string" or "0")
        table.insert(query_parts, resolved.name .. "=" .. example)
      end
    end
  end

  if #query_parts > 0 then
    url = url .. "?" .. table.concat(query_parts, "&")
  end

  if (method:lower() == "post" or method:lower() == "put" or method:lower() == "patch") and operation.parameters then
    local body_param = nil
    for _, p in ipairs(operation.parameters) do
      if p["in"] == "body" then
        body_param = p
        break
      end
    end
    if body_param and body_param.schema then
      body = import_parser.schema_to_example(body_param.schema, spec)
    end
  end

  return import_parser.generate_http_block(name, method:upper(), url, headers, body)
end

function M.import_spec(spec_path, out_dir)
  local spec, err = read_spec(spec_path)
  if not spec then return nil, err end

  if spec.swagger == nil then
    return nil, "Not a Swagger 2.0 spec (missing 'swagger' field)"
  end

  local title = (spec.info and spec.info.title) or "api"
  local filename = title:lower():gsub("%s+", "_"):gsub("[^%w_]", "") .. ".http"

  local scheme = "https"
  if spec.schemes and #spec.schemes > 0 then
    scheme = spec.schemes[1]
  end
  local host = spec.host or "localhost"
  local base_path = spec.basePath or ""
  local base_url = scheme .. "://" .. host .. base_path

  local file_vars = {}
  table.insert(file_vars, { name = "base_url", value = base_url })

  local blocks = {}
  local paths = spec.paths or {}
  for path, path_item in pairs(paths) do
    local methods = { "get", "post", "put", "patch", "delete", "options", "head", "trace" }
    for _, method in ipairs(methods) do
      local operation = path_item[method]
      if operation then
        local block = parse_operation(spec, path, method, operation)
        if block then
          table.insert(blocks, block)
        end
      end
    end
  end

  local file_vars_str = import_parser.generate_file_vars(file_vars)
  local http_content = file_vars_str .. table.concat(blocks, "\n")
  local env_vars = {}
  env_vars["base_url"] = base_url
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
    mode = "file",
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
              vim.notify(string.format("Swagger import: %d blocks → %s/%s",
                result.block_count, out_dir, result.filename),
                vim.log.levels.INFO, { title = "Import Swagger" })
            else
              vim.notify("Swagger import failed: " .. (err or "unknown"),
                vim.log.levels.ERROR, { title = "Import Swagger" })
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