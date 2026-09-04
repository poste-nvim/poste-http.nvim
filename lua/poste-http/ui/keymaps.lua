--- Config-driven keymap registration.
---
--- U7 from the 2026-08-30 review: every UI surface repeated the same
--- `k = state.get_keymap(section, action, default); if k then
--- vim.keymap.set(...) end` block per action (~160 lines in buffer.lua alone).
--- register/register_all collapse that into data.

local state = require("poste-http.state")

local M = {}

--- Map one action from config.
--- @param buf number
--- @param section string  keymap section (e.g. "http_response")
--- @param action string  action name inside the section
--- @param default string|nil  key used when the action is not configured
--- @param handler function|string  rhs for vim.keymap.set
--- @param opts table|nil  extra vim.keymap.set opts (buffer/noremap/silent set
---   here; `opts.modes` overrides the default "n" and is not passed through)
--- @return boolean  true when a mapping was registered (config value or
---   default), false when the action is disabled (`false`) in config
function M.register(buf, section, action, default, handler, opts)
  local key = state.get_keymap(section, action, default)
  if not key then return false end
  local modes = (opts and opts.modes) or "n"
  local map_opts = vim.tbl_extend("force",
    { buffer = buf, noremap = true, silent = true }, opts or {})
  map_opts.modes = nil
  vim.keymap.set(modes, key, handler, map_opts)
  return true
end

--- Register a list of specs.
--- @param buf number
--- @param section string
--- @param specs table[]  { action, default, handler, opts? } entries
--- @param base_opts table|nil  opts shared by every spec (per-spec opts win)
--- @return boolean[]  per-spec registration results, same order
function M.register_all(buf, section, specs, base_opts)
  local results = {}
  for _, spec in ipairs(specs) do
    local opts = spec.opts or base_opts
    if spec.opts and base_opts then
      opts = vim.tbl_extend("force", base_opts, spec.opts)
    end
    results[#results + 1] = M.register(buf, section, spec.action, spec.default, spec.handler, opts)
  end
  return results
end

return M
