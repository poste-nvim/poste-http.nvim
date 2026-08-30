-- Tests for poste-http.ai.actions — confirm heuristics, append_header rules
-- and target-dir resolution (pure seams).

local actions = require("poste-http.ai.actions")

describe("ai.actions.is_readonly", function()
  it("accepts GET/HEAD/OPTIONS", function()
    assert.is_true(actions.is_readonly("### X\nGET /users\n"))
    assert.is_true(actions.is_readonly("head /x\n"))
    assert.is_true(actions.is_readonly("### X\n# c\nOPTIONS /x\n"))
  end)

  it("rejects mutating methods and scripts", function()
    assert.is_false(actions.is_readonly("### X\nPOST /users\n{}"))
    assert.is_false(actions.is_readonly("### X\nDELETE /users/1\n"))
    assert.is_false(actions.is_readonly("SCRIPT\n> {% %}\n"))
    assert.is_false(actions.is_readonly("# nothing"))
  end)
end)

describe("ai.actions.append_header", function()
  -- Stub package.loaded["poste-ai.state"] so the origin check is
  -- deterministic with or without poste-ai on the runtimepath.
  local buf

  local function stub_origin(filetype)
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = filetype
    package.loaded["poste-ai.state"] = { origin_buf = buf }
  end

  after_each(function()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    buf = nil
    package.loaded["poste-ai.state"] = nil
  end)

  it("emits a ### title separator for a .http origin", function()
    stub_origin("poste_http")
    local header = actions.append_header(nil, "GET /users\nAuthorization: Bearer {{t}}")
    assert.same({ "### GET /users" }, header)
  end)

  it("is suppressed when the block has its own ### header", function()
    stub_origin("poste_http")
    assert.is_nil(actions.append_header(nil, "### Mine\nGET /x"))
  end)

  it("returns nil for non-.http origins", function()
    stub_origin("python")
    assert.is_nil(actions.append_header(nil, "GET /x"))
  end)

  it("returns nil when the origin buffer is gone", function()
    stub_origin("poste_http")
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_nil(actions.append_header(nil, "GET /x"))
  end)
end)

describe("ai.actions.resolve_target_dir", function()
  it("prefers the mention file over scope and cwd", function()
    local refs = { { type = "context", context = "http", data = { file = "/a/b/api.http" } } }
    assert.equals("/a/b", actions.resolve_target_dir(refs, { file = "/c/d/other.http" }))
  end)

  it("falls back to the scope file, then cwd", function()
    assert.equals("/c/d", actions.resolve_target_dir(nil, { file = "/c/d/other.http" }))
    assert.equals(vim.fn.getcwd(), actions.resolve_target_dir(nil, nil))
  end)

  it("ignores refs from other contexts", function()
    local refs = { { type = "context", context = "db", data = { file = "/x/y.http" } } }
    assert.equals(vim.fn.getcwd(), actions.resolve_target_dir(refs, nil))
  end)
end)
