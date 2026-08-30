-- Tests for the shared HTTP semantics → highlight group mappings
-- (poste-http.ui.semantics).
--
-- Single source of truth replacing four method→highlight tables and two
-- status→highlight functions that had drifted (outline/symbols missing
-- OPTIONS/SCRIPT, verbose duplicating tables twice in one file).
-- The groups themselves are defined in http/highlights.lua.

local semantics = require("poste-http.ui.semantics")

describe("poste-http.ui.semantics", function()
  describe("method_hl", function()
    it("maps every documented method to its dedicated group", function()
      assert.equals("PosteMethodGET", semantics.method_hl("GET"))
      assert.equals("PosteMethodPOST", semantics.method_hl("POST"))
      assert.equals("PosteMethodPUT", semantics.method_hl("PUT"))
      assert.equals("PosteMethodDELETE", semantics.method_hl("DELETE"))
      assert.equals("PosteMethodPATCH", semantics.method_hl("PATCH"))
      assert.equals("PosteMethodHEAD", semantics.method_hl("HEAD"))
      assert.equals("PosteMethodOPTIONS", semantics.method_hl("OPTIONS"))
      assert.equals("PosteMethodScript", semantics.method_hl("SCRIPT"))
      assert.equals("PosteRun", semantics.method_hl("RUN"))
    end)

    it("is case-insensitive", function()
      assert.equals("PosteMethodGET", semantics.method_hl("get"))
      assert.equals("PosteMethodPOST", semantics.method_hl("Post"))
    end)

    it("falls back to PosteMethodOther for unknown/placeholder methods", function()
      assert.equals("PosteMethodOther", semantics.method_hl("TRACE"))
      assert.equals("PosteMethodOther", semantics.method_hl("--"))
      assert.equals("PosteMethodOther", semantics.method_hl(""))
      assert.equals("PosteMethodOther", semantics.method_hl(nil))
    end)
  end)

  describe("status_hl", function()
    it("maps status classes to their dedicated groups", function()
      assert.equals("PosteStatus2xx", semantics.status_hl(200))
      assert.equals("PosteStatus2xx", semantics.status_hl(299))
      assert.equals("PosteStatus3xx", semantics.status_hl(301))
      assert.equals("PosteStatus4xx", semantics.status_hl(404))
      assert.equals("PosteStatus5xx", semantics.status_hl(503))
    end)

    it("renders no-status/zero as a comment", function()
      assert.equals("Comment", semantics.status_hl(0))
      assert.equals("Comment", semantics.status_hl(nil))
      assert.equals("Comment", semantics.status_hl("-"))
      assert.equals("Comment", semantics.status_hl("-1"))
    end)

    it("accepts numeric strings", function()
      assert.equals("PosteStatus4xx", semantics.status_hl("404"))
    end)
  end)
end)
