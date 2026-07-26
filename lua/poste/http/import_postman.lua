local M = {}
local import_parser = require("poste.http.import_parser")

local function read_collection(path)
  local fd = io.open(path, "r")
  if not fd then return nil, "Cannot read file: " .. path end
  local content = fd:read("*a")
  fd:close()
  local ok, spec = pcall(vim.json.decode, content)
  if not ok then return nil, "Invalid JSON: " .. tostring(spec) end
  return spec, nil
end

local function resolve_postman_var(value, vars)
  if not value then return "" end
  if type(value) == "string" then
    return value:gsub("{{([^}]+)}}", function(name)
      return vars[name] or "{{" .. name .. "}}"
    end)
  end
  return tostring(value)
end

local function parse_url(request_url)
  if not request_url then return "", {} end
  if type(request_url) == "string" then
    return request_url, {}
  end
  local raw = request_url.raw or ""
  local query_parts = {}
  if request_url.query then
    for _, q in ipairs(request_url.query) do
      local key = q.key or ""
      local value = q.value or ""
      table.insert(query_parts, key .. "=" .. value)
    end
  end
  if #query_parts > 0 then
    return raw .. "?" .. table.concat(query_parts, "&"), query_parts
  end
  return raw, {}
end

local function parse_body(request_body)
  if not request_body then return "" end
  local mode = request_body.mode or ""
  if mode == "raw" then
    local raw = request_body.raw or ""
    local options = request_body.options or {}
    local lang = (options.raw and options.raw.language) or ""
    return raw
  elseif mode == "urlencoded" then
    local parts = {}
    for _, p in ipairs(request_body.urlencoded or {}) do
      table.insert(parts, (p.key or "") .. "=" .. (p.value or ""))
    end
    return table.concat(parts, "&")
  elseif mode == "formdata" then
    local parts = {}
    for _, p in ipairs(request_body.formdata or {}) do
      if p.type == "file" then
        table.insert(parts, "< " .. (p.src or ""))
      else
        table.insert(parts, (p.key or "") .. "=" .. (p.value or ""))
      end
    end
    return table.concat(parts, "\n")
  elseif mode == "file" then
    return "< " .. (request_body.file and request_body.file.src or "")
  end
  return ""
end

local function parse_item(item, vars, collection_vars)
  if not item then return nil end

  if item.item then
    local blocks = {}
    for _, sub in ipairs(item.item) do
      local result = parse_item(sub, vars, collection_vars)
      if result then
        for _, b in ipairs(result) do
          table.insert(blocks, b)
        end
      end
    end
    return blocks
  end

  if not item.request then return nil end

  local req = item.request
  local method = req.method or "GET"
  local name = item.name or (method .. " Request")

  local url, _ = parse_url(req.url)
  url = resolve_postman_var(url, vars)

  local headers = {}
  for _, h in ipairs(req.header or {}) do
    if h.key and h.key ~= "" then
      local value = resolve_postman_var(h.value, vars)
      table.insert(headers, { key = h.key, value = value })
    end
  end

  local body = parse_body(req.body)

  local block = import_parser.generate_http_block(name, method, url, headers, body)
  return { block }
end

local function collect_variables(collection)
  local vars = {}
  local collection_vars = collection.variable or {}
  for _, v in ipairs(collection_vars) do
    vars[v.key or v.name or ""] = v.value or ""
  end
  return vars
end

function M.import_spec(spec_path, out_dir)
  local collection, err = read_collection(spec_path)
  if not collection then return nil, err end

  if collection.info == nil then
    return nil, "Not a Postman Collection (missing 'info' field)"
  end

  local vars = collect_variables(collection)
  local title = (collection.info and collection.info.name) or "collection"
  local filename = title:lower():gsub("%s+", "_"):gsub("[^%w_]", "") .. ".http"

  local file_vars = {}
  for k, v in pairs(vars) do
    table.insert(file_vars, { name = k, value = v })
  end

  local blocks = {}
  local items = collection.item or {}
  for _, item in ipairs(items) do
    local result = parse_item(item, vars, vars)
    if result then
      for _, b in ipairs(result) do
        table.insert(blocks, b)
      end
    end
  end

  local file_vars_str = import_parser.generate_file_vars(file_vars)
  local http_content = file_vars_str .. table.concat(blocks, "\n")
  local env_vars = {}
  for k, v in pairs(vars) do
    env_vars[k] = v:gsub("^\"(.*)\"$", "%1")
  end
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
    extensions = { "json" },
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
              vim.notify(string.format("Postman import: %d blocks → %s/%s",
                result.block_count, out_dir, result.filename),
                vim.log.levels.INFO, { title = "Import Postman" })
            else
              vim.notify("Postman import failed: " .. (err or "unknown"),
                vim.log.levels.ERROR, { title = "Import Postman" })
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