--- Highlight group definitions for the Poste plugin.
--- Called at module-load time and on ColorScheme/VimEnter autocmds.
local state = require("poste-http.state")
local M = {}

--- Resolve highlight group links fully (follow chains of `link`).
local function resolve_hl(name)
  local hl = vim.api.nvim_get_hl(0, { name = name })
  while hl.link do
    hl = vim.api.nvim_get_hl(0, { name = hl.link })
  end
  return hl
end

--- Define all Poste highlight groups and register autocmds.
function M.setup()

  for _, pair in ipairs({
    { "PosteSpinner", "DiagnosticInfo" },
    { "PosteSuccess", "DiagnosticOk" },
    { "PosteError",   "DiagnosticError" },
  }) do
    local src = resolve_hl(pair[2])
    local fg = src.fg or src.ctermfg
    if not fg then
      fg = pair[1] == "PosteError" and 0xff0000
        or pair[1] == "PosteSuccess" and 0x00ff00
        or 0x00aaff
    end
    -- fg only, no bg — hl_mode="combine" on extmark handles bg inheritance
    vim.api.nvim_set_hl(0, pair[1], { fg = fg })
  end

  -- Source file syntax highlight groups (linked to standard groups).
  -- These provide sensible defaults for any colorscheme. Only-empty forms
  -- are set, so a user's `:highlight` override of one of these groups
  -- survives colorscheme switches; groups re-defined below with fixed
  -- colours (methods, boundary, …) do not — the `highlights` config table
  -- (state.apply_highlight_overrides) is the override that always persists.
  --
  -- Each group is defined in three forms:
  --   "PosteXxx"              — used by Vim syntax (syntax/poste_http.vim)
  --   "@PosteXxx"             — used by tree-sitter (generic)
  --   "@PosteXxx.poste_http"  — used by tree-sitter (language-specific)
  -- Guarded per form, not per group: the Vim syntax file's `hi def link`
  -- can beat this setup to the plain name (lazy-loading on
  -- filetype=poste_http sources the syntax file first, and so does
  -- tests/minimal_init.lua) — the @ forms must still get their default.
  local function define_hl(name, link)
    for _, form in ipairs({ name, "@" .. name, "@" .. name .. ".poste_http" }) do
      if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = form })) then
        vim.api.nvim_set_hl(0, form, { link = link })
      end
    end
  end

  -- NOTE: entries here that are ALSO defined further down via
  -- define_hl_custom (PosteFileRef, PosteSeparator, PosteRequestName, the
  -- PosteMethod* colors, ...) have their link overridden by those fixed
  -- colors — editing the link target for them changes nothing. They stay
  -- in the table as the `@group.poste_http` fallback spelling; move a name
  -- out only when dropping the custom definition too.
  local syntax_links = {
    { "PosteLatency",    "Constant" },
    { "PosteSeparator",    "Delimiter" },
    { "PosteRequestName",  "Title" },
    { "PosteVarDef",       "Identifier" },
    { "PosteVarAssign",    "Operator" },
    { "PosteVarValue",     "String" },
    { "PosteVarRef",       "Identifier" },
    { "PosteMagicVar",     "Special" },
    { "PosteMethodGET",    "Keyword" },
    { "PosteMethodPOST",   "Keyword" },
    { "PosteMethodPUT",    "Keyword" },
    { "PosteMethodDELETE", "Keyword" },
    { "PosteMethodPATCH",  "Keyword" },
    { "PosteMethodHEAD",   "Keyword" },
    { "PosteMethodOPTIONS", "Keyword" },
    { "PosteMethodScript", "Keyword" },
    { "PosteMethodOther",  "Keyword" },
{ "PosteUrl",          "Normal" },
    { "PosteQueryKey",    "Type" },
    { "PosteQueryValue",  "String" },
    { "PosteHttpVersion", "Constant" },
    { "PosteHeaderKey",    "Type" },
    { "PosteHeaderSep",    "Delimiter" },
    { "PosteComment",      "Comment" },
    { "PosteOperator",     "PreProc" },
    { "PosteImport",       "Include" },
    { "PosteImportPath",   "String" },
    { "PosteImportAliasOpt", "Operator" },
    { "PosteImportAlias",  "Identifier" },
    { "PosteRunVarDef",    "PosteVarDef" },
    { "PosteRunVarAssign", "Operator" },
    { "PosteRunVarValue",  "String" },
    { "PostePromptMarker", "PosteVarDef" },
    { "PostePromptVar",    "PosteVarDef" },
    { "PostePromptOpts",   "String" },
    { "PostePromptOptSep", "Delimiter" },
    { "PostePromptMappingField", "Type" },
    { "PostePromptMappingColon", "Operator" },
    { "PostePromptMappingPath",  "Identifier" },
    { "PostePreScript",    "PreProc" },
    { "PosteAssertion",    "PreProc" },
    { "PosteScriptMarker", "Special" },
    { "PosteExternalScript", "Include" },
    { "PosteFileUpload",  "Include" },
    { "PosteFileRef",     "Include" },
    { "PosteRequestBody",  "Normal" },
    { "PosteMultipartBoundary", "Comment" },
    { "PosteMultipartBody", "Normal" },
    { "PosteJsonString",   "String" },
    { "PosteJsonNumber",   "Number" },
    { "PosteJsonBoolean",  "Boolean" },
    { "PosteJsonNull",     "Special" },
    { "PosteJsonBraces",   "Delimiter" },
    { "PosteJsonBrackets", "Delimiter" },
    { "PosteJsonColon",    "Delimiter" },
    { "PosteJsonComma",    "Delimiter" },
    { "PosteJsonEscape",   "SpecialChar" },
    { "PosteImportRef",    "PosteVarValue" },
    { "PosteImportRefAlias", "PosteImportAlias" },
    { "PosteImportRefDot",   "PosteVarAssign" },
    { "PosteImportRefKey",   "PosteVarValue" },
    { "PosteImportRefIndex", "Number" },
  }
  for _, pair in ipairs(syntax_links) do
    define_hl(pair[1], pair[2])
  end

  -- File references (< ./path / > ./path): underline like Include
  local include_hl = resolve_hl("Include")
  local function define_hl_custom(name, opts)
    vim.api.nvim_set_hl(0, name, opts)
    vim.api.nvim_set_hl(0, "@" .. name, opts)
    vim.api.nvim_set_hl(0, "@" .. name .. ".poste_http", opts)
  end

  define_hl_custom("PosteFileRef", {
    fg = include_hl.fg or 0x5c6370,
    sp = include_hl.fg or 0x5c6370,
    underline = true,
    bold = include_hl.bold,
    italic = include_hl.italic,
  })

  -- HTTP method colors: GET=green, POST=yellow, PUT=orange, DELETE=red
  define_hl_custom("PosteMethodGET",    { fg = 0x98c379, bold = true }) -- green
  define_hl_custom("PosteMethodPOST",   { fg = 0xe5c07b, bold = true }) -- yellow
  define_hl_custom("PosteMethodPUT",    { fg = 0xd19a66, bold = true }) -- orange
  define_hl_custom("PosteMethodDELETE", { fg = 0xe06c75, bold = true }) -- red
  define_hl_custom("PosteMethodPATCH",  { fg = 0xc678dd, bold = true }) -- magenta
  define_hl_custom("PosteMethodHEAD",   { fg = 0x56b6c2, bold = true }) -- cyan
  define_hl_custom("PosteMethodOPTIONS", { fg = 0x56b6c2, bold = true }) -- cyan (same as HEAD)
  define_hl_custom("PosteMethodScript", { fg = 0x8a5cf5, bold = true }) -- purple-blue
  define_hl_custom("PosteMethodOther",  { fg = 0x5c6370, bold = true }) -- gray

  -- Prompt variables: orange same as PUT
  define_hl_custom("PostePromptVar", { fg = 0xd19a66, bold = true })

  -- Multipart boundary: dark gray
  define_hl_custom("PosteMultipartBoundary", { fg = 0x5c6370 })

  -- Run directive: bold purple for "run", green for target, operator for vars
  define_hl_custom("PosteRun", { fg = 0xAA66FF, bold = true })
  define_hl_custom("PosteRunTarget", { fg = 0x44CC88 })
  define_hl_custom("PosteRunVars", { fg = 0xE5C07B })

  -- Request name: bold with a distinct color
  define_hl_custom("PosteSeparator", { fg = 0x439e9f, bold = true }) -- blue bold
  define_hl_custom("PosteRequestName", { fg = 0x439e9f, bold = true }) -- blue bold

  -- Winbar chrome (ui/winbar.lua): the env bar's env name + help hint, and
  -- the live-WebSocket-session key hint. These used to be spelled
  -- `PosteSqlMeta`/`PosteSqlMetaDim` — leftovers from the SQL split that no
  -- `nvim_set_hl` ever defined, so the bars rendered unstyled and could not
  -- be themed. tests/highlight_groups_spec.lua now guards the name set.
  -- Plain links (no @-language variants): winbar strings are not tree-sitter.
  vim.api.nvim_set_hl(0, "PosteMeta", { link = "Title" })
  vim.api.nvim_set_hl(0, "PosteMetaDim", { link = "Comment" })

  -- Symbol outline highlights
  vim.api.nvim_set_hl(0, "PosteSymbolCurrent", { bg = 0x3e4452, bold = true }) -- highlighted bg
  vim.api.nvim_set_hl(0, "PosteSymbolMethod", { fg = 0x98c379, bold = true })  -- green for [GET] [POST] etc

  -- Image preview metadata lines (format/image.lua). Defined here with every
  -- other group rather than lazily inside the renderer, so it is themeable
  -- and visible to the highlight-group drift guard.
  vim.api.nvim_set_hl(0, "PosteImageMeta", { fg = 0x9e9e9e })

  -- HTTP request block boundary: full-width rectangle background for the
  -- request under the cursor (poste_ai-style hl_eol extmarks)
  vim.api.nvim_set_hl(0, "PosteHttpBoundary", { bg = 0x24293f })
  vim.api.nvim_set_hl(0, "PosteHttpBoundaryBorder", { fg = 0x246e3b, bold = true })
  -- boundary_style="gutter" marks only the number column of the block. It
  -- links to the rectangle so one override recolours both; a `bg` of its
  -- own would drift from whatever theme the user pointed the rectangle at.
  vim.api.nvim_set_hl(0, "PosteHttpBoundaryGutter", { link = "PosteHttpBoundary" })

  -- Status code coloring in verbose view
  vim.api.nvim_set_hl(0, "PosteStatus2xx", { fg = 0x98c379, bold = true })          -- green
  vim.api.nvim_set_hl(0, "PosteStatus3xx", { fg = 0x56b6c2, bold = true })          -- cyan
  vim.api.nvim_set_hl(0, "PosteStatus4xx", { fg = 0xe5c07b, bold = true })          -- yellow
  vim.api.nvim_set_hl(0, "PosteStatus5xx", { fg = 0xe06c75, bold = true })          -- red

  -- Verbose view extmark highlights
  vim.api.nvim_set_hl(0, "PosteVerboseSeparator", { fg = 0x3e4452 })                -- dim line
  vim.api.nvim_set_hl(0, "PosteVerboseSection", { fg = 0x61afef, bold = true })      -- blue bold
  vim.api.nvim_set_hl(0, "PosteVerboseSubHeader", { fg = 0xABB2BF, bold = true })    -- bright bold
  vim.api.nvim_set_hl(0, "PosteVerboseKey", { fg = 0x7b78dd })                       -- magenta
  vim.api.nvim_set_hl(0, "PosteVerboseValue", { fg = 0x5c6370 })                     -- grey value

  -- Request tab extmark highlights (Key: bold, Value: gray)
  vim.api.nvim_set_hl(0, "PosteRequestKey", { fg = 0xABB2BF, bold = true })            -- bright bold
  vim.api.nvim_set_hl(0, "PosteRequestValue", { fg = 0x5c6370 })                       -- grey

  -- Assertions view extmark highlights
  vim.api.nvim_set_hl(0, "PosteAssertSummary", { fg = 0x98c379, bold = true })       -- green bold
  vim.api.nvim_set_hl(0, "PosteAssertSummaryFail", { fg = 0xe06c75, bold = true })   -- red bold
  vim.api.nvim_set_hl(0, "PosteAssertPass", { fg = 0x98c379 })                       -- green
  vim.api.nvim_set_hl(0, "PosteAssertFail", { fg = 0xe06c75, bold = true })          -- red bold
  vim.api.nvim_set_hl(0, "PosteAssertIconPass", { fg = 0x98c379, bold = true })      -- green bold ✓
  vim.api.nvim_set_hl(0, "PosteAssertIconFail", { fg = 0xe06c75, bold = true })      -- red bold ✘
  vim.api.nvim_set_hl(0, "PosteAssertError", { fg = 0xe06c75, italic = true })       -- red italic
  vim.api.nvim_set_hl(0, "PosteAssertLogHeader", { fg = 0x61afef, bold = true })     -- blue bold
  vim.api.nvim_set_hl(0, "PosteAssertLog", { fg = 0xABB2BF })                        -- bright
  vim.api.nvim_set_hl(0, "PosteAssertSep", { fg = 0x3e4452 })                        -- dim line
  vim.api.nvim_set_hl(0, "PosteAssertHint", { fg = 0x5c6370, italic = true })        -- gray italic for hints



  -- File link for binary response Open file: line — blue, underlined, clickable feel
  vim.api.nvim_set_hl(0, "PosteFileLink", { fg = 0x61afef, underline = true, sp = 0x61afef })

  state.apply_highlight_overrides({
    "PosteLatency", "PosteSpinner", "PosteSuccess", "PosteError",
    "PosteSeparator", "PosteRequestName", "PosteVarDef", "PosteVarAssign", "PosteVarValue", "PosteVarRef", "PosteMagicVar",
    "PosteMethodGET", "PosteMethodPOST",     "PosteMethodPUT", "PosteMethodDELETE",
    "PosteMethodPATCH", "PosteMethodHEAD", "PosteMethodOPTIONS", "PosteMethodScript", "PosteMethodOther",
    "PosteUrl", "PosteQueryKey", "PosteQueryValue", "PosteHttpVersion", "PosteHeaderKey", "PosteHeaderSep", "PosteComment",
    "PosteOperator",
    "PosteImport", "PosteImportPath", "PosteImportAliasOpt", "PosteImportAlias",
"PosteRequestBody",
"PosteMultipartBoundary",
    "PosteMultipartBody",
    "PosteRun", "PosteRunTarget", "PosteRunVars", "PosteRunVarDef", "PosteRunVarAssign", "PosteRunVarValue",
    "PostePromptMarker", "PostePromptVar", "PostePromptOpts",
    "PostePromptOptSep", "PostePromptMappingField", "PostePromptMappingColon", "PostePromptMappingPath",
    "PostePreScript", "PosteAssertion", "PosteScriptMarker", "PosteExternalScript",
    "PosteFileUpload", "PosteFileRef",
    "PosteJsonString", "PosteJsonNumber", "PosteJsonBoolean", "PosteJsonNull",
    "PosteJsonBraces", "PosteJsonBrackets", "PosteJsonColon", "PosteJsonComma",
    "PosteJsonEscape",
    "PosteSymbolCurrent", "PosteSymbolMethod",
    "PosteMeta", "PosteMetaDim",
    "PosteImageMeta",
    "PosteHttpBoundaryBorder",
    "PosteHttpBoundary",
    "PosteHttpBoundaryGutter",
    "PosteStatus2xx", "PosteStatus3xx", "PosteStatus4xx", "PosteStatus5xx",
    "PosteVerboseSeparator", "PosteVerboseSection", "PosteVerboseSubHeader", "PosteVerboseKey", "PosteVerboseValue",
    "PosteRequestKey", "PosteRequestValue",
    "PosteImportRef", "PosteImportRefAlias", "PosteImportRefDot", "PosteImportRefKey", "PosteImportRefIndex",
    "PosteAssertSummary", "PosteAssertSummaryFail",
    "PosteAssertPass", "PosteAssertFail",
    "PosteAssertIconPass", "PosteAssertIconFail",
    "PosteAssertError", "PosteAssertLogHeader", "PosteAssertLog",
    "PosteAssertSep", "PosteAssertHint",
    "PosteFileLink",
  })
end

-- Apply highlights immediately on require
M.setup()

-- Re-apply when colorscheme changes or after full startup
vim.api.nvim_create_autocmd("ColorScheme", { callback = M.setup })
vim.api.nvim_create_autocmd("VimEnter", { callback = M.setup, once = true })

return M
