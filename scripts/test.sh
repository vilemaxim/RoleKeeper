#!/bin/bash
# RoleKeeper test script — runs all tests across the full stack.
# Called by the TDD MCP server before accepting a `success` call.
# Exit code 0 = all pass. Non-zero = failure (blocks state advance).

set -e

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
echo ">>> [2/2] Functions tests"
cd "$ROOT_DIR/functions"
# Build TypeScript first, then run Node's built-in test runner
npm run build 2>&1
FIRESTORE_EMULATOR_HOST="localhost:8080" \
FIREBASE_AUTH_EMULATOR_HOST="localhost:9099" \
FUNCTIONS_EMULATOR_HOST="localhost:5001" \
  node --test lib/
echo "    Functions tests: PASSED"

echo ""
echo "================================================"
echo "  All tests PASSED"
echo "================================================"
