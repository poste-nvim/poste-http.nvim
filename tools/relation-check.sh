#!/usr/bin/env bash
set -euo pipefail

# relation-check.sh — Pre-flight code relation analyzer for poste-http.nvim
#
# Usage:
#   tools/relation-check.sh                  # run all checks
#   tools/relation-check.sh set-lines        # nvim_buf_set_lines + sanitize
#   tools/relation-check.sh state <field>    # state field lifecycle
#   tools/relation-check.sh format           # format function callers
#   tools/relation-check.sh pre-render       # pre-render consistency
#   tools/relation-check.sh session          # request session lifecycle
#   tools/relation-check.sh all              # same as no-args
#
# Run this BEFORE making changes to catch incomplete modifications.
# Requires ripgrep. Exits non-zero when an expected directory is missing.

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; GRAY='\033[90m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Module roots. This repo owns `lua/poste-http/` only — each other protocol is
# its own repo (AGENTS.md "Module name ownership"), so there is no
# `lua/poste/sql/` sibling to check here.
ROOT_DIR="lua/poste-http/"
HTTP_DIR="lua/poste-http/http/"

# Fields that are intentionally persistent — always-current values, config, or caches.
# These trigger ⚠ "NEVER cleared" but that's by design, not a bug.
# Request-scoped fields must be cleared by state.clear_request_scoped();
# persistent fields are exempt.
EXEMPT_FIELDS="current_env|config|http_history|http_history_id_counter|http_history_max|last_request|log|global_vars|global_headers|script_variables|global_vars_sources|global_headers_sources|script_variables_sources|_http_session|_exec_context|_split_override|_busy"

check_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "require $1"; exit 1; }; }
check_cmd rg

cd "$PROJECT_ROOT"

# A check whose failure mode is silence is worse than no check: this script
# spent the whole post-protocol-split era pointing at `lua/poste/http/`, which
# no longer exists, so every section printed [SKIP] and the run looked clean.
# Missing input is now a hard failure.
require_dir() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo -e "${RED}FATAL: expected directory $dir does not exist.${NC}"
    echo -e "${RED}       Update ROOT_DIR/HTTP_DIR in $0 to match the current layout.${NC}"
    exit 1
  fi
}

###############################################################################
# nvim_buf_set_lines + sanitize_lines coverage
###############################################################################
check_set_lines() {
  echo -e "${BOLD}${CYAN}═══ nvim_buf_set_lines + sanitize_lines coverage${NC}"
  echo -e "${DIM}  ✗ = no sanitize_lines in the surrounding block. That is a prompt to"
  echo -e "    verify the lines cannot carry embedded newlines (nvim_buf_set_lines"
  echo -e "    rejects them); sites that split their input themselves are fine.${NC}"
  require_dir "$HTTP_DIR"

  while IFS= read -r line; do
    local file="${line%%:*}"
    local lineno="${line#*:}"; lineno="${lineno%%:*}"
    local near="" near_status=""
    if near=$(rg -n -B5 -A2 "nvim_buf_set_lines" "$file" | rg -m1 "sanitize_lines" 2>/dev/null); then
      near_status="${GREEN}✓ sanitize_lines nearby${NC}"
    else
      near_status="${RED}✗ NO sanitize_lines nearby${NC}"
    fi
    echo -e "  ${GRAY}$file:$lineno${NC} $near_status"
  done < <(rg -n "nvim_buf_set_lines" "$HTTP_DIR" --type lua | rg -v ":\s*--" | sort)

  # also check highlight functions that compute end_col from line length
  echo
  echo -e "${BOLD}${DIM}  --- highlight functions using #line as end_col (risk: OOB if lines differ)${NC}"
  while IFS= read -r line; do
    echo -e "  ${GRAY}$line${NC}"
  done < <(rg -n "end_col.*#line\|#lines\|#lines\[" "$HTTP_DIR" --type lua || echo "  (none)")
}

