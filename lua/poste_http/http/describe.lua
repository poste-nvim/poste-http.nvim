local state = require("poste_http.state")

local M = {}

local function get_node_text(node, source)
  local ok, sr, sc, er, ec = pcall(node.range, node)
  if not ok then return "" end
  local lines = vim.split(source, "\n", { plain = true })
  if sr == er then
    return lines[sr + 1]:sub(sc + 1, ec)
  end
  local parts = { lines[sr + 1]:sub(sc + 1) }
  for i = sr + 2, er do
    table.insert(parts, lines[i])
  end
  parts[#parts + 1] = lines[er + 1]:sub(1, ec)
  return table.concat(parts, "\n")
end

local function get_children_by_type(node, type_name)
  local results = {}
  for child in node:iter_children() do
    if child:type() == type_name then
      table.insert(results, child)
    end
  end
  return results
end

local function describe_via_treesitter(content)
  if not content or content == "" then
    return {}, nil
  end

  local ok, parser = pcall(vim.treesitter.get_string_parser, content, "poste_http")
  if not ok or not parser then
    return nil, "tree-sitter parser not available"
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return nil, "tree-sitter parse returned empty tree"
  end

  local root = trees[1]:root()
  local lines = vim.split(content, "\n", { plain = true })
  local line_count = #lines

  local blocks = {}
  local current_block = nil
  local block_count = 0

  local function finalize_block()
    if not current_block then return end
    local end_line = line_count
    for i = current_block._line + 1, line_count do
      if lines[i] and lines[i]:match("^###") then
        end_line = i - 1
        break
      end
    end
    current_block.end_line = end_line
    current_block.body = ""
    if current_block._body_text then
      current_block.body = current_block._body_text
    elseif current_block._request_line_row then
      local body_start = (current_block._last_header_row or current_block._request_line_row) + 1
      while body_start <= end_line do
        local line = lines[body_start]
        if line and line:match("%S") then
          break
        end
        body_start = body_start + 1
      end
      if body_start <= end_line then
        local first_line = lines[body_start]
        if first_line and not current_block._non_body_lines[body_start] then
          local body_parts = {}
          for i = body_start, end_line do
            if not current_block._non_body_lines[i] then
              table.insert(body_parts, lines[i])
            end
          end
          current_block.body = table.concat(body_parts, "\n")
        end
      end
    end
    current_block._line = nil
    current_block._request_line_row = nil
    current_block._last_header_row = nil
    current_block._body_text = nil
    current_block._non_body_lines = nil
    table.insert(blocks, current_block)
    current_block = nil
  end

  for child in root:iter_children() do
    local type = child:type()
    local sr, sc, er, ec = child:range()
    local line_num = sr + 1

    if type == "request_block" then
      finalize_block()
      block_count = block_count + 1
      local name_nodes = get_children_by_type(child, "request_name")
      local name = ""
      if #name_nodes > 0 then
        name = get_node_text(name_nodes[1], content)
      end
      current_block = {
        name = vim.trim(name),
        line = line_num,
        end_line = line_count,
        method = "",
        path = "",
        headers = {},
        body = "",
        request_line = "",
        _line = line_num,
        _request_line_row = nil,
        _last_header_row = nil,
        _body_text = nil,
        _non_body_lines = {},
      }
    elseif type == "request_line" then
      if current_block then
        local text = get_node_text(child, content)
        current_block.request_line = vim.trim(text)
        local method = text:match("^(%S+)")
        local path = text:match("^%S+%s+(%S+)")
        current_block.method = vim.trim(method or "")
        current_block.path = vim.trim(path or "")
        current_block._request_line_row = line_num
      end
    elseif type == "header" then
      if current_block then
        local key = ""
        local value = ""
        for gc in child:iter_children() do
          local gt = gc:type()
          if gt == "header_key" then
            key = get_node_text(gc, content) or ""
          elseif gt == "header_value" then
            value = get_node_text(gc, content) or ""
          end
        end
        table.insert(current_block.headers, { vim.trim(key), vim.trim(value) })
        current_block._last_header_row = line_num
      end
    elseif type == "json_body" or type == "form_body" then
      if current_block then
        current_block._body_text = get_node_text(child, content)
      end
    elseif type == "multipart_boundary" or type == "multipart_form_data" then
      if current_block then
      end
    elseif type == "external_assertion" or type == "external_script" or type == "file_upload" or type == "comment" or type == "pre_script" or type == "post_script" then
      if current_block then
        for l = sr + 1, er + 1 do
          current_block._non_body_lines[l] = true
        end
      end
    end
  end

  finalize_block()

  return blocks, nil
end

function M.describe_content(content, file, opts)
  opts = opts or {}
  if not content or content == "" then
    return {}, nil
  end
  if not file or file == "" then
    file = "untitled.http"
  end

  local blocks, err = describe_via_treesitter(content)
  if blocks then
    return blocks, nil
  end

  state.log("WARN", "tree-sitter describe unavailable: " .. tostring(err))
  return {}, nil
end

function M.block_at_line(blocks, line)
  if not blocks or not line then return nil end
  for _, b in ipairs(blocks) do
    local start_l = b.line or 0
    local end_l = b.end_line or start_l
    if line >= start_l and line <= end_l then
      return b
    end
  end
  local best = nil
  for _, b in ipairs(blocks) do
    if (b.line or 0) <= line then
      best = b
    end
  end
  return best
end

function M.to_req_block(meta)
  if not meta then
    return { request_line = "", headers = {}, name = "", method = "", path = "", body = "" }
  end
  local headers = meta.headers or {}
  return {
    request_line = meta.request_line or "",
    headers = headers,
    name = meta.name or "",
    method = meta.method or "",
    path = meta.path or "",
    body = meta.body or "",
  }
end

function M.headers_str(meta)
  if not meta or not meta.headers then return "" end
  local parts = {}
  for _, h in ipairs(meta.headers) do
    if type(h) == "table" and h[1] then
      table.insert(parts, h[1] .. ": " .. (h[2] or ""))
    end
  end
  return table.concat(parts, "\n")
end

return M