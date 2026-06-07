# 🧠 Task Learnings
**Task:** 002
**Role:** CODER

## Two infrastructure lessons surfaced during Task 002

### 1. `node --test` glob support is node-22+ only
The MCP server runs `bash scripts/test.sh` via `execSync` using the system `/usr/bin/node` (v18.19.1 on this host). Node 18's `--test` flag treats `'lib/**/*.test.js'` as a literal path and errors with `Could not find ...`. Cursor's bundled node (v22.22.0) supports the glob, so interactive testing masked the bug entirely. Fix: enable `shopt -s globstar nullglob` in scripts/test.sh and expand the glob into a bash array before passing to node. Adds explicit failure when zero test files are discovered (otherwise a typo'd path would silently pass).

### 2. TEST_OR_LINTING_FAILED unconditionally returns to CODER_TEST_CREATION
The MCP state machine routes every successful `TEST_OR_LINTING_FAILED` recovery back to `CODER_TEST_CREATION`, even if the original failure was during `CODER_IMPLEMENTATION`. This means recovering from a verification failure after the implementation is on disk produces a catch-22: you're back in Red phase but tests pass, triggering RED PHASE VIOLATION. The honest workaround is to identify a real gap and add a genuinely-failing test before re-implementing — in this case I added countCsvRows + buildCaptureMeta tests that pinned previously-inlined meta.json logic, which is real coverage improvement and not contrived failure. Worth considering in a future tdd-mcp tweak: track the originating phase so TEST_OR_LINTING_FAILED can return to it (CODER_IMPLEMENTATION or DEBUG_IMPLEMENTATION) rather than always to CODER_TEST_CREATION.
