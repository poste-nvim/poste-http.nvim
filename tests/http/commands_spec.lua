local harness = require("helpers.gui_harness")

describe("commands", function()
  before_each(function()
    harness.setup()
    package.loaded["poste-http.commands"] = nil
  end)

  after_each(function()
    harness.teardown()
  end)

  it("registers all Poste commands", function()
    local commands = require("poste-http.commands")
    commands.setup()

    local cmds = harness.get_user_commands()

    local expected = {
      "PosteRun", "PosteEnv", "PostePasteCurl",
      "PosteImportOpenAPI", "PosteImportSwagger", "PosteImportPostman",
      "PosteCopyAsCurl", "PosteHelp", "PosteImportResolve",
      "PosteCmpStatus", "PosteCmpProfile",
      "PosteSymbols", "PosteOutline", "PosteFormatHttp", "PosteHttpHistory",
      "PosteClearCache", "PosteTSInspect",
    }

    for _, name in ipairs(expected) do
      assert.is_not_nil(cmds[name],
        string.format("command '%s' should be registered", name))
    end
  end)
end)