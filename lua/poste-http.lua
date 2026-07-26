--- Standalone entry point for poste-http.nvim (no poste.nvim dependency).
--- Usage: require("poste-http").setup({ use_treesitter = { ... } })
local setup = require("poste_http").setup

local M = {}

function M.setup(opts)
  setup(opts)
end

return M