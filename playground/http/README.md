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
│   ├── lua_import_demo.http    Lua import feature demo (see data/lua_vars.lua)
│   ├── orchestration_requests.http     Request library for client.run demos
│   ├── orchestration_demo.http          client.run orchestration demo
│   └── orchestration_run_directive.http import/run single-step demo
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

# In Neovim: open a scenario file, put the cursor on a request/run/SCRIPT line,
# and press <CR> (or :PosteRun).

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

## Request Orchestration (client.run)

`orchestration_demo.http` runs a whole flow from a single `SCRIPT` block:
login → profile → register 3 users in a loop → verify. The requests it calls
live in `orchestration_requests.http` and can also be executed one at a time
from `orchestration_run_directive.http` with the `run` directive.

The demo depends on the stateful demo API added to `server/server.py`
(`POST /api/login`, `GET /api/profile`, `POST /api/users`,
`GET /api/users`, `GET /api/users/{id}`). Login issues an in-memory token;
password `wrong` returns 401 so the failure-path demo in
`orchestration_demo.http` can show script abort + error rendering.
