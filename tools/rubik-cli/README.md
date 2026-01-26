# rubik-cli

A verified Rubik's Cube solver for scripts and the OpenCode `rubik-solver`
plugin. The CLI links the same core used by the macOS app: ckociemba, full
cubie validation, 4^6 orientation recovery, and the Core ML neural facade.

## Build

```bash
scripts/build-cli.sh          # release build
scripts/build-cli.sh --debug  # debug build with symbols
```

The binary is written to `build/rubik-cli/rubik-cli` (git-ignored). No Xcode
project or DerivedData is needed. The pruning tables are cached in
`~/Library/Application Support/RubikSolver/ckociemba-cache` and reused by the
app.

## Facelet format

54 characters in face order **U R F D L B**, row-major within each face:

```
UUUUUUUUU RRRRRRRRR FFFFFFFFF DDDDDDDDD LLLLLLLLL BBBBBBBBB
```

Both standard letters (`U R F D L B`) and color letters (`W R G Y O B`) are
accepted, as are digits `0`–`5` for U/R/F/D/L/B. Whitespace is ignored.
A solved cube is:

```
UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB
```

## Commands

### `solve`

```bash
rubik-cli solve --facelets <54 chars> [--engine exact|neural|hybrid] [--json]
```

Validates the state first, then solves it. Every returned solution is replayed
and verified before it is printed. `hybrid` tries the neural search and falls
back to the exact solver; the result reports `usedFallback`.

Options:

| Option | Default | Meaning |
|---|---|---|
| `--engine` | `hybrid` | `exact` (CPU), `neural` (Core ML), `hybrid` (neural then exact) |
| `--timeout` | `30` | Exact solver timeout in seconds |
| `--neural-budget` | `4` | Neural search time budget in seconds |
| `--max-depth` | `24` | Exact solver maximum depth |
| `--beam-width` | model default | Neural beam width |
| `--max-nodes` | model default | Neural node budget |
| `--cache-dir` | Application Support | Pruning-table cache |
| `--no-verify` | off | Skip replay verification (not recommended) |
| `--no-simplify` | off | Keep the raw two-phase sequence |
| `--json` | off | Machine-readable JSON |

### `verify`

```bash
rubik-cli verify --facelets <54 chars> [--json]
```

Runs color-count, center-color, edge/corner existence, edge flip, corner twist,
and parity checks. Does not solve.

### `orient`

```bash
rubik-cli orient --facelets <54 chars> [--json]
```

Tries all 4^6 in-plane face rotations, validates each candidate, and returns
the canonical facelet string plus clockwise quarter-turns per face. Ambiguous
states (for example a solved cube) are flagged with `"ambiguous": true`.

### `state`

```bash
rubik-cli state [--facelets <54 chars>] [--moves "R U R' ..."] [--scramble N] [--seed N] [--json]
```

Applies moves to a fresh or supplied state and prints the resulting facelet
string. Without `--json` it prints only the 54-character string, so it can be
piped into `verify` or `solve`:

```bash
STATE=$(rubik-cli state --scramble 20 --seed 42)
rubik-cli solve --facelets "$STATE" --engine exact
```

`--scramble` is deterministic for a given `--seed`; the chosen seed is included
in JSON output.

## JSON output

All commands emit one JSON object on stdout when `--json` is used. Diagnostics
and model messages go to stderr, so the output is safe to pipe to `jq`.

`solve`:

```json
{
  "ok": true,
  "command": "solve",
  "status": "success",
  "engineRequested": "hybrid",
  "engineUsed": "exact",
  "usedFallback": true,
  "verified": true,
  "alreadySolved": false,
  "moveCount": 19,
  "moves": ["B", "D", "B2"],
  "solution": "B D B2",
  "timeMs": 2.6,
  "nodesExpanded": 0,
  "neuralModelAvailable": true,
  "validation": { "valid": true, "code": "valid", "message": "The cube state is valid." },
  "message": "Solved with the exact two-phase solver."
}
```

`verify` reports `valid`, `code`, and `message`. `orient` reports `success`,
`ambiguous`, `validCandidates`, `rotations`, and `facelets`. `state` reports
`facelets`, `solved`, `moveCount`, `moves`, and optionally `scramble`/`seed`.

## Exit codes

The exit code is stable and is the preferred way to branch in scripts:

| Code | Meaning |
|---|---|
| 0 | Success, valid cube, or already solved |
| 2 | Usage / argument error |
| 3 | Invalid cube state (see `validation.code`) |
| 4 | No solution / internal solver failure |
| 5 | Timeout |
| 6 | Cancelled |
| 7 | Solver busy |
| 8 | Orientation failed |

## OpenCode plugin

`.opencode/plugins/rubik-solver/index.ts` registers three tools:

- `rubik_solve` — solve a facelet string
- `rubik_verify` — validate a facelet string
- `rubik_orient` — recover face rotations

The plugin builds the CLI on first use and calls it with `spawn`/`execFile`
semantics (argument arrays, no shell interpolation), forwarding OpenCode's
`context.signal` so cancellation stops the child process. Configure a custom
binary with `RUBIK_CLI=/path/to/rubik-cli`.

Example prompt in OpenCode:

> Solve this cube: `UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB`

## Tests

```bash
tools/rubik-cli/tests/cli.sh   # end-to-end CLI tests
scripts/test.sh cli            # same, through the test runner
scripts/test.sh plugin         # plugin argument/formatting tests
```
