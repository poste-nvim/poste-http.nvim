local M = {}

local function http_reason(status)
  local reasons = {
    [100] = "Continue", [101] = "Switching Protocols", [102] = "Processing",
    [200] = "OK", [201] = "Created", [202] = "Accepted", [203] = "Non-Authoritative Information",
    [204] = "No Content", [205] = "Reset Content", [206] = "Partial Content",
    [300] = "Multiple Choices", [301] = "Moved Permanently", [302] = "Found",
    [303] = "See Other", [304] = "Not Modified", [307] = "Temporary Redirect",
    [308] = "Permanent Redirect",
    [400] = "Bad Request", [401] = "Unauthorized", [402] = "Payment Required",
    [403] = "Forbidden", [404] = "Not Found", [405] = "Method Not Allowed",
    [406] = "Not Acceptable", [407] = "Proxy Authentication Required",
    [408] = "Request Timeout", [409] = "Conflict", [410] = "Gone",
    [411] = "Length Required", [412] = "Precondition Failed",
    [413] = "Payload Too Large", [414] = "URI Too Long",
    [415] = "Unsupported Media Type", [416] = "Range Not Satisfiable",
    [417] = "Expectation Failed", [418] = "I'm a Teapot",
    [421] = "Misdirected Request", [422] = "Unprocessable Entity",
    [423] = "Locked", [424] = "Failed Dependency", [425] = "Too Early",
    [426] = "Upgrade Required", [428] = "Precondition Required",
    [429] = "Too Many Requests", [431] = "Request Header Fields Too Large",
    [451] = "Unavailable For Legal Reasons",
    [500] = "Internal Server Error", [501] = "Not Implemented",
    [502] = "Bad Gateway", [503] = "Service Unavailable",
    [504] = "Gateway Timeout", [505] = "HTTP Version Not Supported",
    [506] = "Variant Also Negotiates", [507] = "Insufficient Storage",
    [508] = "Loop Detected", [510] = "Not Extended", [511] = "Network Authentication Required",
  }
  return reasons[status] or ("Status " .. status)
end

local function parse_set_cookie(header_value)
  local cookie = { name = "", value = "", domain = "", path = "/", expires = nil, http_only = false, secure = false }
  local name, value = header_value:match("^%s*([^=]+)=([^;]+)")
  if not name then return nil end
  cookie.name = vim.trim(name)
  cookie.value = vim.trim(value)
  for attr in header_value:gmatch(";%s*([^;]+)") do
    local attr_name = vim.trim(attr)
    local attr_val = true
    local eq_pos = attr_name:find("=")
    if eq_pos then
      attr_val = vim.trim(attr_name:sub(eq_pos + 1))
      attr_name = vim.trim(attr_name:sub(1, eq_pos - 1))
    end
    local lower = attr_name:lower()
    if lower == "domain" then
      cookie.domain = attr_val
    elseif lower == "path" then
      cookie.path = attr_val
    elseif lower == "expires" then
      cookie.expires = attr_val
    elseif lower == "httponly" then
      cookie.http_only = true
    elseif lower == "secure" then
      cookie.secure = true
    end
  end
  return cookie
end

