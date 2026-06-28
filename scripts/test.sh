#!/bin/bash
# RoleKeeper test script — runs all tests across the full stack.
# Run locally before pushing; also invoked by CI.
# Exit code 0 = all pass. Non-zero = failure.

set -e
# Enable recursive glob expansion (**) so we can hand node a real
# file list. Node 18 (which the MCP host uses) does NOT understand
# glob patterns in `node --test`, so we must resolve them in bash.
shopt -s globstar nullglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMULATOR_PID=""
STARTED_EMULATORS=0

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -tlnH 2>/dev/null | grep -qE "[:.]${port}\b"
    return $?
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  return 1
}

emulator_ui_ready() {
  curl -s http://localhost:4000 >/dev/null 2>&1
}

emulator_ports_blocked() {
  local port
  for port in 8080 9099 5001 9199 4000; do
    if port_in_use "$port"; then
      return 0
    fi
  done
  return 1
}

cleanup_stale_emulators() {
  echo "    Stale emulator ports detected — stopping orphaned Firebase processes..."
  pkill -f "cloud-firestore-emulator" 2>/dev/null || true
  pkill -f "firebase emulators:start" 2>/dev/null || true
  pkill -f "firebase-tools.*emulators" 2>/dev/null || true
  sleep 2
}

cleanup() {
  if [ "$STARTED_EMULATORS" -eq 1 ] && [ -n "$EMULATOR_PID" ]; then
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
if emulator_ui_ready; then
  echo ">>> Firebase emulators already running — reusing."
else
  if emulator_ports_blocked; then
    cleanup_stale_emulators
    if emulator_ports_blocked; then
      echo "    ERROR: Emulator ports (8080/9099/5001/9199/4000) are still in use."
      echo "    Stop the blocking process or run: firebase emulators:stop"
      exit 1
    fi
  fi

  echo ">>> Starting Firebase emulators..."
  cd "$ROOT_DIR"
  EMULATOR_LOG="$(mktemp /tmp/rolekeeper-emulator-XXXX.log)"
  firebase emulators:start \
    --only auth,functions,firestore,storage \
    --export-on-exit /tmp/rolekeeper-emulator-data \
    --import /tmp/rolekeeper-emulator-data \
    >"$EMULATOR_LOG" 2>&1 &
  EMULATOR_PID=$!
  STARTED_EMULATORS=1

  echo "    Waiting for emulators..."
  EMULATOR_READY=0
  for i in {1..30}; do
    if emulator_ui_ready; then
      echo "    Emulators ready."
      EMULATOR_READY=1
      break
    fi
    if ! kill -0 "$EMULATOR_PID" 2>/dev/null; then
      echo "    ERROR: Firebase emulators exited before becoming ready."
      tail -20 "$EMULATOR_LOG" 2>/dev/null || true
      exit 1
    fi
    sleep 2
  done

  if [ "$EMULATOR_READY" -ne 1 ]; then
    echo "    ERROR: Timed out waiting for emulator UI on port 4000."
    tail -20 "$EMULATOR_LOG" 2>/dev/null || true
    exit 1
  fi
fi

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
