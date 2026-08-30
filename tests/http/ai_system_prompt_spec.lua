-- Tests for poste-http.ai.system_prompt — knowledge + scope section.

local system_prompt = require("poste-http.ai.system_prompt")

describe("ai.system_prompt.build", function()
  it("contains the .http contract instructions", function()
    local md = system_prompt.build(nil)
    assert.truthy(md:match("```http"))
    assert.truthy(md:match("never inline literal secrets"))
    assert.truthy(md:match("client%.run"))
    assert.truthy(md:match("env%.json"))
  end)

  it("appends the scope section when bindings exist", function()
    local md = system_prompt.build({ file = "/p/api.http", env = "prod", request = "Login" })
    assert.truthy(md:match("## Current chat scope"))
    assert.truthy(md:match("file /p/api%.http"))
    assert.truthy(md:match("environment prod"))
    assert.truthy(md:match("focused request Login"))
  end)

  it("omits the scope section without bindings", function()
    assert.falsy(system_prompt.build(nil):match("Current chat scope"))
    assert.falsy(system_prompt.build({}):match("Current chat scope"))
  end)
end)
