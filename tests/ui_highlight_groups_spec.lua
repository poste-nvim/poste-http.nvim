-- Drift guard for highlight group names.
--
-- A `%#Group#` winbar string and an extmark `hl_group` have no compile-time
-- check: an undefined name silently renders unstyled. The env winbar and the
-- live-WebSocket-session hint spent the whole post-protocol-split era emitting
-- `%#PosteSqlMeta#`/`%#PosteSqlMetaDim#` — names no `nvim_set_hl` ever defined
-- (SQL-era leftovers) — so both bars were unstyleable. This spec pins every
-- `Poste*` name the UI emits against the groups http/highlights.lua defines.

local highlights = require("poste-http.http.highlights")

--- Every `Poste*` group name emitted anywhere under lua/, mapped to the file
--- that emits it (for the failure message).
local function emitted_groups()
  local groups = {}
  for _, path in ipairs(vim.fn.glob("lua/**/*.lua", false, true)) do
    local fd = io.open(path, "r")
    if fd then
      local text = fd:read("*a")
      fd:close()
      -- winbar / statusline highlight runs
      for g in text:gmatch("%%#([A-Za-z@][%w_@.]*)#") do
        groups[g] = groups[g] or path
      end
      -- extmark highlight groups
      for g in text:gmatch('hl_group%s*=%s*"([A-Za-z@][%w_@.]*)"') do
        groups[g] = groups[g] or path
      end
    end
  end
  return groups
end

local function is_defined(name)
  return not vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = name }))
end

describe("highlight group definitions", function()
  it("defines every Poste* group the UI emits", function()
    highlights.setup()
    local missing = {}
    for group, path in pairs(emitted_groups()) do
      if group:match("^Poste") and not is_defined(group) then
        missing[#missing + 1] = group .. "  (emitted by " .. path .. ")"
      end
    end
    table.sort(missing)
    assert.same({}, missing)
  end)

  it("leaves no SQL-era group name in the UI", function()
    -- PosteSql* groups belong to poste-db.nvim; this repo is standalone and
    -- defines none of them, so any survivor renders unstyled.
    for group in pairs(emitted_groups()) do
      assert.is_nil(group:match("^PosteSql"), "stale SQL-era group emitted: " .. group)
    end
  end)

  it("detects an undefined group (self-check of the probe above)", function()
    -- Without this the first test would pass for a detector that reports
    -- "defined" unconditionally.
    assert.is_false(is_defined("PosteSqlMeta"))
    assert.is_true(is_defined("PosteMeta"))
  end)

  it("resolves the winbar chrome groups to a concrete style", function()
    assert.is_true(is_defined("PosteMeta"))
    assert.is_true(is_defined("PosteMetaDim"))
  end)
end)
