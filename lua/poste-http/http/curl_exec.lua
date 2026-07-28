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
  local body_file = tmp_dir .. "/body"
  local cookie_file = tmp_dir .. "/cookies"

  if expanded_body and expanded_body ~= "" then
    local fd = io.open(body_file, "w")
    if fd then
      fd:write(expanded_body)
      fd:close()
    end
  end

  local args = {
    "curl",
    "-s", "-S", "-v",
    "-L",
    "--compressed",
    "--globoff",
    "-X", method,
    "-D", headers_file,
    "-A", "poste/0.1.0",
  }

  for _, h in ipairs(headers) do
    table.insert(args, "-H")
    table.insert(args, h[1] .. ": " .. h[2])
  end

  if expanded_body and expanded_body ~= "" then
    table.insert(args, "--data-binary")
    table.insert(args, "@" .. body_file)
  end

  if cookie_jar then
    table.insert(args, "-b")
    table.insert(args, cookie_jar)
    table.insert(args, "-c")
    table.insert(args, cookie_jar)
  end

  table.insert(args, url)

  local cmd = ""
  for _, a in ipairs(args) do
    if cmd ~= "" then
      cmd = cmd .. " "
    end
    cmd = cmd .. shell_escape(a)
  end

  state.log("INFO", "curl: " .. cmd:sub(1, 500))

  local stdout_buf = {}
  local stderr_buf = {}
  local start_hires = uv.hrtime()

  local function on_complete()
    local response
    if #stdout_buf > 0 or #stderr_buf > 0 then
      response = response_parser.parse_response(headers_file, stdout_buf, stderr_buf, start_hires, method, url)
    else
      response = response_parser.parse_error(headers_file, stdout_buf, stderr_buf, start_hires, method, 1)
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
          local response = response_parser.parse_error(headers_file, stdout_buf, stderr_buf, start_hires, method, exit_code)
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