local function parse_headers_file(headers_text)
  if not headers_text or headers_text == "" then
    return { status = 200, status_text = "200 OK", headers = {}, content_type = "" }
  end
  local blocks = {}
  local text = headers_text .. "\n\n"
  for block in text:gmatch("(.-)\r?\n\r?\n") do
    local trimmed = vim.trim(block)
    if trimmed ~= "" then
      table.insert(blocks, trimmed)
    end
  end
  if #blocks == 0 then
    return { status = 200, status_text = "200 OK", headers = {}, content_type = "" }
  end
  local final = blocks[#blocks]
  local lines = vim.split(final, "\n", { plain = true })
  local status_line = vim.trim(lines[1] or "")
  local status = 0
  local status_text = ""
  if status_line:match("^HTTP/") then
    local code_str = status_line:match("^(%S+)%s+(%d+)%s*(.*)")
    if code_str then
      local _, code, reason = status_line:match("^(%S+)%s+(%d+)%s*(.*)")
      if code then
        status = tonumber(code) or 0
        local reason_text = vim.trim(reason or "")
        status_text = tostring(status) .. (reason_text ~= "" and " " .. reason_text or "")
      end
    end
    if status == 0 then
      status = tonumber(status_line:match("HTTP/%d%.?%d* (%d+)") or "0") or 0
    end
  end
  if status_text == "" and status > 0 then
    status_text = tostring(status) .. " " .. http_reason(status)
  end
  local headers = {}
  local content_type = ""
  for i = 2, #lines do
    local line = vim.trim(lines[i])
    if line ~= "" then
      local key, value = line:match("^([^:]+):%s*(.*)")
      if key then
        local k = vim.trim(key)
        local v = vim.trim(value)
        table.insert(headers, { k, v })
        if k:lower() == "content-type" then
          content_type = v
        end
      end
    end
  end
  return { status = status, status_text = status_text, headers = headers, content_type = content_type }
end

local function extract_cookies(headers)
  local cookies = {}
  for _, h in ipairs(headers) do
    if h[1]:lower() == "set-cookie" then
      local c = parse_set_cookie(h[2])
      if c then
        table.insert(cookies, c)
      end
    end
  end
  return cookies
end

function M.parse_response(headers_file, stdout_data, stderr_data, start_hires, method, request_url, body_file)
  local uv = vim.uv or vim.loop
  local latency_ms = 0
  if start_hires then
    latency_ms = math.floor((uv.hrtime() - start_hires) / 1e6)
  end

  local body = ""
  if body_file then
    local fd = io.open(body_file, "rb")
    if fd then
      body = fd:read("*a")
      fd:close()
    end
  end
  if body == "" and stdout_data and #stdout_data > 0 then
    body = table.concat(stdout_data, "\n")
  end

  local verbose = ""
  if stderr_data and #stderr_data > 0 then
    verbose = table.concat(stderr_data, "\n")
  end

  local headers_text = ""
  if headers_file then
    local fd = io.open(headers_file, "r")
    if fd then
      headers_text = fd:read("*a")
      fd:close()
    end
  end

  local parsed = parse_headers_file(headers_text)

  local cookies = extract_cookies(parsed.headers)

  local redirect_count = "0"
  local raw_redirect_count = verbose:match("([%d]+) r[ea]direct")
  if raw_redirect_count then
    redirect_count = raw_redirect_count
  end

  local final_url = request_url or ""
  local loc = verbose:match("Location: ([^\r\n]+)")
  if loc then
    final_url = vim.trim(loc)
  end
  local from = verbose:match("}%s+(%S+)%s*$")
  if not from then
    from = verbose:match("\\*\\s+(%S+)%s*$")
  end
  if not from then
    from = verbose:match("Trying%s+%S+.*connected.*to%s+(%S+)")
  end

  local response = {
    protocol = "http",
    status = parsed.status,
    status_text = parsed.status_text,
    latency_ms = latency_ms,
    url = final_url,
    content_type = parsed.content_type,
    headers = parsed.headers,
    body = body,
    cookies = cookies,
    metadata = {
      method = method or "",
      redirect_count = redirect_count,
      verbose = verbose,
    },
  }

  -- Fallback: detect content-type from body if headers didn't provide it
  if (not response.content_type or response.content_type == "") and body ~= "" then
    if body:match("^%s*[{%[]") then
      response.content_type = "application/json"
    elseif body:match("^%s*<") then
      response.content_type = "text/xml"
    elseif body:match("^%s*<") then
      response.content_type = "text/html"
    end
  end

  return response
end

function M.parse_error(headers_file, stdout_data, stderr_data, start_hires, method, exit_code, body_file)
  local uv = vim.uv or vim.loop
  local latency_ms = 0
  if start_hires then
    latency_ms = math.floor((uv.hrtime() - start_hires) / 1e6)
  end

  local body = ""
  if body_file then
    local fd = io.open(body_file, "rb")
    if fd then
      body = fd:read("*a")
      fd:close()
    end
  end
  if body == "" and stdout_data and #stdout_data > 0 then
    body = table.concat(stdout_data, "\n")
  end
  local stderr = ""
  if stderr_data and #stderr_data > 0 then
    stderr = table.concat(stderr_data, "\n")
  end

  local headers_text = ""
  if headers_file then
    local fd = io.open(headers_file, "r")
    if fd then
      headers_text = fd:read("*a")
      fd:close()
    end
  end

  local parsed = parse_headers_file(headers_text)

  local display_body = body
  if display_body == "" then
    display_body = stderr
  end

  return {
    protocol = "error",
    status = parsed.status,
    status_text = "Failed (exit " .. tostring(exit_code) .. ")",
    latency_ms = latency_ms,
    url = "",
    content_type = parsed.content_type or "text/plain",
    headers = parsed.headers,
    body = display_body,
    cookies = {},
    metadata = {
      method = method or "",
      error = stderr,
      exit_code = tostring(exit_code),
      verbose = stderr,
    },
  }
end

M._test = {
  parse_headers_file = parse_headers_file,
}

return M