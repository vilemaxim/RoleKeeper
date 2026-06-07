# LarpManager fixtures

This directory holds **anonymized** dumps of real LarpManager event data
(character export JSON + registrations CSV + meta) captured by
[`scripts/capture-lm-fixture.ts`](../../../scripts/capture-lm-fixture.ts).

Each subdirectory contains:

- `character-export.json` — pretty-printed bulk character export.
- `registration.csv` — registrations CSV (possibly with scrubbed emails).
- `meta.json` — `{ baseUrl, eventSlug, capturedAt, characterCount,
  registrationCount, sha256OfExport, scrubbed, seed }`.

## Capturing a new fixture

```bash
npx ts-node scripts/capture-lm-fixture.ts \
  --base-url https://lm.example.com \
  --event-slug my-event-2026-1 \
  --username svc-account --password '***' \
  --out functions/test/fixtures/my-event
```

PII scrub is **on by default**. To capture raw data for one-off local
debugging, pass `--no-scrub` — the script will append `-unscrubbed/` to the
output directory and `.gitignore` excludes
`functions/test/fixtures/*-unscrubbed/` to prevent accidental commits.

## Rules for what may live here

1. **Never commit a `--no-scrub` capture.** If you accidentally stage one,
   `git rm -r --cached` it immediately and rotate any credentials that
   could be reconstructed from the dump.
2. Captures committed here must have `meta.json.scrubbed === true`.
3. Keep fixtures small. Trim down to the rows/characters relevant to the
   bug being reproduced; large dumps make repo clones slow.
4. Reference each fixture from the test that uses it (e.g. via a comment
   pointing to `functions/test/fixtures/<name>/`), so it's clear which
   tests are gated on the fixture.

## Why a directory and not inline test data

Hand-crafted JSON is fine for unit-level branch coverage, but real
LarpManager exports drift in subtle ways (column header drift, name
format drift, locale variants) that are easy to miss in synthetic
fixtures. Captured fixtures let future debugger tasks replay the exact
production payload that triggered a bug — see Task 001 for context.
