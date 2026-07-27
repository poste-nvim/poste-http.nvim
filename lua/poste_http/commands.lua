local state = require("poste_http.state")
local completion = require("poste_http.http.completion")
local symbols = require("poste_http.http.symbols")

local M = {}

local commands = {
  {
    name = "PosteRun",
    handler = function()
      require("poste_http.http.run").run_request()
    end,
    opts = { desc = "Run request at cursor" },
  },
  {
    name = "PosteEnv",
    handler = function(args)
      local env_mod = require("poste_http.http.env")
      if args.args == "" then
        vim.notify("Current environment: " .. state.current_env, vim.log.levels.INFO)
      else
        env_mod.set_env(args.args)
      end
    end,
    opts = { nargs = "?", desc = "Switch environment or show current" },
  },
  {
    name = "PostePasteCurl",
    handler = function()
      require("poste_http.http.curl").paste_curl("+")
    end,
    opts = { desc = "Paste curl command from clipboard as HTTP request" },
  },
  {
    name = "PosteImportOpenAPI",
    handler = function()
      require("poste_http.http.import_openapi").run()
    end,
    opts = { desc = "Import OpenAPI 3.x spec as .http files" },
  },
  {
    name = "PosteImportSwagger",
    handler = function()
      require("poste_http.http.import_swagger").run()
    end,
    opts = { desc = "Import Swagger 2.0 spec as .http files" },
  },
  {
    name = "PosteImportPostman",
    handler = function()
      require("poste_http.http.import_postman").run()
    end,
    opts = { desc = "Import Postman collection as .http files" },
  },
  {
    name = "PosteCopyAsCurl",
    handler = function()
      require("poste_http.http.copy").copy_to_clipboard("+")
    end,
    opts = { desc = "Copy current request as curl command to clipboard" },
  },
  {
    name = "PosteHelp",
    handler = function()
      require("poste_http.help").open()
    end,
    opts = { desc = "Show Poste keymap help" },
  },
  {
    name = "PosteImportResolve",
    handler = function()
      local import = require("poste_http.http.import")
      local lines = import.status()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, "poste://import-status")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].filetype = "poste"
      vim.bo[buf].modifiable = false
      local width = 80
      local height = math.min(#lines + 2, 20)
      local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.max(0, (vim.o.lines - height) / 2 - 1),
        col = math.max(0, (vim.o.columns - width) / 2),
        style = "minimal",
        border = "single",
        title = " Import Resolution Status ",
        title_pos = "center",
      })
      vim.keymap.set("n", "q", function() pcall(vim.api.nvim_win_close, win, true) end,
        { buffer = buf, noremap = true, silent = true })
      vim.api.nvim_buf_attach(buf, false, { on_detach = function() pcall(vim.api.nvim_win_close, win, true) end })
    end,
    opts = { desc = "Show import resolution status" },
  },
  {
    name = "PosteCmpStatus",
    handler = function()
      vim.notify(completion.status(), vim.log.levels.INFO)
    end,
    opts = { desc = "Check poste completion status" },
  },
  {
    name = "PosteCmpProfile",
    handler = function()
      completion.profile()
    end,
    opts = { desc = "Profile poste completion performance" },
  },
  {
    name = "PosteSymbols",
    handler = function()
      symbols.show_symbols()
    end,
    opts = { desc = "Show symbol outline (all HTTP requests)" },
  },
  {
    name = "PosteOutline",
    handler = function()
      symbols.show_symbols()
    end,
    opts = { desc = "Show symbol picker (all HTTP requests)" },
  },
  {
    name = "PosteFormatHttp",
    handler = function()
      local format_file = require("poste_http.http.format_file")
      local changed = format_file.format_buffer()
      if changed then
        vim.notify("poste: formatted", vim.log.levels.INFO)
      else
        vim.notify("poste: already formatted", vim.log.levels.INFO)
      end
    end,
    opts = { desc = "Format .http buffer" },
  },
  {
    name = "PosteHttpHistory",
    handler = function()
      require("poste_http.http.history").show()
    end,
    opts = { desc = "Show HTTP request history" },
  },
  {
    name = "PosteClearCache",
    handler = function()
      local format = require("poste_http.http.format")
      local cleaned = format.clean_response_cache()
      vim.notify(string.format("[Poste] Cleared %d old response file(s)", cleaned), vim.log.levels.INFO)
    end,
    opts = { desc = "Remove old cached response files from stdpath(cache)/poste_res/" },
  },
  {
    name = "PosteTSInspect",
    handler = function()
      require("poste_http.http.treesitter").inspect()
    end,
    opts = { desc = "Inspect tree-sitter parse tree for current buffer" },
  },
}

function M.setup()
  for _, cmd in ipairs(commands) do
    vim.api.nvim_create_user_command(cmd.name, cmd.handler, cmd.opts)
  end
end

function M.status()
  return string.format("[env: %s]", state.current_env)
end

return M