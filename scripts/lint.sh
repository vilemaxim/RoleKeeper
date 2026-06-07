#!/bin/bash
# RoleKeeper lint script — runs all linters across the full stack.
# Run locally before pushing; also invoked by CI.
# Exit code 0 = all clean. Non-zero = failure.

set -e  # Exit immediately on any error

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "================================================"
echo "  RoleKeeper Lint"
echo "================================================"

# --- Flutter ---
echo ""
echo ">>> [1/2] Flutter analyze"
cd "$ROOT_DIR"
flutter analyze --no-pub
echo "    Flutter analyze: PASSED"

# --- Firebase Functions (TypeScript / ESLint) ---
echo ""
echo ">>> [2/2] Functions ESLint"
cd "$ROOT_DIR/functions"
npx eslint src/ --max-warnings 0
echo "    Functions ESLint: PASSED"

echo ""
echo "================================================"
echo "  All lint checks PASSED"
echo "================================================"
