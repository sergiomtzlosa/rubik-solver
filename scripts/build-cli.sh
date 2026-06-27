#!/usr/bin/env bash
#
# Build the rubik-cli command-line tool.
#
# The CLI links the same core objects as the macOS app: the exact solver
# engine, ckociemba, validation, orientation, and the neural/Core ML facade.
# No Xcode project or DerivedData is required.
#
# Usage:
#   scripts/build-cli.sh            # optimized build
#   scripts/build-cli.sh --debug    # debug build with symbols
#
# Output:
#   build/rubik-cli/rubik-cli

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CXX="${CXX:-clang++}"
OUT_DIR="$ROOT_DIR/build/rubik-cli"
OUT="$OUT_DIR/rubik-cli"

OPT_FLAGS=(-O2 -DNDEBUG)
if [[ "${1:-}" == "--debug" ]]; then
  OPT_FLAGS=(-O0 -g)
fi

mkdir -p "$OUT_DIR"

CORE_SOURCES=(
  "RubikSolver/RubikCore/RubikCube.cpp"
  "RubikSolver/RubikCore/RubikValidation.cpp"
  "RubikSolver/RubikCore/RubikOrientation.cpp"
  "RubikSolver/RubikCore/RubikSolverEngine.cpp"
  "RubikSolver/RubikCore/RubikCoreMLModel.mm"
  "RubikSolver/RubikCore/RubikNeuralSolver.mm"
  "RubikSolver/RubikCore/RubikMetalSolver.mm"
)

CKOCIEMBA_SOURCES=(
  "RubikSolver/RubikCore/ckociemba/coordcube.c"
  "RubikSolver/RubikCore/ckociemba/cubiecube.c"
  "RubikSolver/RubikCore/ckociemba/facecube.c"
  "RubikSolver/RubikCore/ckociemba/prunetable_helpers.c"
  "RubikSolver/RubikCore/ckociemba/search.c"
)

# ckociemba is C. Compile it with clang so the translation units stay C, then
# link the Objective-C++ CLI against the same objects the app uses.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rubik-cli.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

OBJECTS=()
for source in "${CKOCIEMBA_SOURCES[@]}"; do
  object="$TMP_DIR/$(basename "${source%.c}").o"
  clang -std=c11 -O2 -DNDEBUG \
    -I RubikSolver/RubikCore \
    -I RubikSolver/RubikCore/ckociemba/include \
    -c "$source" -o "$object"
  OBJECTS+=("$object")
done

"$CXX" -std=gnu++17 "${OPT_FLAGS[@]}" -fobjc-arc \
  -I RubikSolver/RubikCore \
  -I RubikSolver/RubikCore/ckociemba/include \
  -I tools/rubik-cli \
  tools/rubik-cli/main.mm \
  "${CORE_SOURCES[@]}" \
  "${OBJECTS[@]}" \
  -framework Foundation \
  -framework CoreML \
  -framework Metal \
  -o "$OUT"

echo "Built $OUT"
