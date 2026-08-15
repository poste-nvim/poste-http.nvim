local harness = require("helpers.gui_harness")

describe("highlights", function()
  before_each(function()
    harness.setup()
    package.loaded["poste-http.http.highlights"] = nil
  end)

  after_each(function()
    harness.teardown()
  end)

  it("registers all Poste highlight groups", function()
    require("poste-http.http.highlights")

    local nvim_set_hl_count = 0
    for _, call in ipairs(harness.calls) do
      if call == "nvim_set_hl" then
        nvim_set_hl_count = nvim_set_hl_count + 1
      end
    end

    assert.is_true(nvim_set_hl_count > 0,
      string.format("expected nvim_set_hl calls, got %d out of %d total calls",
        nvim_set_hl_count, #harness.calls))

    local hl_set = {}
    for i = 1, #harness.calls do
      if harness.calls[i] == "nvim_set_hl" then
        local detail = harness.calls[i + 1]
        if detail and type(detail) == "table" then
          hl_set[detail.name] = detail.val
        end
      end
    end

    local expected = {
      "PosteLatency", "PosteSeparator", "PosteRequestName", "PosteVarDef",
      "PosteVarAssign", "PosteVarValue", "PosteVarRef", "PosteMagicVar",
      "PosteMethodGET", "PosteMethodPOST", "PosteMethodPUT",
      "PosteMethodDELETE", "PosteMethodPATCH", "PosteMethodHEAD", "PosteMethodOPTIONS",
      "PosteMethodScript", "PosteMethodOther",
      "PosteUrl", "PosteQueryKey", "PosteQueryValue", "PosteHttpVersion",
      "PosteHeaderKey", "PosteHeaderSep", "PosteComment", "PosteImport",
      "PosteImportPath", "PosteImportAliasOpt", "PosteImportAlias",
      "PosteRunVarDef", "PosteRunVarAssign", "PosteRunVarValue",
      "PostePromptMarker", "PostePromptVar", "PostePromptOpts", "PostePromptOptSep",
      "PostePromptMappingField", "PostePromptMappingColon", "PostePromptMappingPath",
      "PostePreScript", "PosteAssertion", "PosteScriptMarker", "PosteExternalScript",
      "PosteFileUpload", "PosteFileRef", "PosteRequestBody",
      "PosteMultipartBoundary", "PosteMultipartBody",
      "PosteJsonString", "PosteJsonNumber", "PosteJsonBoolean", "PosteJsonNull",
      "PosteJsonBraces", "PosteJsonBrackets", "PosteJsonColon", "PosteJsonComma", "PosteJsonEscape",
      "PosteImportRef", "PosteImportRefAlias", "PosteImportRefDot", "PosteImportRefKey", "PosteImportRefIndex",
      "PosteSpinner", "PosteSuccess", "PosteError",
      "PosteStatus2xx", "PosteStatus3xx", "PosteStatus4xx", "PosteStatus5xx",
      "PosteVerboseKey", "PosteVerboseValue", "PosteVerboseSection", "PosteVerboseSeparator",
      "PosteHttpBoundaryBorder",
    }

    for _, name in ipairs(expected) do
      assert.is_not_nil(hl_set[name],
        string.format("highlight group '%s' should be defined", name))
    end
  end)
end)