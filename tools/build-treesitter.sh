#!/bin/bash
# Development: regenerate parser.c from grammar.js and compile.
# Not needed by end users — parsers are compiled automatically by install.lua.
set -euo pipefail
cd "$(dirname "$0")/../tree-sitter-poste-http"

echo "Generating parser from grammar.js..."
tree-sitter generate

echo "Compiling..."
${CC:-cc} -c -Isrc -fPIC -O2 -o src/parser.o src/parser.c
${CC:-cc} -shared -o src/parser.o src/parser.o

echo "Done: tree-sitter-poste-http/src/parser.c"