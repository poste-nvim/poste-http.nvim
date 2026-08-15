local uv = vim.uv or vim.loop
local C = require("poste-http.constants")
local M = {}
local ns = vim.api.nvim_create_namespace(C.INDICATOR_NS_NAME)
local _extmarks = {}  -- buf -> { line_0 = extmark_id, ... }
local spinners = {}   -- buf -> { line_0 = { timer, gen }, ... }
local spinner_frames = C.SPINNER_FRAMES

local function stop_timer(buf, line_0)
  if not spinners[buf] then return end
  local s = spinners[buf][line_0]
  if not s then return end
  s.timer:stop()
  s.timer:close()
  spinners[buf][line_0] = nil
end

local function stop_all_timers(buf)
  if not spinners[buf] then return end
  for _, s in pairs(spinners[buf]) do
    s.timer:stop()
    s.timer:close()
  end
  spinners[buf] = nil
end

function M.clear_all(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if _extmarks[buf] then _extmarks[buf] = {} end
  stop_all_timers(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

function M.clear_other_requests(buf, line_0)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not _extmarks[buf] then return end
  for other_line_0, _ in pairs(_extmarks[buf]) do
    if other_line_0 ~= line_0 then
      _extmarks[buf][other_line_0] = nil
      vim.api.nvim_buf_clear_namespace(buf, ns, other_line_0, other_line_0 + 1)
    end
  end
end

local function format_latency(latency_ms)
  if latency_ms >= 1000 then
    return string.format("%.2f s", latency_ms / 1000)
  end
  return string.format("%.2f ms", latency_ms)
end

local function build_assertion_text(assertion_results)
  if not assertion_results or not assertion_results.total or assertion_results.total == 0 then
    return nil
  end
  if assertion_results.failed and assertion_results.failed > 0 then
    return { text = string.format("  ✘ %d/%d tests", assertion_results.failed, assertion_results.total), hl = "PosteError" }
  end
  return { text = string.format("  ✓ %d/%d tests", assertion_results.passed, assertion_results.total), hl = "PosteSuccess" }
end

local function build_virt_text(latency_ms, assertion_results)
  local virt_text = {}
  if latency_ms and latency_ms > 0 then
    table.insert(virt_text, { format_latency(latency_ms), "PosteLatency" })
  end
  local assert_item = build_assertion_text(assertion_results)
  if assert_item then
    table.insert(virt_text, { assert_item.text, assert_item.hl })
  end
  return virt_text
end

local function set_extmark(buf, line_0, virt_text)
  vim.api.nvim_buf_clear_namespace(buf, ns, line_0, line_0 + 1)
  if virt_text and #virt_text > 0 then
    local id = vim.api.nvim_buf_set_extmark(buf, ns, line_0, 0, {
      virt_text = virt_text,
      virt_text_pos = "right_align",
      hl_mode = "combine",
    })
    if not _extmarks[buf] then _extmarks[buf] = {} end
    _extmarks[buf][line_0] = id
  end
end

function M.set_indicator(buf, line_0, status, latency_ms, assertion_results)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not line_0 then return end
  if not _extmarks[buf] then _extmarks[buf] = {} end

  if status == "running" then
    stop_timer(buf, line_0)
    set_extmark(buf, line_0, { { spinner_frames[1], "PosteSpinner" } })
    local frame = 1
    local timer = uv.new_timer()
    if not spinners[buf] then spinners[buf] = {} end
    spinners[buf][line_0] = { timer = timer }
    local function update_spinner()
      if not spinners[buf] or not spinners[buf][line_0] then return end
      if not vim.api.nvim_buf_is_valid(buf) then return end
      frame = (frame % #spinner_frames) + 1
      set_extmark(buf, line_0, { { spinner_frames[frame], "PosteSpinner" } })
    end
    timer:start(C.SPINNER_INTERVAL_MS, C.SPINNER_INTERVAL_MS, vim.schedule_wrap(update_spinner))
  elseif status == "success" then
    stop_timer(buf, line_0)
    local virt_text = build_virt_text(latency_ms, assertion_results)
    table.insert(virt_text, 1, { "✓ ", "PosteSuccess" })
    set_extmark(buf, line_0, virt_text)
  elseif status == "error" then
    stop_timer(buf, line_0)
    local virt_text = build_virt_text(latency_ms, assertion_results)
    table.insert(virt_text, 1, { "✘ ", "PosteError" })
    set_extmark(buf, line_0, virt_text)
  end
end

local _indicator_augroup = vim.api.nvim_create_augroup("PosteHttpIndicators", { clear = true })
vim.api.nvim_create_autocmd("BufDelete", {
  group = _indicator_augroup,
  callback = function(ev)
    local buf = ev.buf
    if _extmarks[buf] then _extmarks[buf] = nil end
    if spinners[buf] then
      for _, s in pairs(spinners[buf]) do
        s.timer:stop()
        s.timer:close()
      end
      spinners[buf] = nil
    end
  end,
})

return M