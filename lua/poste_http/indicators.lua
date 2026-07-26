local uv = vim.uv or vim.loop
local C = require("poste_http.constants")
local M = {}
local sign_group = C.SIGN_GROUP_NAME
local indicator_ns = vim.api.nvim_create_namespace(C.INDICATOR_NS_NAME)
local indicator_marks = {}
local spinner_timer = nil
local spinner_gen = 0
local spinner_frames = C.SPINNER_FRAMES
local sign_configs = {
  PosteSpinnerSign = { text = spinner_frames[1], texthl = "PosteSpinner" },
  PosteSuccessSign = { text = "✓", texthl = "PosteSuccess" },
  PosteErrorSign   = { text = "✘", texthl = "PosteError" },
}
for name, config in pairs(sign_configs) do
  pcall(vim.fn.sign_define, name, config)
end

local function stop_timer()
  spinner_gen = spinner_gen + 1
  if spinner_timer then
    spinner_timer:stop()
    spinner_timer:close()
    spinner_timer = nil
  end
end

function M.clear_all(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if indicator_marks[buf] then
    for _, sign_id in pairs(indicator_marks[buf]) do
      pcall(vim.fn.sign_unplace, sign_group, { id = sign_id })
    end
    indicator_marks[buf] = {}
  end
  vim.api.nvim_buf_clear_namespace(buf, indicator_ns, 0, -1)
  stop_timer()
end

function M.clear_other_requests(buf, line_0)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not indicator_marks[buf] then return end
  for other_line_0, sign_id in pairs(indicator_marks[buf]) do
    if other_line_0 ~= line_0 then
      pcall(vim.fn.sign_unplace, sign_group, { id = sign_id })
      indicator_marks[buf][other_line_0] = nil
      vim.api.nvim_buf_clear_namespace(buf, indicator_ns, other_line_0, other_line_0 + 1)
    end
  end
end

local function place_or_replace_sign(buf, line_0, old_sign_id, sign_name)
  local lnum = line_0 + 1
  if old_sign_id then
    vim.cmd(string.format("sign place %d line=%d name=%s group=%s buffer=%d",
      old_sign_id, lnum, sign_name, sign_group, buf))
    return old_sign_id
  else
    return vim.fn.sign_place(0, sign_group, sign_name, buf, { lnum = lnum })
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

function M.set_indicator(buf, line_0, status, latency_ms, assertion_results)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not line_0 then return end
  if not indicator_marks[buf] then indicator_marks[buf] = {} end
  stop_timer()
  spinner_gen = spinner_gen + 1
  local my_gen = spinner_gen
  if status == "running" then
    local old_id = indicator_marks[buf][line_0]
    local new_sign_id = place_or_replace_sign(buf, line_0, old_id, "PosteSpinnerSign")
    if new_sign_id and new_sign_id > 0 then
      indicator_marks[buf][line_0] = new_sign_id
    end
    local frame = 1
    local function update_spinner()
      if my_gen ~= spinner_gen then return end
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local sign_id = indicator_marks[buf] and indicator_marks[buf][line_0]
      if not sign_id then return end
      vim.fn.sign_define("PosteSpinnerSign", { text = spinner_frames[frame], texthl = "PosteSpinner" })
      local new_id = vim.fn.sign_place(0, sign_group, "PosteSpinnerSign", buf, { lnum = line_0 + 1 })
      if new_id and new_id > 0 then
        pcall(vim.fn.sign_unplace, sign_group, { id = sign_id })
        indicator_marks[buf][line_0] = new_id
      end
      frame = (frame % #spinner_frames) + 1
    end
    spinner_timer = uv.new_timer()
    spinner_timer:start(C.SPINNER_INTERVAL_MS, C.SPINNER_INTERVAL_MS, vim.schedule_wrap(update_spinner))
  elseif status == "success" then
    local old_id = indicator_marks[buf][line_0]
    local _ = place_or_replace_sign(buf, line_0, old_id, "PosteSuccessSign")
    vim.api.nvim_buf_clear_namespace(buf, indicator_ns, line_0, line_0 + 1)
    local virt_text = build_virt_text(latency_ms, assertion_results)
    if #virt_text > 0 then
      vim.api.nvim_buf_set_extmark(buf, indicator_ns, line_0, 0, {
        virt_text = virt_text, virt_text_pos = "eol", hl_mode = "combine",
      })
    end
  elseif status == "error" then
    local old_id = indicator_marks[buf][line_0]
    local sign_id = place_or_replace_sign(buf, line_0, old_id, "PosteErrorSign")
    if sign_id and sign_id > 0 then
      indicator_marks[buf][line_0] = sign_id
    end
    vim.api.nvim_buf_clear_namespace(buf, indicator_ns, line_0, line_0 + 1)
    local virt_text = build_virt_text(latency_ms, assertion_results)
    if #virt_text > 0 then
      vim.api.nvim_buf_set_extmark(buf, indicator_ns, line_0, 0, {
        virt_text = virt_text, virt_text_pos = "eol", hl_mode = "combine",
      })
    end
  end
end

return M