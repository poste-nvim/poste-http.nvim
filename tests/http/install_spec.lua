local harness = require("helpers.gui_harness")

describe("install", function()
  before_each(function()
    harness.setup {
      executable = function(name)
        if name == "cc" then return 1 end
        return 0
      end,
    }
    package.loaded["poste-http.install"] = nil
  end)

  after_each(function()
    harness.teardown()
  end)

  it("ensure_parsers skips when no C compiler", function()
    harness.teardown()
    harness.setup {
      executable = function(name) return 0 end,
    }
    package.loaded["poste-http.install"] = nil
    local install = require("poste-http.install")
    install.ensure_parsers()

    -- No notifications should be sent (no compiler, no attempt)
    local notify_count = 0
    for _, call in ipairs(harness.calls) do
      if call == "vim_notify" then notify_count = notify_count + 1 end
    end
    assert.equals(0, notify_count, "should not notify when no compiler")
  end)

  it("force_build reports when no compiler found", function()
    harness.teardown()
    harness.setup {
      executable = function(name) return 0 end,
    }
    package.loaded["poste-http.install"] = nil
    local install = require("poste-http.install")
    install.force_build()

    local has_error = false
    for i = 1, #harness.calls do
      if harness.calls[i] == "vim_notify" then
        local detail = harness.calls[i + 1]
        if detail and detail.msg and detail.msg:match("No parsers") then
          has_error = true
        end
      end
    end
    assert.is_true(has_error, "should notify about no parsers compiled")
  end)
end)