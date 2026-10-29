local M = {}
local import_parser = require("poste-http.http.import_parser")

-- spec.schemes/spec.host are read by the exporter but deliberately NOT
-- baked into the generated URL: the host is swapped for {{base_url}}.
local function build_url(spec, path)
  local base_path = spec.basePath or ""
  return "{{base_url}}" .. base_path .. path
end

local function parse_operation(spec, path, method, operation)
  local name = operation.summary or operation.operationId or (method:upper() .. " " .. path)
  local url = build_url(spec, path)
  local headers = {}
  local body = ""

  local security_defs = spec.securityDefinitions
  if type(security_defs) ~= "table" then security_defs = {} end
  local security = operation.security or spec.security
  if type(security) ~= "table" then security = {} end
  for _, req in ipairs(security) do
    if type(req) == "table" then
      for sec_name, _ in pairs(req) do
        local def = security_defs[sec_name]
        if type(def) == "table" then
          if def.type == "apiKey" and def["in"] == "header" then
            table.insert(headers, { key = def.name or "X-API-Key", value = "{{api_key}}" })
          elseif def.type == "basic" then
            table.insert(headers, { key = "Authorization", value = "Basic {{credentials}}" })
          end
        end
      end
    end
  end

  local params = operation.parameters
  if type(params) ~= "table" then params = {} end
  local query_parts = {}
  for _, p in ipairs(params) do
    if type(p) == "table" then
      local resolved = import_parser.resolve_schema(p, spec)
      -- Hand-edited specs can omit `name` ({"in": "header"}) or give
      -- x-example a table; both used to raise on the concatenations below.
      -- Every other malformed shape in this module is guarded the same way.
      if resolved and type(resolved.name) == "string" and resolved.name ~= "" then
        if resolved["in"] == "header" then
          table.insert(headers, { key = resolved.name, value = "{{" .. resolved.name .. "}}" })
        elseif resolved["in"] == "query" then
          local example = resolved["x-example"]
          if type(example) ~= "string" and type(example) ~= "number" then
            example = (resolved.type == "string" and "string" or "0")
          end
          table.insert(query_parts, resolved.name .. "=" .. tostring(example))
        end
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
      local example = import_parser.schema_to_example(body_param.schema, spec)
      body = type(example) == "table" and vim.json.encode(example) or tostring(example)
    end
  end

  return import_parser.generate_http_block(name, method:upper(), url, headers, body)
end

function M.import_spec(spec_path, out_dir)
  local spec, err = import_parser.read_spec(spec_path)
  if not spec then return nil, err end

  if spec.swagger == nil then
    return nil, "Not a Swagger 2.0 spec (missing 'swagger' field)"
  end

  local title = (spec.info and spec.info.title) or "api"
  local filename = import_parser.make_filename(title)

  local scheme = "https"
  if type(spec.schemes) == "table" and type(spec.schemes[1]) == "string" then
    scheme = spec.schemes[1]
  end
  local host = spec.host or "localhost"
  local base_path = spec.basePath or ""
  local base_url = scheme .. "://" .. host .. base_path

  local file_vars = {}
  table.insert(file_vars, { name = "base_url", value = base_url })

  local blocks = {}
  local paths = spec.paths
  -- Same total-shape rule as the rest of this module: a hand-edited
  -- spec may carry a scalar (or null) paths map; ipairs/pairs on one
  -- crashes the import instead of producing an empty file.
  if type(paths) ~= "table" then paths = {} end
  -- Sorted path order + table-only path items: same rules as import_openapi
  -- (deterministic, reviewable output; malformed specs skip, not crash).
  local sorted_paths = {}
  for path in pairs(paths) do
    table.insert(sorted_paths, path)
  end
  table.sort(sorted_paths)
  for _, path in ipairs(sorted_paths) do
    local path_item = paths[path]
    if type(path_item) == "table" then
      local methods = { "get", "post", "put", "patch", "delete", "options", "head", "trace" }
      for _, method in ipairs(methods) do
        local operation = path_item[method]
        if type(operation) == "table" then
          local block = parse_operation(spec, path, method, operation)
          if block then
            table.insert(blocks, block)
          end
        end
      end
    end
  end

  local file_vars_str = import_parser.generate_file_vars(file_vars)
  local http_content = file_vars_str .. table.concat(blocks, "\n")
  local env_vars = {}
  env_vars["base_url"] = base_url
  local env_json = import_parser.generate_env_json("dev", env_vars)

  local ok, write_err = import_parser.write_output(out_dir, http_content, env_json, filename)
  if not ok then
    return nil, write_err
  end

  return { filename = filename, block_count = #blocks }
end

function M.run()
  import_parser.run_importer({
    mode = "file",
    -- read_spec is JSON-only; advertising yaml/yml here would let the picker
    -- offer files the importer then rejects.
    extensions = { "json" },
    title = "Swagger",
    import_fn = function(spec_path, out_dir)
      return M.import_spec(spec_path, out_dir)
    end,
  })
end

return M