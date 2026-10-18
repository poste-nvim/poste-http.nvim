-- `setup({ highlights = ... })` is the documented way to recolour Poste
-- groups. The attribute table must land on the plain group name AND on its
-- tree-sitter variants: `.http` buffers are highlighted by tree-sitter
-- captures (`@PosteMethodGET.poste_http`), so a plain-name-only override
-- styled the winbar and extmarks but silently left the source buffer on the
-- default colours. The override must also apply immediately at setup() time,
-- not only on the next ColorScheme/VimEnter autocmd.

local function fg(name)
  return vim.api.nvim_get_hl(0, { name = name }).fg
end

describe("highlight config overrides", function()
  it("apply immediately at setup() time", function()
    require("poste-http").setup({ highlights = { PosteStatus2xx = { fg = 0x112233 } } })
    assert.equals(0x112233, fg("PosteStatus2xx"))
  end)

  it("reach the plain group, the @ group and the @.poste_http group", function()
    require("poste-http").setup({ highlights = { PosteMethodGET = { fg = 0x445566 } } })
    assert.equals(0x445566, fg("PosteMethodGET"))
    assert.equals(0x445566, fg("@PosteMethodGET"))
    assert.equals(0x445566, fg("@PosteMethodGET.poste_http"))
  end)

  it("reach syntax-linked groups too", function()
    require("poste-http").setup({ highlights = { PosteHeaderKey = { fg = 0x778899 } } })
    assert.equals(0x778899, fg("PosteHeaderKey"))
    assert.equals(0x778899, fg("@PosteHeaderKey.poste_http"))
  end)

  it("do not invent @ groups for groups tree-sitter never captures", function()
    require("poste-http").setup({ highlights = { PosteStatus2xx = { fg = 0x00aa00 } } })
    assert.equals(0x00aa00, fg("PosteStatus2xx"))
    assert.is_true(vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "@PosteStatus2xx" })))
  end)
end)
