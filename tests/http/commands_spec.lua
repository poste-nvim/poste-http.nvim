local harness = require("helpers.gui_harness")

describe("commands", function()
  before_each(function()
    harness.setup()
    package.loaded["poste-http.commands"] = nil
  end)

  after_each(function()
    harness.teardown()
  end)

  it("registers all commands with the PosteHttp prefix", function()
    local commands = require("poste-http.commands")
    commands.setup()

    local cmds = harness.get_user_commands()

    local expected = {
      "PosteHttpRun", "PosteHttpEnv", "PosteHttpPasteCurl",
      "PosteHttpImportOpenAPI", "PosteHttpImportSwagger", "PosteHttpImportPostman",
      "PosteHttpCopyAsCurl", "PosteHttpHelp", "PosteHttpImportResolve",
      "PosteHttpCmpStatus", "PosteHttpCmpProfile",
      "PosteHttpSymbols", "PosteHttpOutline", "PosteHttpFormat", "PosteHttpHistory",
      "PosteHttpClearCache", "PosteHttpTSInspect",
    }

    for _, name in ipairs(expected) do
      assert.is_not_nil(cmds[name],
        string.format("command '%s' should be registered", name))
    end
  end)

  it("never registers a command without the PosteHttp prefix", function()
    local commands = require("poste-http.commands")
    commands.setup()

    for name in pairs(harness.get_user_commands()) do
      assert.truthy(name:match("^PosteHttp"), name .. " must start with PosteHttp")
    end
  end)
end)
