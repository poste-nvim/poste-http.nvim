-- Drift guard between highlight groups and their documentation.
--
-- Group names are only strings at runtime: a name documented but no longer
-- defined, or a defined name missing from the docs, both strand the user —
-- either they override a group that does nothing, or they never learn a
-- group exists. The full reference lives in doc/poste-http.txt under
-- *poste-http-highlights*; this spec pins that chapter to
-- lua/poste-http/http/highlights.lua in both directions.

local DOC_PATH = "doc/poste-http.txt"
local HIGHLIGHTS_PATH = "lua/poste-http/http/highlights.lua"
local TAG = "*poste-http-highlights*"

local function read(path)
  local fd = io.open(path, "r")
  assert(fd, "cannot open " .. path .. " (run from the repo root)")
  local text = fd:read("*a")
  fd:close()
  return text
end

--- Every group name defined in http/highlights.lua. Definitions always name
--- the group as a quoted string on a code line; comment lines are skipped so
--- placeholder names in prose ("PosteXxx") are not mistaken for definitions.
local function defined_groups()
  local groups = {}
  for line in read(HIGHLIGHTS_PATH):gmatch("[^\n]+") do
    if not line:match("^%s*%-%-") then
      for name in line:gmatch('"Poste%w+"') do
        groups[name:sub(2, -2)] = true
      end
    end
  end
  return groups
end

--- Body of the vimdoc highlights chapter: everything after the
--- *poste-http-highlights* tag line up to the next ====== divider.
local function highlights_chapter()
  local lines = vim.split(read(DOC_PATH), "\n")
  local start
  for i, line in ipairs(lines) do
    if line:find(TAG, 1, true) then
      start = i
      break
    end
  end
  assert(start, "doc has no " .. TAG .. " tag")
  local body = {}
  for i = start + 1, #lines do
    if lines[i]:match("^======") then
      break
    end
    body[#body + 1] = lines[i]
  end
  return table.concat(body, "\n")
end

describe("highlight documentation", function()
  it("is reachable from the vimdoc table of contents", function()
    assert.is_truthy(read(DOC_PATH):find("|poste-http-highlights|", 1, true))
  end)

  it("documents every group defined in highlights.lua", function()
    local chapter = highlights_chapter()
    local missing = {}
    for name in pairs(defined_groups()) do
      if not chapter:find(name, 1, true) then
        missing[#missing + 1] = name
      end
    end
    table.sort(missing)
    assert.same({}, missing)
  end)

  it("documents no group that no longer exists", function()
    local defined = defined_groups()
    local stale = {}
    for name in highlights_chapter():gmatch("Poste%w+") do
      if not defined[name] then
        stale[#stale + 1] = name
      end
    end
    table.sort(stale)
    assert.same({}, stale)
  end)
end)
