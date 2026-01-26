#!/usr/bin/env bash
#
# RubikSolver test runner.
#
# Usage:
#   scripts/test.sh              # unit tests
#   scripts/test.sh unit         # unit tests
#   scripts/test.sh ui           # UI tests
#   scripts/test.sh cli          # rubik-cli end-to-end tests
#   scripts/test.sh plugin       # OpenCode plugin unit tests
#   scripts/test.sh all          # unit + UI + CLI + plugin tests
#   scripts/test.sh coverage     # unit tests with a coverage report
#   scripts/test.sh list         # list available Xcode tests
#
# Environment:
#   SCHEME        Xcode scheme (default: RubikSolver)
#   CONFIGURATION Build configuration (default: Debug)
#   DESTINATION   xcodebuild destination (default: platform=macOS)
#   RESULT_BUNDLE Optional path for a .xcresult bundle

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="${PROJECT:-RubikSolver.xcodeproj}"
SCHEME="${SCHEME:-RubikSolver}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
MODE="${1:-unit}"

COMMON_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "$DESTINATION"
)

if [[ -n "${RESULT_BUNDLE:-}" ]]; then
  COMMON_ARGS+=(-resultBundlePath "$RESULT_BUNDLE")
fi

run_unit() {
  xcodebuild "${COMMON_ARGS[@]}" test -only-testing:RubikSolverTests
}

run_ui() {
  xcodebuild "${COMMON_ARGS[@]}" test -only-testing:RubikSolverUITests
}

run_cli() {
  "$ROOT_DIR/tools/rubik-cli/tests/cli.sh"
}

run_plugin() {
  node --experimental-strip-types --test \
    "$ROOT_DIR/.opencode/plugins/rubik-solver/lib.test.ts"
}

case "$MODE" in
  unit)
    run_unit
    ;;
  ui)
    run_ui
    ;;
  cli)
    run_cli
    ;;
  plugin)
    run_plugin
    ;;
  all)
    run_unit
    run_cli
    run_plugin
    run_ui
    ;;
  coverage)
    xcodebuild "${COMMON_ARGS[@]}" -enableCodeCoverage YES test -only-testing:RubikSolverTests
    ;;
  list)
    xcodebuild "${COMMON_ARGS[@]}" -list
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    sed -n '4,20p' "$0" >&2
    exit 2
    ;;
esac
