-- Lua variables file for Poste HTTP import demo
-- Exports a table; each field becomes accessible as m.<key> in .http files
local M = {}

-- Simple values
M.an_int = 100
M.a_string = "hello from lua"
M.a_float = 3.14
M.a_bool = true

-- Objects (Lua tables)
M.person = { name = "Lex", age = 23, role = "admin" }

-- Arrays (1-indexed in Lua)
M.tags = { "rust", "lua", "neovim", "poste" }

-- Nested data
M.config = {
  endpoint = "https://api.example.com",
  timeout = 5000,
  retry = 3,
}

-- Mixed
M.users = {
  { id = 1, name = "alice", email = "alice@test.com" },
  { id = 2, name = "bob",   email = "bob@test.com" },
}

return M