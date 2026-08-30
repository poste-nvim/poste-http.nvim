-- Minimal Neovim configuration for running tests
-- This file is loaded by plenary before running tests

-- Add the plugin to runtime path
vim.opt.runtimepath:append(".")

-- Optional: poste-ai.nvim (AI integration specs are skipped when absent)
if vim.fn.isdirectory("../poste-ai.nvim") == 1 then
  vim.opt.runtimepath:append("../poste-ai.nvim")
end

-- Make test helper modules loadable via require("helpers.*")
package.path = package.path
  .. ";./lua/poste-http/?.lua"
  .. ";./lua/poste-http/?/init.lua"
  .. ";./tests/?.lua"
  .. ";./tests/?/init.lua"
  .. ";./tests/helpers/?.lua"

-- Deterministic RNG across runs
math.randomseed(42)
-- Set up a dummy buffer for tests that need it
vim.api.nvim_buf_set_option(0, "filetype", "poste_http")
