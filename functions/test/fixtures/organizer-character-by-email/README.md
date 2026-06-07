# Task 006 fixture — organizer character by email

Hand-crafted (not from a real LarpManager capture) regression fixture for
Task 006: an organizer's own LarpManager character not surfacing in the
RoleKeeper Characters screen.

## What it reproduces (Hypothesis A)

- `character-export.json` has 3 characters. Two belong to players (in
  registrations.csv); the third (`Cassandra Quartermaster`, uuid
  `uuid-cassandra`) is owned by the organizer service email
  `organizer-svc@example.test`.
- `registration.csv` contains the two players but **deliberately omits the
  organizer** — this is the exact production shape that broke
  `syncPlayerCharactersForUser`: the organizer has `regExists: false` and
  `characterNames: []`, so the registration-name join can't see their
  character.

## What the fix does

`functions/src/larpmanager/playerCharacters.ts`
(`findCharactersByEmailInExportMap` + organizer fallback path in
`syncPlayerCharactersForUser`) walks every string field of every character
in the bulk mirror and resolves the organizer's character via an exact
lower-cased email match. The fallback only triggers when the caller is an
organizer.

## Why scrubbed: true

This fixture was never sourced from a real LarpManager event, so there is
no PII to scrub. `meta.json.scrubbed: true` is set to satisfy the fixtures
README convention ("Captures committed here must have
`meta.json.scrubbed === true`") and to make it explicit that these strings
are placeholders, not real player data.