###############################################################################
# state field lifecycle
###############################################################################
check_state() {
  local field="${1:-}"
  local pattern="state\.${field}"
  require_dir "$ROOT_DIR"

  if [ -z "$field" ]; then
    echo -e "${BOLD}${CYAN}═══ state field lifecycle (all fields)${NC}"
    local fields
    fields=$(rg -o "state\.\w+" "$ROOT_DIR" --type lua -g '!tests/' | sed 's/.*state\.//' | sort -u | head -40)
    for f in $fields; do
      local exempt=0
      echo "$f" | rg -q "^($EXEMPT_FIELDS)$" && exempt=1
      echo -e "${BOLD}  $f${NC}$([ "$exempt" -eq 1 ] && echo " ${DIM}(exempt — intentional persistence)${NC}")"
      local file
      for file in $(rg -l "state\.$f\b" "$ROOT_DIR" --type lua -g '!tests/'); do
        local set_count=0 read_count=0 clear_count=0
        set_count=$(rg -c "state\.${f}\b(\.\w+)?\s*=" "$file" 2>/dev/null || echo 0)
        clear_count=$(rg -c "state\.${f}\b(\.\w+)?\s*=\s*nil" "$file" 2>/dev/null || echo 0)
        read_count=$(rg -c "state\.${f}\b" "$file" 2>/dev/null || echo 0)
        read_count=$((read_count - set_count))
        echo -e "    ${GRAY}$file${NC}  SET=${CYAN}$set_count${NC} READ=${YELLOW}$read_count${NC} CLEAR=${RED}$clear_count${NC}"
        if [ "$exempt" -eq 0 ] && [ "$set_count" -gt 0 ] && [ "$clear_count" -eq 0 ]; then
          echo -e "    ${RED}    ⚠  WRITTEN but NEVER cleared!${NC}"
        fi
      done
    done
    return
  fi

  local exempt=0
  echo "$field" | rg -q "^($EXEMPT_FIELDS)$" && exempt=1
  echo -e "${BOLD}${CYAN}═══ state.$field lifecycle${NC}$([ "$exempt" -eq 1 ] && echo " ${DIM}(exempt — intentional persistence)${NC}")"
  local state_pattern="state\.${field}\b"
  local assign_pattern="state\.${field}\b(\.\w+)?\s*="
  local clear_pattern="state\.${field}\b(\.\w+)?\s*=\s*nil"
  local set_total=0 clear_total=0

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    # SET: assignment (including sub-fields)
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo -e "  SET  ${GRAY}$line${NC}"; ((set_total++))
    done < <(rg -n "$assign_pattern" "$file" 2>/dev/null || true)
    # CLEAR: ... = nil (including sub-fields)
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo -e "  ${RED}CLEAR${NC} ${GRAY}$line${NC}"; ((clear_total++))
    done < <(rg -n "$clear_pattern" "$file" 2>/dev/null || true)
    # READ: any non-assignment usage
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      # skip assignment lines (already counted above)
      if echo "$line" | rg -q "=\s*nil"; then continue; fi
      if echo "$line" | rg -q "=\s*\$"; then continue; fi
      if echo "$line" | rg -q "$assign_pattern"; then continue; fi
      echo -e "  READ ${GRAY}$line${NC}"
    done < <(rg -n "$state_pattern" "$file" 2>/dev/null || true)
  done < <(rg -l "$state_pattern" "$ROOT_DIR" --type lua -g '!tests/')

  echo
  if [ "$exempt" -eq 1 ]; then
    echo -e "  ${DIM}  Skipped — field is exempt (intentional persistence)${NC}"
  elif [ "$set_total" -gt "$clear_total" ]; then
    echo -e "  ${RED}⚠  SET ($set_total) > CLEAR ($clear_total) — possible stale state${NC}"
  elif [ "$set_total" -eq 0 ]; then
    echo -e "  ${YELLOW}  No SETs found (state.$field may be computed or unused)${NC}"
  else
    echo -e "  ${GREEN}✓ SET ($set_total) ≤ CLEAR ($clear_total)${NC}"
  fi
}

###############################################################################
# format function callers
###############################################################################
check_format() {
  echo -e "${BOLD}${CYAN}═══ format function definitions + callers${NC}"
  require_dir "$HTTP_DIR"

  # define all format functions
  echo -e "${BOLD}${DIM}  --- definitions in format.lua${NC}"
  local funcs=()
  while IFS= read -r line; do
    local func_name
    func_name=$(echo "$line" | rg -o "function\s+M\.(\w+)" | sed 's/function M\.//')
    [ -n "$func_name" ] && funcs+=("$func_name")
    echo -e "  ${GRAY}$line${NC}"
  done < <(rg -n "^function M\.(format_|sanitize_)" "${HTTP_DIR}format.lua" 2>/dev/null || true)

  echo
  echo -e "${BOLD}${DIM}  --- callers across http/ lua${NC}"
  for fn in "${funcs[@]}"; do
    local count=0 files_with=()
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local c="${line##*:}"
      count=$((count + c))
      files_with+=("$line")
    done < <(rg -c "format\.$fn\b" "$HTTP_DIR" --type lua 2>/dev/null || true)
    [ "$count" -eq 0 ] && continue
    local file_list=""
    for f in "${files_with[@]}"; do file_list="$file_list ${f%%:*}"; done
    echo -e "${BOLD}  format.$fn${NC} (called $count times across: $file_list)"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo -e "    ${GRAY}$line${NC}"
    done < <(rg -n "format\.$fn\b" "$HTTP_DIR" --type lua 2>/dev/null | head -10)
  done

  # check sibling paths: view.lua calls format functions
  echo
  echo -e "${BOLD}${DIM}  --- render paths in view.lua${NC}"
  while IFS= read -r line; do
    echo -e "  ${GRAY}$line${NC}"
  done < <(rg -n "function M\.(show_view|render_view|render_detail|show_verbose)" "${HTTP_DIR}view.lua" 2>/dev/null || echo "  (none)")

  # check history module also calls format
  if [ -f "${HTTP_DIR}history.lua" ]; then
    echo
    echo -e "${BOLD}${DIM}  --- format calls from history.lua${NC}"
    while IFS= read -r line; do
      echo -e "  ${GRAY}$line${NC}"
    done < <(rg -n "format\.(format_|sanitize_)" "${HTTP_DIR}history.lua" 2>/dev/null || echo "  (none)")
  fi
}

