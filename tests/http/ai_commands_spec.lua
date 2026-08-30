-- Tests for poste-http.ai.commands — /env candidate discovery from env.json.

local commands = require("poste-http.ai.commands")

describe("ai.commands.env_names", function()
  local tmp

  before_each(function()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
  end)

  after_each(function()
    pcall(vim.fn.delete, tmp, "rf")
  end)

  it("lists env names from the scoped file's env.json", function()
    vim.fn.writefile({ '{"dev": {}, "prod": {}}' }, tmp .. "/env.json")
    local names, err = commands.env_names({ file = tmp .. "/api.http" })
    assert.is_nil(err)
    assert.same({ "dev", "prod" }, names)
  end)

  it("walks up from the file's directory", function()
    local deep = tmp .. "/sub"
    vim.fn.mkdir(deep, "p")
    vim.fn.writefile({ '{"staging": {}}' }, tmp .. "/env.json")
    local names, err = commands.env_names({ file = deep .. "/api.http" })
    assert.is_nil(err)
    assert.same({ "staging" }, names)
  end)

  it("errors when no env.json exists above the file", function()
    local other = vim.fn.tempname()
    vim.fn.mkdir(other, "p")
    local names, err = commands.env_names({ file = other .. "/api.http" })
    assert.is_nil(names)
    assert.truthy(err:match("no env%.json"))
    pcall(vim.fn.delete, other, "rf")
  end)

  it("errors on malformed env.json", function()
    vim.fn.writefile({ "not json" }, tmp .. "/env.json")
    local names, err = commands.env_names({ file = tmp .. "/api.http" })
    assert.is_nil(names)
    assert.truthy(err:match("cannot parse"))
  end)
end)
