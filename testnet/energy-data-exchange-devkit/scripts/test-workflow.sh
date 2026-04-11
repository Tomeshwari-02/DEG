#!/usr/bin/env bash
# Energy Data Exchange Devkit - Workflow Test Script
#
# Exercises the full beckn 2.0 transactional lifecycle against the local
# adapter testnet, verifying each step returns ACK.
#
# Usage:
#   ./scripts/test-workflow.sh                    # uses defaults
#   BAP_URL=http://host:8081/bap/caller ./scripts/test-workflow.sh

set -euo pipefail

BAP_URL="${BAP_URL:-http://localhost:8081/bap/caller}"
BPP_URL="${BPP_URL:-http://localhost:8082/bpp/caller}"
EXAMPLES="$(cd "$(dirname "$0")/.." && pwd)/examples/v2"

passed=0
failed=0
total=0

run_step() {
  local label="$1" url="$2" action="$3" file="$4"
  total=$((total + 1))
  local http_code body
  body=$(curl -s -w "\n%{http_code}" -X POST "$url/$action" \
    -H "Content-Type: application/json" \
    -d @"$EXAMPLES/$file" 2>&1)
  http_code=$(echo "$body" | tail -1)
  body=$(echo "$body" | sed '$d')

  local ack_status
  ack_status=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',{}).get('ack',{}).get('status','?'))" 2>/dev/null || echo "?")

  if [ "$http_code" = "200" ] && [ "$ack_status" = "ACK" ]; then
    printf "  \033[32m✓\033[0m %-45s %s %s\n" "$label" "$http_code" "$ack_status"
    passed=$((passed + 1))
  else
    printf "  \033[31m✗\033[0m %-45s %s %s\n" "$label" "$http_code" "$ack_status"
    if [ "$ack_status" = "NACK" ]; then
      echo "$body" | python3 -c "import sys,json; e=json.load(sys.stdin).get('message',{}).get('error',{}); print('    error:', e.get('message','')[:120])" 2>/dev/null || true
    fi
    failed=$((failed + 1))
  fi
}

echo ""
echo "Energy Data Exchange Devkit - Workflow Test"
echo "============================================"
echo "BAP: $BAP_URL"
echo "BPP: $BPP_URL"
echo ""

# Health checks
printf "Health checks: "
bap_base=$(echo "$BAP_URL" | sed 's|/bap/caller.*||')
bpp_base=$(echo "$BPP_URL" | sed 's|/bpp/caller.*||')
bap_health=$(curl -s -o /dev/null -w "%{http_code}" "$bap_base/health" 2>/dev/null || echo "000")
bpp_health=$(curl -s -o /dev/null -w "%{http_code}" "$bpp_base/health" 2>/dev/null || echo "000")
if [ "$bap_health" != "200" ] || [ "$bpp_health" != "200" ]; then
  echo "FAIL (BAP=$bap_health BPP=$bpp_health)"
  echo "Start the testnet first: cd install && docker compose -f docker-compose-adapter.yml up -d"
  exit 1
fi
echo "OK"
echo ""

# --- BAP-initiated actions (select → confirm → status → cancel) ---
echo "BAP actions (→ BAP caller → BPP receiver → sandbox):"
run_step "select"    "$BAP_URL" "select"  "select-request.json"
run_step "init"      "$BAP_URL" "init"    "init-request.json"
run_step "confirm"   "$BAP_URL" "confirm" "confirm-request.json"
run_step "status"    "$BAP_URL" "status"  "status-request.json"
run_step "cancel"    "$BAP_URL" "cancel"  "cancel-request.json"
echo ""

# --- BPP-initiated actions (on_select → on_confirm → on_status → on_cancel) ---
echo "BPP actions (→ BPP caller → BAP receiver → sandbox):"
run_step "on_select"             "$BPP_URL" "on_select" "on-select-response.json"
run_step "on_init"               "$BPP_URL" "on_init"   "on-init-response.json"
run_step "on_confirm"            "$BPP_URL" "on_confirm" "on-confirm-response.json"
run_step "on_status (processing)" "$BPP_URL" "on_status" "on-status-response-processing.json"
run_step "on_status (ready+dataPayload)" "$BPP_URL" "on_status" "on-status-response-ready.json"
run_step "on_cancel"             "$BPP_URL" "on_cancel" "on-cancel-response.json"
echo ""

# --- Summary ---
echo "============================================"
if [ "$failed" -eq 0 ]; then
  printf "\033[32mAll %d steps passed.\033[0m\n" "$total"
  exit 0
else
  printf "\033[31m%d/%d steps failed.\033[0m\n" "$failed" "$total"
  exit 1
fi
