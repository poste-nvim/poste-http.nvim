local state = require("poste_http.state")
local _ = require("poste_http.indicators")
local M = {}

function M.setup_buffer_keymaps(buf)
  local keymap_opts = { buffer = buf, noremap = true, silent = true }
  local km = state.get_keymap
  local nav_ok, nav = pcall(require, "poste_http.http.nav")
  local run_ok, run = pcall(require, "poste_http.http.run")
  local run_request = run_ok and run.run_request or nil

  if run_request then
    local k = km("http_source", "run", "<CR>")
    if k then vim.keymap.set("n", k, run_request, keymap_opts) end
    k = km("http_source", "run_hsplit", "<M-CR>")
    if k then
      vim.keymap.set("n", k, function()
        state._split_override = "horizontal"
        run_request()
      end, keymap_opts)
    end
  end

  if nav_ok then
    local k = km("http_source", "jump_next", "]]")
    if k and nav.jump_next then vim.keymap.set("n", k, nav.jump_next, keymap_opts) end
    k = km("http_source", "jump_prev", "[[")
    if k and nav.jump_prev then vim.keymap.set("n", k, nav.jump_prev, keymap_opts) end
    k = km("http_source", "goto_definition", "gd")
    if k and nav.goto_definition then
      vim.keymap.set("n", k, function() nav.goto_definition() end, keymap_opts)
    end
    k = km("http_source", "goto_references", "grr")
    if k and nav.goto_references then vim.keymap.set("n", k, nav.goto_references, keymap_opts) end
    k = km("http_source", "show_var_value", "K")
    if k and nav.show_var_value then vim.keymap.set("n", k, nav.show_var_value, keymap_opts) end
  end

  local k = km("http_source", "quickfix_next", "]q")
  if k then vim.keymap.set("n", k, function() vim.cmd("cnext") end, keymap_opts) end
  k = km("http_source", "quickfix_prev", "[q")
  if k then vim.keymap.set("n", k, function() vim.cmd("cprev") end, keymap_opts) end

  k = km("http_source", "paste_curl", "<leader>rp")
  if k then
    vim.keymap.set("n", k, function()
      require("poste_http.http.curl").paste_curl("+")
    end, keymap_opts)
  end
  k = km("http_source", "copy_as_curl", "<leader>rc")
  if k then
    vim.keymap.set("n", k, function()
      require("poste_http.http.copy").copy_to_clipboard("+")
    end, keymap_opts)
  end
  k = km("http_source", "toggle_outline", "gs")
  if k then
    vim.keymap.set("n", k, function()
      require("poste_http.http.symbols").show_symbols()
    end, keymap_opts)
  end
  k = km("http_source", "pick_env", "<leader>vv")
  if k then vim.keymap.set("n", k, require("poste_http.http.env").pick_env, keymap_opts) end
  k = km("http_source", "show_history", "<leader>l")
  if k then
    vim.keymap.set("n", k, function()
      require("poste_http.http.history").show()
    end, keymap_opts)
  end
  k = km("http_source", "help", "g?")
  if k then
    vim.keymap.set("n", k, function() require("poste_http.help").open() end, keymap_opts)
  end

  local indicator_ns = vim.api.nvim_create_namespace("poste_indicator")
  local group = vim.api.nvim_create_augroup("PosteClearIndicators_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("TextChanged", {
    group = group, buffer = buf,
    callback = function()
      vim.api.nvim_buf_clear_namespace(buf, indicator_ns, 0, -1)
    end,
  })

  local fileref_ns = vim.api.nvim_create_namespace("poste_fileref_" .. buf)
  local function refresh_fileref_marks()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.api.nvim_buf_clear_namespace(buf, fileref_ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("^%s*[<>]%s+%S") and not line:find("{%", 1, true) then
        local path_start = line:match("^%s*[<>]%s+()")
        if path_start then
          vim.api.nvim_buf_set_extmark(buf, fileref_ns, i - 1, path_start - 1, {
            end_col = #line, hl_group = "PosteFileRef",
          })
        end
      end
    end
  end
  refresh_fileref_marks()
  local frg = vim.api.nvim_create_augroup("PosteFileref_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("TextChanged", {
    group = frg, buffer = buf,
    callback = refresh_fileref_marks,
  })
end

return M