-- Tests for cache.collect_env_vars mtime invalidation:
-- edits to env.json within the same second must invalidate the cache.

local cache = require("poste-http.http.cache")
local state = require("poste-http.state")

describe("collect_env_vars", function()
  local dir
  local env_path
  local buf
  local orig_env

  local function write_env(content)
    local f = io.open(env_path, "w")
    f:write(content)
    f:close()
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    env_path = vim.fs.joinpath(dir, "env.json")
    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(dir, "test.http"))
    vim.api.nvim_set_current_buf(buf)
    orig_env = state.current_env
    state.current_env = "dev"
  end)

  after_each(function()
    state.current_env = orig_env
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    pcall(vim.fn.delete, dir, "rf")
  end)

  it("invalidates the cache when env.json changes within the same second", function()
    write_env(vim.json.encode({ dev = { token = "first" } }))
    assert.is_true(cache.collect_env_vars().token, "first env key present")

    write_env(vim.json.encode({ dev = { token = "second" } }))
    assert.is_true(cache.collect_env_vars().token, "second env key present")
  end)

  it("returns cached vars when file is unchanged", function()
    write_env(vim.json.encode({ dev = { token = "cached" } }))
    assert.is_true(cache.collect_env_vars().token)
    assert.is_true(cache.collect_env_vars().token)
  end)

  it("picks up an added key after a rewrite in the same second", function()
    write_env(vim.json.encode({ dev = { a = 1 } }))
    assert.is_true(cache.collect_env_vars().a)
    assert.is_nil(cache.collect_env_vars().b)

    write_env(vim.json.encode({ dev = { a = 1, b = 2 } }))
    assert.is_true(cache.collect_env_vars().b, "added key visible after same-second rewrite")
  end)
end)
