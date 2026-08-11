#!/bin/bash
# Development: regenerate parser.c from grammar.js and compile.
# Not needed by end users — parsers are compiled automatically by install.lua.
set -euo pipefail
cd "$(dirname "$0")/../tree-sitter-poste-http"

echo "Generating parser from grammar.js..."
tree-sitter generate

echo "Compiling..."
${CC:-cc} -c -Isrc/tree_sitter -fPIC -O2 -o src/parser.o src/parser.c
${CC:-cc} -shared -o tree-sitter-poste_http.so src/parser.o

echo "Done: tree-sitter-poste-http/src/parser.c"