###############################################################################
# pre-render path consistency
###############################################################################
check_prerender() {
  echo -e "${BOLD}${CYAN}═══ pre-render/cached buffer consistency${NC}"
  require_dir "$HTTP_DIR"

  echo -e "${BOLD}${DIM}  --- pre-render functions${NC}"
  while IFS= read -r line; do
    echo -e "  ${GRAY}$line${NC}"
  done < <(rg -n "prepare_multi_responses\b|M\.render_" "$HTTP_DIR" --type lua -g '!tests/' 2>/dev/null | head -20 || echo "  (none)")

  echo
  echo -e "${BOLD}${DIM}  --- apply_highlights / apply_extmarks calls${NC}"
  while IFS= read -r line; do
    echo -e "  ${GRAY}$line${NC}"
  done < <(rg -n "apply_verbose_highlights|apply_request_highlights|apply_file_link_highlight|setup_json_buffer|nvim_buf_set_extmark" "$HTTP_DIR" --type lua -g '!tests/' 2>/dev/null || echo "  (none)")
}

###############################################################################
# session lifecycle
###############################################################################
check_session() {
  echo -e "${BOLD}${CYAN}═══ session lifecycle (run_* must begin a session)${NC}"
  require_dir "$HTTP_DIR"

  local ok=1
  if rg -q 'session\.begin|poste-http\.http\.session' "${HTTP_DIR}run.lua" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} http/run.lua creates a request session"
  else
    echo -e "  ${RED}✗${NC} http/run.lua missing session.begin"
    ok=0
  fi

  # Request-scoped fields that state.clear_request_scoped() must clear.
  # session.begin() delegates to it, so that is the single place to check.
  local required_clears="last_response last_responses response_index last_assertion_results last_errors last_script_logs pending_request"
  for f in $required_clears; do
    if rg -q "M\.${f}\s*=\s*nil" "${ROOT_DIR}state.lua" 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} clear_request_scoped clears state.$f"
    else
      echo -e "  ${RED}✗${NC} clear_request_scoped does not clear state.$f"
      ok=0
    fi
  done

  # run.lua must not re-parse method/headers from buffer lines
  if rg -n "text:match\(\"\^\\(%S\\+\\)%s\\+\"\|request_found\s*=\s*true" "${HTTP_DIR}run.lua" 2>/dev/null | rg -q .; then
    echo -e "  ${YELLOW}⚠${NC} run.lua still has Lua request-line re-parse patterns"
  else
    echo -e "  ${GREEN}✓${NC} run.lua has no Lua request-block re-parse loop"
  fi

  # describe module must exist
  if [ -f "${HTTP_DIR}describe.lua" ]; then
    echo -e "  ${GREEN}✓${NC} http/describe.lua present (single parse authority)"
  else
    echo -e "  ${RED}✗${NC} http/describe.lua missing"
    ok=0
  fi

  if [ "$ok" -eq 0 ]; then
    echo -e "  ${RED}session lifecycle check FAILED${NC}"
    return 1
  fi
  echo -e "  ${GREEN}session lifecycle check OK${NC}"
}

###############################################################################
# main
###############################################################################
main() {
  local mode="${1:-all}"
  shift 2>/dev/null || true

  case "$mode" in
    set-lines|set_lines)
      check_set_lines
      ;;
    state)
      check_state "${1:-}"
      ;;
    format)
      check_format
      ;;
    pre-render|prerender)
      check_prerender
      ;;
    session)
      check_session
      ;;
    all|"")
      echo -e "${BOLD}${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
      echo -e "${BOLD}${CYAN}│  poste-http code relation check                    │${NC}"
      echo -e "${BOLD}${CYAN}│  Run before editing to catch incomplete mods       │${NC}"
      echo -e "${BOLD}${CYAN}└─────────────────────────────────────────────────────┘${NC}"
      echo
      check_set_lines
      echo
      check_state
      echo
      check_format
      echo
      check_prerender
      echo
      check_session || exit 1
      ;;
    *)
      echo "usage: $0 [set-lines|state [field]|format|pre-render|session|all]"
      exit 1
      ;;
  esac
}

main "$@"
