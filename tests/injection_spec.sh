#!/usr/bin/env bash
# Injection test: verify JSON body injection works in Neovim
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

cat > "$TEST_DIR/test.http" << 'EOF'
### Create user
POST /users
Content-Type: application/json

{
  "name": "John",
  "email": "john@test.com"
}

### Next
GET /test
EOF

cat > "$TEST_DIR/inject.lua" << EOF
vim.cmd('edit $TEST_DIR/test.http')
local bufnr = vim.api.nvim_get_current_buf()
vim.bo[bufnr].filetype = 'poste_http'
vim.treesitter.start(bufnr, 'poste_http')

-- Wait for parser
vim.wait(500, function() return pcall(vim.treesitter.get_parser, bufnr) end)

-- Check injection query
local q = vim.treesitter.query.get('poste_http', 'injections')
local root = vim.treesitter.get_parser(bufnr):parse()[1]:root()

local found_json = false
for pattern, match, metadata in q:iter_matches(root, bufnr, 0, -1) do
  if metadata['injection.language'] == 'poste_json' then
    for id, nodes in pairs(match) do
      if q.captures[id] == 'injection.content' then
        for _, node in ipairs(nodes) do
          if node:type() == 'json_body' then
            found_json = true
            print('INJECTION_OK: json_body -> poste_json')
          end
        end
      end
    end
  end
end

if not found_json then
  print('INJECTION_FAIL: no json_body -> poste_json injection found')
end
vim.cmd('qall!')
EOF

nvim --headless -u NONE +"set rtp+=$PROJECT_DIR" -c "luafile $TEST_DIR/inject.lua" 2>&1 | grep -E 'INJECTION_' > "$TEST_DIR/out.txt" || true

if grep -q 'INJECTION_OK' "$TEST_DIR/out.txt"; then
  echo "PASS: JSON injection works"
  exit 0
else
  echo "FAIL: JSON injection not working"
  cat "$TEST_DIR/out.txt"
  exit 1
fi
