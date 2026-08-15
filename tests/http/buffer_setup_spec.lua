local mock = require("helpers.mock_nvim")
local state = require("poste-http.state")

describe("buffer_setup namespace leak", function()
  before_each(function()
    mock.setup()
    state.config.keymaps = {}
    package.loaded["poste-http.buffer_setup"] = nil
  end)

  after_each(function()
    mock.teardown()
  end)

  it("uses a single fileref namespace across buffers", function()
    local buf_setup = require("poste-http.buffer_setup")

    buf_setup.setup_buffer_keymaps(1001)
    buf_setup.setup_buffer_keymaps(1002)

    local ns_name = nil
    local ns_count = 0
    for i = 1, #mock.calls do
      if mock.calls[i] == "nvim_create_namespace" then
        local name = mock.calls[i + 1]
        if name and type(name) == "string" and name:match("poste_fileref") then
          ns_name = name
          ns_count = ns_count + 1
        end
      end
    end

    assert.is_not_nil(ns_name, "should create a fileref namespace")
    assert.equals("poste_fileref", ns_name,
      "should use static name, not per-buffer unique name")
    assert.equals(1, ns_count,
      "should create only one fileref namespace across multiple buffers")
  end)
end)