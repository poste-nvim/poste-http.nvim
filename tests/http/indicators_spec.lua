-- Tests for indicators.lua: set_indicator, build_virt_text, and helpers.
--
-- Uses the mock_nvim helper to isolate from Neovim API.

local mock = require("helpers.mock_nvim")

describe("indicators", function()
  local indicators

  before_each(function()
    mock.setup()
    -- Re-require to pick up fresh module state
    package.loaded["poste-http.indicators"] = nil
    indicators = require("poste-http.indicators")
  end)

  after_each(function()
    mock.teardown()
    package.loaded["poste-http.indicators"] = nil
  end)

  -------------------------------------------------------------------------
  -- build_virt_text (internal helper)
  -------------------------------------------------------------------------

  describe("build_virt_text", function()
    -- build_virt_text is local; drive it through set_indicator and read the
    -- virt_text captured by the mocked nvim_buf_set_extmark.
    local function last_virt_text()
      for i = #mock.calls, 1, -1 do
        local call = mock.calls[i]
        if call == "nvim_buf_set_extmark" then
          local detail = mock.calls[i + 1]
          return detail and detail.opts and detail.opts.virt_text or nil
        end
      end
      return nil
    end

    it("returns empty table when no latency and no assertions", function()
      indicators.set_indicator(1, 0, "success")
      local virt = last_virt_text()
      assert.equals("✓ ", virt[1][1])
      assert.equals(1, #virt)
    end)

    it("formats latency < 1000ms as ms", function()
      indicators.set_indicator(1, 0, "success", 120)
      local virt = last_virt_text()
      assert.equals("120.00 ms", virt[2][1])
      assert.equals("PosteLatency", virt[2][2])
    end)

    it("formats latency >= 1000ms as seconds", function()
      indicators.set_indicator(1, 0, "success", 2500)
      local virt = last_virt_text()
      assert.equals("2.50 s", virt[2][1])
    end)

    it("shows assertion passed count when no failures", function()
      indicators.set_indicator(1, 0, "success", 10, { total = 5, passed = 5, failed = 0 })
      local virt = last_virt_text()
      local assert_item = virt[#virt]
      assert.equals("  ✓ 5/5 tests", assert_item[1])
      assert.equals("PosteSuccess", assert_item[2])
    end)

    it("shows assertion failed count when failures exist", function()
      indicators.set_indicator(1, 0, "error", 10, { total = 5, passed = 2, failed = 3 })
      local virt = last_virt_text()
      local assert_item = virt[#virt]
      assert.equals("  ✘ 3/5 tests", assert_item[1])
      assert.equals("PosteError", assert_item[2])
    end)
  end)

  -------------------------------------------------------------------------
  -- set_indicator("running")
  -------------------------------------------------------------------------

  describe("set_indicator('running')", function()
    it("places spinner extmark", function()
      indicators.set_indicator(1, 0, "running")
      -- Should have called nvim_buf_set_extmark
      local has_extmark = false
      for _, call in ipairs(mock.calls) do
        if call == "nvim_buf_set_extmark" then
          has_extmark = true
          break
        end
      end
      assert.is_true(has_extmark)
    end)

    it("starts timer for spinner animation", function()
      indicators.set_indicator(1, 0, "running")
      local has_timer_start = false
      for _, call in ipairs(mock.calls) do
        if call == "uv_timer_start" then
          has_timer_start = true
          break
        end
      end
      assert.is_true(has_timer_start)
    end)
  end)

  -------------------------------------------------------------------------
  -- clear_all
  -------------------------------------------------------------------------

  describe("clear_all", function()
    it("clears namespace and stops timer", function()
      indicators.set_indicator(1, 0, "running")
      mock.reset_calls()
      indicators.clear_all(1)
      local has_clear_namespace = false
      for _, call in ipairs(mock.calls) do
        if call == "nvim_buf_clear_namespace" then
          has_clear_namespace = true
          break
        end
      end
      assert.is_true(has_clear_namespace)
    end)

    it("does not error on invalid buffer", function()
      indicators.clear_all(nil)  -- should not crash
    end)
  end)

  -------------------------------------------------------------------------
  -- concurrent spinners
  -------------------------------------------------------------------------

  describe("concurrent spinners", function()
    it("keeps first spinner timer when second starts on different buffer", function()
      indicators.set_indicator(1, 0, "running")
      mock.reset_calls()

      indicators.set_indicator(2, 0, "running")

      local timer_start_count = 0
      for _, call in ipairs(mock.calls) do
        if call == "uv_timer_start" then
          timer_start_count = timer_start_count + 1
        end
      end
      assert.equals(1, timer_start_count,
        "second spinner should create a new timer (not stop the first)")
    end)

    it("stops only the completed spinner's timer, not other spinners", function()
      indicators.set_indicator(1, 0, "running")
      indicators.set_indicator(2, 0, "running")
      mock.reset_calls()

      indicators.set_indicator(1, 0, "success", 42)

      local timer_stop_count = 0
      for _, call in ipairs(mock.calls) do
        if call == "uv_timer_stop" then
          timer_stop_count = timer_stop_count + 1
        end
      end
      assert.equals(1, timer_stop_count,
        "should stop only one timer (the completed spinner)")
    end)
  end)
end)
