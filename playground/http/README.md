# HTTP Playground

Manual verification fixtures for Poste's HTTP features. Start the test server,
then run `.http` files against it.

## Structure

```
http/
├── server/                     ← Docker test server (httpbin-like)
│   ├── docker-compose.yml      Start: docker compose -f server/docker-compose.yml up -d
│   ├── server.py               FastAPI server on port 8888
│   ├── Dockerfile
│   └── README.md
│
├── scenarios/                  ← .http files for manual testing
│   ├── test_server.http        Comprehensive endpoint test (50+ requests)
│   ├── variable_resolver_test.http
│   ├── variable_resolver_imported.http
│   └── lua_import_demo.http    Lua import feature demo (see data/lua_vars.lua)
│
└── data/                       ← Test data files
    ├── simple.txt
    ├── test_data.txt
    ├── lua_vars.lua             Lua variables for lua_import_demo.http
    ├── smoke_test.sh
    └── env.json
```

## Quick Start

```bash
# Start the test server
docker compose -f server/docker-compose.yml up -d

# Wait for health
curl -sf http://localhost:8888/health

# Run a test scenario
cargo run -- run --line 6 scenarios/test_server.http

# Stop the server
docker compose -f server/docker-compose.yml down
```

## Lua Import Feature

Import Lua variables for use in `.http` files:

```lua
-- data/lua_vars.lua
local M = {}
M.an_int = 100
M.person = { name = "Lex", age = 23 }
M.tags = { "rust", "lua", "neovim" }
return M
```

```http
import ./data/lua_vars.lua as m

@my_person = m.person

### Use in requests
POST /test
Content-Type: application/json

{
  "id": {{m.an_int}},
  "name": "{{m.person.name}}",
  "tags": ["{{m.tags[1]}}", "{{m.tags[2]}}"],
  "data": {{my_person}}
}
```

See `scenarios/lua_import_demo.http` for a full demo.
