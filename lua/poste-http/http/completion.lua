--- Completion source for blink.cmp and nvim-cmp.
--- Provides context-aware completions for HTTP requests.
---
--- For blink.cmp: this module IS the source (blink.cmp calls require("poste-http.http.completion").new())
--- For nvim-cmp:  use M.source subtable + M.register()
---
--- Structure:
---   - Module header & requires (lines 1-20)
---   - blink.cmp source (M.new, M:enabled, M:get_*, M:get_completions, M:resolve, M:execute)
---   - nvim-cmp source (M.source table, minimal wrapper)
---   - Registration (M.register for both engines)
---   - Diagnostics (M.status)

local M = {}
local item_builder = require("poste-http.http.item_builder")

---------------------------------------------------------------------------
-- blink.cmp source (module-level interface)
---------------------------------------------------------------------------

--- Constructor called by blink.cmp.
function M.new(opts, config)
  local self = setmetatable({}, { __index = M })
  self.opts = opts or {}
  return self
end

--- blink.cmp: whether this source is enabled for the current buffer.
function M:enabled()
  return vim.bo.filetype == "poste_http"
end

--- blink.cmp: trigger characters that activate this source.
function M:get_trigger_characters()
  return { ":", "/", "-", "{", ".", "#" }
end

--- blink.cmp: keyword pattern for word boundary detection.
function M:get_keyword_pattern()
  return '[#%w_%-]+'
end

--- blink.cmp: get completion items.
function M:get_completions(ctx, callback)
  local line = ctx.line or ""
  local cursor = ctx.cursor or { 0, 0 }
  local cursor_line = cursor[1]
  local col = cursor[2] or 0
  local buf = ctx.bufnr or vim.api.nvim_get_current_buf()
  local line_before_cursor = line:sub(1, col)

  -- blink exposes ctx.cursor = nvim_win_get_cursor(0) = {1-based row, 0-based col},
  -- matching context_detector's convention.
  local items = item_builder.get_items_for_context(line_before_cursor, buf, cursor_line, col)

  callback({
    items = items,
    -- Must be true so {{ triggers a re-query: first { → "method_or_header" context,
    -- second { → "variable" context. Without this, blink caches the first result.
    is_incomplete_forward = true,
    is_incomplete_backward = false,
  })
end

--- blink.cmp: resolve additional item details.
function M:resolve(item, callback)
  callback(item)
end

--- blink.cmp: called after user accepts a completion.
function M:execute(ctx, item, callback, default_implementation)
  if default_implementation then
    default_implementation()
  end
  callback()
end

---------------------------------------------------------------------------
-- nvim-cmp source (minimal wrapper)
---------------------------------------------------------------------------

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source.get_keyword_pattern()
  return [=[[#\w%-]\+]=]
end

function source:get_trigger_characters()
  return { ":", "/", "-", "{", ".", "#" }
end

function source:get_debug_name()
  return "poste"
end

function source:is_available()
  return vim.bo.filetype == "poste_http"
end

function source:complete(request, callback)
  local line = request.context.cursor_before_line
  local col = request.offset
  local line_before_cursor = line:sub(1, col - 1)
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]

  local items = item_builder.get_items_for_context(line_before_cursor, buf, cursor_line, col - 1)

  callback({ items = items, isIncomplete = true })
end

function source:resolve(completion_item, callback)
  callback(completion_item)
end

function source:execute(completion_item, callback)
  callback(completion_item)
end

M.source = source

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local registered = false

local function register_blink()
  local blink = require("blink.cmp")
  blink.add_source_provider("poste", {
    module = "poste-http.http.completion",
    name = "Poste",
    score_offset = 100,
  })
  blink.add_filetype_source("poste_http", "poste")
  registered = "blink"
end

local function register_cmp()
  local cmp = require("cmp")
  cmp.register_source("poste", source.new())
  registered = "cmp"
end

function M.register()
  if registered then return end

  vim.schedule(function()
    if registered then return end

    local blink_ok = pcall(register_blink)
    if blink_ok then return end

    local cmp_ok = pcall(register_cmp)
    if cmp_ok then return end

    local group = vim.api.nvim_create_augroup("PosteCmpRegister", { clear = true })
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      callback = function()
        if registered then return end
        if pcall(register_blink) then
          vim.api.nvim_del_augroup_by_name("PosteCmpRegister")
          return
        end
        if pcall(register_cmp) then
          if vim.bo.filetype == "poste_http" then
            local cmp = require("cmp")
            cmp.setup.buffer({
              sources = cmp.config.sources({ { name = "poste" } }, { { name = "buffer" } }),
            })
          end
          vim.api.nvim_del_augroup_by_name("PosteCmpRegister")
        end
      end,
    })
  end)
end

--- Diagnostic function to check completion status.
function M.status()
  if registered == "blink" then
    local providers = {}
    local blink_ok, blink = pcall(require, "blink.cmp")
    if blink_ok and blink.config and blink.config.sources and blink.config.sources.providers then
      for id, _ in pairs(blink.config.sources.providers) do
        table.insert(providers, id)
      end
    end
    return string.format("blink.cmp [%s], filetype=%s",
      #providers > 0 and table.concat(providers, ", ") or "?",
      vim.bo.filetype)
  end
  if registered == "cmp" then
    return "nvim-cmp, filetype=" .. vim.bo.filetype
  end
  return "not registered"
end

return M
