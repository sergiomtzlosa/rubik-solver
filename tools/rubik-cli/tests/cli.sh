#!/usr/bin/env bash
#
# End-to-end tests for tools/rubik-cli.
#
# The suite is intentionally dependency-light: bash + python3 (for JSON
# assertions) and the CLI itself. Run directly or through scripts/test.sh cli.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

if [[ "${RUBIK_CLI_SKIP_BUILD:-0}" != "1" ]]; then
  "$ROOT_DIR/scripts/build-cli.sh" >/dev/null
fi

CLI="${RUBIK_CLI:-$ROOT_DIR/build/rubik-cli/rubik-cli}"
if [[ ! -x "$CLI" ]]; then
  echo "rubik-cli not found at $CLI" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for CLI JSON tests" >&2
  exit 2
fi

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf 'ok %d - %s\n' "$PASS" "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'not ok %d - %s\n' "$((PASS + FAIL))" "$1"
  printf '  %s\n' "$2"
}

assert_eq() {
  local name="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected [$expected], got [$actual]"
  fi
}

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit $expected, got $actual"
  fi
}

json_get() {
  python3 -c '
import json, sys
value = json.load(sys.stdin)
for key in sys.argv[1:]:
    if isinstance(value, list):
        value = value[int(key)]
    else:
        value = value[key]
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
' "$@"
}

capture() {
  local out_file err_file
  out_file="$(mktemp)"
  err_file="$(mktemp)"
  "$@" >"$out_file" 2>"$err_file"
  CAPTURE_CODE=$?
  CAPTURE_OUT="$(cat "$out_file")"
  CAPTURE_ERR="$(cat "$err_file")"
  rm -f "$out_file" "$err_file"
}

SOLVED="UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"
EDGE_FLIP="UUUUUUUFURRRRRRRRRFUFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"
CENTER_SWAP="UUUURUUUURRRRURRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"
COLOR_COUNT="RUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"
CORNER_TWIST="UUUUUUUURFRRRRRRRRFFUFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"
PARITY="UUUUUUUUURFRRRRRRRFRFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"
DUP_EDGE="UUUUUUUUURFRRRRRRRFFFFFFFFRDDDDDDDDDLLLLLLLLLBBBBBBBBB"
DUP_CORNER="UUUUUUUUURRFRRRRRRFFFFFFBFFDDDDDDDDDLLLLLLLLLRBBBBBBBB"

ORIENT_INPUT="URLBUDRULBFFLRUDLDUDBRFLRDURBFDDFLBLFBDRLUDLBUFRRBFBUF"
ORIENT_EXPECTED="URLBUDRULBFFLRUDLDBLUDFDURRRBFDDFLBLBLDULRDBFUFRRBFBUF"

# --- state ---------------------------------------------------------------

capture "$CLI" state
assert_exit "state defaults to solved" 0 "$CAPTURE_CODE"
assert_eq "state prints a solved facelet string" "$CAPTURE_OUT" "$SOLVED"

capture "$CLI" state --scramble 20 --seed 42 --json
assert_exit "state scramble succeeds" 0 "$CAPTURE_CODE"
SCRAMBLED_A="$CAPTURE_OUT"
SCRAMBLED_FACELETS="$(printf '%s' "$SCRAMBLED_A" | json_get facelets)"
assert_eq "state scramble move count" "$(printf '%s' "$SCRAMBLED_A" | json_get moveCount)" "0"
assert_eq "state scramble returns 20 moves" \
  "$(printf '%s' "$SCRAMBLED_A" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["scramble"]))')" "20"
capture "$CLI" state --scramble 20 --seed 42 --json
assert_eq "state scramble is deterministic" "$(printf '%s' "$SCRAMBLED_A" | json_get facelets)" \
  "$(printf '%s' "$CAPTURE_OUT" | json_get facelets)"

# --- verify --------------------------------------------------------------

capture "$CLI" verify --facelets "$SOLVED" --json
assert_exit "verify accepts the solved cube" 0 "$CAPTURE_CODE"
assert_eq "verify reports valid" "$(printf '%s' "$CAPTURE_OUT" | json_get code)" "valid"

check_invalid() {
  local name="$1" fixture="$2" expected_code="$3"
  capture "$CLI" verify --facelets "$fixture" --json
  assert_exit "verify rejects $name" 3 "$CAPTURE_CODE"
  assert_eq "verify $name error code" "$(printf '%s' "$CAPTURE_OUT" | json_get code)" "$expected_code"
}

