#!/bin/sh
# Run before pushing to GitHub. Exit with 1 to block the push.
set -e
echo "Running tests..."
flutter test
if [ -d functions ] && [ -f functions/package.json ]; then
  echo "Running Cloud Functions tests..."
  (cd functions && npm test)
fi
echo "All tests passed."
