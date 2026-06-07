# Task 002: Capture LarpManager fixtures for regression tests

## Objective
Provide a developer script that, given LarpManager credentials and an
event slug, dumps the character export JSON and the registrations CSV
into `functions/test/fixtures/` so future bugs in the sync pipeline can
be reproduced from real (anonymized) payloads instead of hand-crafted
JSON.

## Requirements
- New script at `scripts/capture-lm-fixture.ts` runnable via
  `npx ts-node scripts/capture-lm-fixture.ts` (or
  `node --loader ts-node/esm`, follow whatever the existing
  `scripts/` entries use).
- Inputs via CLI args or env vars (document in `--help`):
  `--base-url`, `--event-slug`, `--username`, `--password`
  (or `--session-id`), optional `--out functions/test/fixtures/<name>`.
- Reuses `establishLarpManagerSession`, `fetchCharacterExportJson`, and
  `fetchRegistrationsExportZip` / `extractRegistrationCsvFromZip` from
  `functions/src/larpmanager/` — do NOT re-implement HTTP.
- Output files in the chosen directory:
  - `character-export.json` (pretty-printed)
  - `registration.csv` (raw)
  - `meta.json` with `{ baseUrl, eventSlug, capturedAt, characterCount,
    registrationCount, sha256OfExport }`
- **PII scrub mode** (default ON; flag `--no-scrub` to disable):
  - Replace every email in `registration.csv` with
    `user{N}@example.test` (stable per email within one capture).
  - Replace every value in the character export JSON's `name`,
    `teaser`, and any string field whose key matches
    `/email|player|user|real_name/i` with a placeholder of the same
    length, BUT keep `uuid` and `number` untouched so name-resolution
    tests are still meaningful.
  - `meta.json` records `scrubbed: true|false` and the seed used.
- `functions/test/fixtures/` is added to git with a `.gitkeep` and a
  short `README.md` explaining the directory's purpose and that
  unscrubbed dumps must NEVER be committed.
- Script refuses to overwrite an existing fixture directory without
  `--force`.

## Acceptance Criteria
- [ ] Script runs end-to-end against a live LarpManager event with
      valid creds (manual verification by the human, not CI).
- [ ] Output directory contains the three files described above.
- [ ] Default run produces scrubbed output; `meta.json.scrubbed` is
      `true`; no original emails or personal names appear anywhere in
      the output files.
- [ ] `--no-scrub` produces unscrubbed output and `meta.json.scrubbed`
      is `false`.
- [ ] Unit tests for the pure scrub helpers (email replacement, JSON
      field redaction) in `scripts/capture-lm-fixture.test.ts` —
      these run in CI; the HTTP-touching parts do not.
- [ ] `scripts/lint.sh` and `scripts/test.sh` both clean.
- [ ] `functions/test/fixtures/.gitkeep` and `README.md` exist.
- [ ] `.gitignore` excludes `functions/test/fixtures/*-unscrubbed/`
      pattern so accidental unscrubbed dumps don't get committed.

## Files Likely Affected
- `scripts/capture-lm-fixture.ts` (new)
- `scripts/capture-lm-fixture.test.ts` (new — scrub helpers only)
- `functions/test/fixtures/.gitkeep` (new)
- `functions/test/fixtures/README.md` (new)
- `.gitignore` (one line)

## Context
- The HTTP helpers in `functions/src/larpmanager/client.ts` are written
  to be callable from outside the Functions runtime — they take a
  `LarpManagerSyncConfig` and return parsed data. Reusing them avoids
  a second HTTP implementation drifting from prod behavior.
- `parseRegistrationRowsFromCsv` and the CSV format are documented in
  `functions/src/larpmanager/registrations.ts`. The capture step
  should NOT parse — store the raw CSV so future tests can exercise
  the parser too.
- Tenant scope: a capture is per `(baseUrl, eventSlug)`. The script
  does not need a `gameId` — it's pulling from LM directly, not from
  Firestore.

## Out of Scope
- Loading the captured fixtures into running tests (those will be
  added incrementally by future debugger tasks as bugs arise — Task 001
  uses synthetic fixtures, not these).
- A UI for triggering captures from the app.
- Automating captures in CI.
- Wiring up the Firestore emulator (separate ADR if/when we want it).


# 📊 Agent Report

Capture LarpManager fixtures for regression tests (Task 002). New developer tool scripts/capture-lm-fixture.ts (+ pure-helper test file capture-lm-fixture.test.ts with 24 tests) dumps a LarpManager event's character export JSON + registrations CSV into functions/test/fixtures/<name>/ for future debugger tasks. Pure helpers (scrubEmailsInCsv, scrubCharacterExportJson, countCsvRows, buildCaptureMeta) run in CI with zero network access; the live HTTP path is lazy-loaded from functions/lib/larpmanager/* so production code is reused, not re-implemented. PII scrub is default-ON: emails become user{N}@example.test (stable per email within one capture), and JSON name/teaser/* sensitive keys are replaced with same-length deterministic placeholders — uuid and number are preserved so name-resolution tests still resolve. --no-scrub auto-appends '-unscrubbed' to the output dir and .gitignore excludes functions/test/fixtures/*-unscrubbed/ so raw dumps cannot be committed by accident. Script refuses to overwrite a non-empty directory without --force. functions/test/fixtures/{.gitkeep,README.md} added. Also fixed an infrastructure bug in scripts/test.sh: the MCP host runs node 18 which does NOT understand glob patterns in `node --test`, so test discovery now resolves globs in bash via `shopt -s globstar nullglob` and passes the file list explicitly — 80 tests now run end-to-end (56 functions + 24 scripts).

---
DONE