check_invalid "an edge flip" "$EDGE_FLIP" "edge-flip"
check_invalid "a center swap" "$CENTER_SWAP" "center-color"
check_invalid "a color count" "$COLOR_COUNT" "color-count"
check_invalid "a corner twist" "$CORNER_TWIST" "corner-twist"
check_invalid "a parity error" "$PARITY" "parity"
check_invalid "a duplicate edge" "$DUP_EDGE" "edge-existence"
check_invalid "a duplicate corner" "$DUP_CORNER" "corner-existence"

capture "$CLI" verify --facelets "UUUUUUUUURRRRRRRRR"
assert_exit "verify rejects a short facelet string" 2 "$CAPTURE_CODE"

# --- orient --------------------------------------------------------------

capture "$CLI" orient --facelets "$ORIENT_INPUT" --json
assert_exit "orient recovers rotated faces" 0 "$CAPTURE_CODE"
assert_eq "orient returns the canonical facelets" \
  "$(printf '%s' "$CAPTURE_OUT" | json_get facelets)" "$ORIENT_EXPECTED"
assert_eq "orient is not ambiguous for a scrambled cube" \
  "$(printf '%s' "$CAPTURE_OUT" | json_get ambiguous)" "false"

capture "$CLI" orient --facelets "$EDGE_FLIP" --json
assert_exit "orient rejects an invalid cube" 8 "$CAPTURE_CODE"

# --- solve ---------------------------------------------------------------

capture "$CLI" solve --facelets "$SOLVED" --engine exact --json
assert_exit "exact solve of a solved cube succeeds" 0 "$CAPTURE_CODE"
assert_eq "exact solve reports already-solved" \
  "$(printf '%s' "$CAPTURE_OUT" | json_get status)" "already-solved"

capture "$CLI" solve --facelets "$SCRAMBLED_FACELETS" --engine exact --json
assert_exit "exact solve of a scrambled cube succeeds" 0 "$CAPTURE_CODE"
assert_eq "exact solution is verified" "$(printf '%s' "$CAPTURE_OUT" | json_get verified)" "true"
SOLUTION="$(printf '%s' "$CAPTURE_OUT" | json_get solution)"
if [[ -z "$SOLUTION" ]]; then
  fail "exact solve returns moves" "solution was empty"
else
  pass "exact solve returns moves"
fi

capture "$CLI" state --facelets "$SCRAMBLED_FACELETS" --moves "$SOLUTION"
assert_exit "replay of the exact solution succeeds" 0 "$CAPTURE_CODE"
assert_eq "replay of the exact solution reaches solved" "$CAPTURE_OUT" "$SOLVED"

capture "$CLI" solve --facelets "$EDGE_FLIP" --engine exact --json
assert_exit "exact solve rejects an invalid cube" 3 "$CAPTURE_CODE"
assert_eq "exact solve reports invalid-state" \
  "$(printf '%s' "$CAPTURE_OUT" | json_get status)" "invalid-state"

capture "$CLI" solve --facelets "$SOLVED" --engine neural --json
assert_exit "neural solve of a solved cube succeeds" 0 "$CAPTURE_CODE"
assert_eq "neural solve reports already-solved" \
  "$(printf '%s' "$CAPTURE_OUT" | json_get status)" "already-solved"

SHALLOW="$( "$CLI" state --moves "R U R' U' F2" )"
capture "$CLI" solve --facelets "$SHALLOW" --engine hybrid --neural-budget 1 --timeout 30 --json
assert_exit "hybrid solve succeeds or falls back cleanly" 0 "$CAPTURE_CODE"
assert_eq "hybrid result is verified" "$(printf '%s' "$CAPTURE_OUT" | json_get verified)" "true"

# A 20-move scramble is far beyond the bundled demo model's search budget.
# Neural mode must still return a verified solution via the exact fallback.
DEEP="$( "$CLI" state --scramble 20 --seed 42 )"
capture "$CLI" solve --facelets "$DEEP" --engine neural --neural-budget 0.1 --timeout 30 --json
assert_exit "neural solve falls back cleanly" 0 "$CAPTURE_CODE"
assert_eq "neural fallback is verified" "$(printf '%s' "$CAPTURE_OUT" | json_get verified)" "true"
assert_eq "neural fallback is reported" "$(printf '%s' "$CAPTURE_OUT" | json_get usedFallback)" "true"
assert_eq "neural fallback uses the exact engine" \
  "$(printf '%s' "$CAPTURE_OUT" | json_get engineUsed)" "exact"

# --- summary -------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
