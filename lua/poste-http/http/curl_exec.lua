local M = {}
local state = require("poste-http.state")
local util = require("poste-http.util")
local response_parser = require("poste-http.http.response_parser")
local file_include = require("poste-http.http.file_include")

local uv = vim.uv or vim.loop

local function make_temp_dir()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  return tmp
end

local function cleanup_temp_dir(dir)
  if not dir then return end
  local ok, _ = pcall(vim.fn.delete, dir, "rf")
  return ok
end

local function shell_escape(s)
  if not s or s == "" then return "''" end
  if s:match("^[a-zA-Z0-9_./:=-]+$") then
    return s
  end
  local escaped = s:gsub("'", "'\\''")
  return "'" .. escaped .. "'"
end

--- Header names whose values must not be written to logs.
local SENSITIVE_HEADERS = {
  ["authorization"] = true,
  ["proxy-authorization"] = true,
  ["cookie"] = true,
  ["set-cookie"] = true,
  ["x-api-key"] = true,
  ["api-key"] = true,
}

--- Redact sensitive header values from a raw curl arg list.
--- Returns a log-safe string of the command.
local function redacted_curl_cmd(args)
  local parts = {}
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "-H" and args[i + 1] then
      local raw = args[i + 1]
      local k, v = raw:match("^([^:]+):%s*(.*)$")
      if k and SENSITIVE_HEADERS[k:lower()] then
        table.insert(parts, shell_escape(a))
        table.insert(parts, shell_escape(k .. ": [REDACTED]"))
        i = i + 1
      else
        table.insert(parts, shell_escape(a))
        table.insert(parts, shell_escape(raw))
        i = i + 1
      end
    else
      table.insert(parts, shell_escape(a))
    end
    i = i + 1
  end
  return table.concat(parts, " ")
end

function M.execute(opts, callback)
  if not callback then
    callback = opts.on_complete or function() end
  end

  local method = opts.method or "GET"
  local url = opts.url or ""
  local headers = opts.headers or {}
  local body = opts.body or ""
  local buf_dir = opts.buf_dir or ""
  local cookie_jar = opts.cookie_jar
  local timeout = opts.timeout or 30000

  if not url or url == "" then
    callback({ error = "No URL provided" })
    return
  end

  local expanded_body, inc_err = file_include.expand_file_includes(body, buf_dir)
  if inc_err then
    callback({ error = inc_err })
    return
  end

  local tmp_dir = make_temp_dir()
  local headers_file = tmp_dir .. "/headers"
  local req_body_file = tmp_dir .. "/body"
  local resp_body_file = tmp_dir .. "/resp_body"

  if expanded_body and expanded_body ~= "" then
    local fd, werr = io.open(req_body_file, "wb")
    if not fd then
      cleanup_temp_dir(tmp_dir)
      callback({ error = "Failed to write request body temp file: " .. tostring(werr) })
      return
    end
    local ok, werr2 = fd:write(expanded_body)
    fd:close()
    if not ok then
      cleanup_temp_dir(tmp_dir)
      callback({ error = "Failed to write request body temp file: " .. tostring(werr2) })
      return
    end
  end

  local args = {
    "curl",
    "-s", "-S", "-v",
    "-L",
    "--compressed",
    "--globoff",
    "--max-time", tostring(math.max(1, math.ceil(timeout / 1000))),
    "-X", method,
    "-D", headers_file,
    "-o", resp_body_file,
    "-A", "poste/0.1.0",
  }

  for _, h in ipairs(headers) do
    table.insert(args, "-H")
    table.insert(args, h[1] .. ": " .. h[2])
  end

  if expanded_body and expanded_body ~= "" then
    table.insert(args, "--data-binary")
    table.insert(args, "@" .. req_body_file)
  end

  if cookie_jar then
    table.insert(args, "-b")
    table.insert(args, cookie_jar)
    table.insert(args, "-c")
    table.insert(args, cookie_jar)
  end

  table.insert(args, url)

  state.log("INFO", "curl: " .. redacted_curl_cmd(args):sub(1, 500))

  local cmd_parts = {}
  for _, a in ipairs(args) do
    table.insert(cmd_parts, shell_escape(a))
  end
  local cmd = table.concat(cmd_parts, " ")

  local stdout_buf = {}
  local stderr_buf = {}
  local start_hires = uv.hrtime()

  local function on_complete()
    local response
    if #stdout_buf > 0 or #stderr_buf > 0 then
      response = response_parser.parse_response(headers_file, stdout_buf, stderr_buf, start_hires, method, url, resp_body_file)
    else
      response = response_parser.parse_error(headers_file, stdout_buf, stderr_buf, start_hires, method, 1, resp_body_file)
    end
    cleanup_temp_dir(tmp_dir)
    callback(response)
  end

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      data = util.ensure_job_data(data)
      if #data == 0 then return end
      for _, l in ipairs(data) do
        table.insert(stdout_buf, l)
      end
    end,
    on_stderr = function(_, data)
      data = util.ensure_job_data(data)
      if #data == 0 then return end
      for _, l in ipairs(data) do
        table.insert(stderr_buf, l)
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code ~= 0 then
          state.log("ERROR", string.format("curl exit code %d", exit_code))
          local response = response_parser.parse_error(headers_file, stdout_buf, stderr_buf, start_hires, method, exit_code, resp_body_file)
          cleanup_temp_dir(tmp_dir)
          callback(response)
          return
        end
        on_complete()
      end)
    end,
  })

  if not job_id or job_id <= 0 then
    cleanup_temp_dir(tmp_dir)
    callback({ error = "Failed to start curl process" })
  end
end

return M