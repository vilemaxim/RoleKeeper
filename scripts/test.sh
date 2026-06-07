#!/bin/bash
# RoleKeeper test script — runs all tests across the full stack.
# Called by the TDD MCP server before accepting a `success` call.
# Exit code 0 = all pass. Non-zero = failure (blocks state advance).

set -e
# Enable recursive glob expansion (**) so we can hand node a real
# file list. Node 18 (which the MCP host uses) does NOT understand
# glob patterns in `node --test`, so we must resolve them in bash.
shopt -s globstar nullglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMULATOR_PID=""

cleanup() {
  if [ -n "$EMULATOR_PID" ]; then
    echo ""
    echo ">>> Stopping Firebase emulators (PID $EMULATOR_PID)..."
    kill "$EMULATOR_PID" 2>/dev/null || true
    wait "$EMULATOR_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "================================================"
echo "  RoleKeeper Tests"
echo "================================================"

# --- Start Firebase emulators ---
echo ""
echo ">>> Starting Firebase emulators..."
cd "$ROOT_DIR"
firebase emulators:start \
  --only auth,functions,firestore,storage \
  --export-on-exit /tmp/rolekeeper-emulator-data \
  --import /tmp/rolekeeper-emulator-data \
  2>&1 | grep -E "(Emulator|Error|✔|✗|Started)" &
EMULATOR_PID=$!

# Wait for emulators to be ready
echo "    Waiting for emulators..."
for i in {1..30}; do
  if curl -s http://localhost:4000 > /dev/null 2>&1; then
    echo "    Emulators ready."
    break
  fi
  sleep 2
done

# --- Flutter tests ---
echo ""
echo ">>> [1/2] Flutter tests"
cd "$ROOT_DIR"
flutter test --no-pub
echo "    Flutter tests: PASSED"

# --- Functions tests ---
echo ""
echo ">>> [2/3] Functions tests"
cd "$ROOT_DIR/functions"
# Build TypeScript first, then run Node's built-in test runner.
# NOTE: `node --test lib/` does NOT recurse — it tries to load lib/index.js
# as a single test. And `node --test 'lib/**/*.test.js'` only works on
# node >= 21; the MCP host runs node 18, which treats the glob as a literal
# path. So expand the glob in bash and pass real files to node.
npm run build 2>&1
FUNC_TESTS=( lib/**/*.test.js )
if [ ${#FUNC_TESTS[@]} -eq 0 ]; then
  echo "    ERROR: no compiled *.test.js files found under functions/lib/"
  exit 1
fi
FIRESTORE_EMULATOR_HOST="localhost:8080" \
FIREBASE_AUTH_EMULATOR_HOST="localhost:9099" \
FUNCTIONS_EMULATOR_HOST="localhost:5001" \
  node --test "${FUNC_TESTS[@]}"
echo "    Functions tests: PASSED (${#FUNC_TESTS[@]} files)"

# --- Scripts tests (TS, pure helpers — no network, no emulator) ---
echo ""
echo ">>> [3/3] Scripts tests"
cd "$ROOT_DIR/scripts"
# Reuse the typescript compiler from functions/ so scripts/ does not need
# its own node_modules. Compiles scripts/*.ts → scripts/lib/, then runs
# Node's built-in test runner against the compiled output. Same node-18
# glob caveat as above — resolve in bash.
"$ROOT_DIR/functions/node_modules/.bin/tsc" --project tsconfig.json
SCRIPT_TESTS=( lib/**/*.test.js )
if [ ${#SCRIPT_TESTS[@]} -eq 0 ]; then
  echo "    ERROR: no compiled *.test.js files found under scripts/lib/"
  exit 1
fi
node --test "${SCRIPT_TESTS[@]}"
echo "    Scripts tests: PASSED (${#SCRIPT_TESTS[@]} files)"

echo ""
echo "================================================"
echo "  All tests PASSED"
echo "================================================"
