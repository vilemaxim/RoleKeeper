# Task 001: Registered LarpManager users don't see their assigned character

## Objective
A user who is registered for an event in LarpManager AND has a character
assigned in LarpManager is being told to "Create a character on LarpManager"
instead of seeing their existing character. Reproduce in a unit test, find
the failing step, fix it, and lock it down with a regression test.

## Symptom (reproduction)
- Test user has an account in LarpManager.
- LarpManager shows the user as registered for the event.
- LarpManager shows a character assigned to that user for the event.
- In RoleKeeper, the same user (same email) sees the "Create a character
  on LarpManager…" prompt on the characters/home screen, instead of
  seeing their character.
- The exact "Create a character on LarpManager…" wording proves
  `registered = true` and `isOrganizer = false` at the time of the
  failure (see `playerAccess.ts:125-129`). The failing step is therefore
  one of:
    - 2: the registration doc's `characterNames` array is empty
         (CSV column not picked up, or LM didn't list characters there).
    - 3: `characterNames` is populated but no name matches the mirror
         export (name format drift between CSV and export).
    - 4: matches happen and writes succeed, but the Flutter reader
         doesn't see them (wrong query / ownerId mismatch).

## Background: the sync pipeline this bug lives in
The chain that produces `hasCharacter: true` for a regular player runs
inside `resolveLarpManagerPlayerAccess`
(`functions/src/larpmanager/playerAccess.ts`):

1. `syncLarpManagerRegistrations` parses the LM registrations CSV and
   writes `games/{i}/events/{e}/larpManagerRegistrations/{sha256(email)}`
   with `{ emailLower, characterNames: string[] }`. The `characterNames`
   column is read from a header literally named `"Characters"`
   (case-insensitive) in `parseRegistrationRowsFromCsv`.
2. `resolveLarpManagerPlayerAccess` looks up that registration doc by
   the caller's email; if it doesn't exist, the user is treated as
   not-registered and `syncPlayerCharactersForUser` is **not** called.
3. If registered, `syncPlayerCharactersForUser`:
   a. Reads `characterNames` from the registration doc.
   b. If empty: returns based on existing `/characters` docs owned by uid.
   c. Otherwise loads the event-wide mirror at `larpManagerMirrorChars/*`
      (or fetches the LM export if mirror is empty) and matches by
      lowercased name via `resolveCharactersByNames`.
   d. For each match, writes the LM character UUID as the doc id into
      `games/{i}/events/{e}/characters/{uuid}` with
      `ownerId: uid, shortId, larpManagerUuid, isArchived: false`,
      and a lookup doc at `characterShortIdLookup/{shortId}`.
4. Flutter screens read `/characters` where `ownerId == uid` and
   `isArchived == false`.

Any of steps 1–4 can produce the observed symptom. DEBUG_ANALYSIS must
identify **which** before the fix is written. The symptom narrows the
search to steps 2, 3, or 4 (see Symptom above).

## Requirements

### DEBUG_ANALYSIS phase (no code changes)
- **Email-identity check first.** Confirm the email on the test user's
  Firebase Auth identity (visible at `users/{uid}` and via
  `auth.token.email`) matches the email on their LarpManager
  registration row (case-insensitively). Note the outcome in the PR
  description. Hash both with `registrationDocIdForEmail` and confirm
  the doc the server looks up actually exists.
- Inspect the affected user's
  `larpManagerRegistrations/{sha256(email)}` doc and confirm
  `characterNames` is non-empty. If empty, the bug is in step 2 (CSV
  parse or LM not populating the column). If non-empty, inspect
  `larpManagerMirrorChars/*` and check whether
  `resolveCharactersByNames(mirror, registration.characterNames)`
  returns anything — that's step 3. If it does, look at `characters`
  where `ownerId == uid` for the actual written docs — that's step 4.
- Acceptable evidence sources: existing `firebase functions:log` output
  for `checkLarpManagerPlayerAccessCallable` /
  `runLarpManagerSyncCallable` on the affected game; reading the live
  Firestore docs at the four paths above; or running the chain locally
  with a captured registrations.csv + character export JSON pasted into
  the test.
- Write down the failing step and the root cause in the PR description.

### DEBUG_IMPLEMENTATION phase
- Add a **failing** unit test in
  `functions/src/larpmanager/playerCharacters.test.ts` (or
  `playerAccess.test.ts` if the cause is upstream of
  `syncPlayerCharactersForUser`) that reproduces the bug using a
  synthetic fixture mirroring the test user's real state. Test must
  use the existing pure-unit pattern (no Firestore emulator). Stub
  Firestore via a minimal in-memory object that implements just
  `db.doc`, `db.collection`, `db.batch` — keep local to the test file
  unless it grows beyond ~50 lines, in which case extract to
  `functions/src/_testing/firestoreStub.ts`.
- Fix the root cause. Fix scope is limited to whichever file in
  `functions/src/larpmanager/` contains the failing step.
- Add a second test for each adjacent failure mode that COULD cause
  the same symptom but didn't this time — so we don't ship a fix that
  re-introduces a sibling bug. Specifically cover:
  - Registration doc missing → result is `hasCharacter: false`,
    `characterMessage` is the "complete registration" copy (NOT the
    "create character" copy).
  - Registration doc present, `characterNames` empty, no existing
    `/characters` doc for uid → `hasCharacter: false`,
    `characterMessage` is the "create character" copy.
  - Registration doc present, `characterNames` has one entry, mirror
    has a matching entry by case-insensitive name → writes one
    `/characters/{uuid}` doc with the required fields and returns
    `hasCharacter: true, characterCount: 1`.
  - Registration doc present, `characterNames` has one entry, mirror
    has NO matching name → `hasCharacter: false`, `characterMessage`
    is the "create character" copy.
- Replace `firebase-functions/logger` `.info/.warn/.error` with spies
  that capture calls into an array, following the exact pattern in
  `functions/src/larpmanager/client.test.ts` (the `withMockedFetch`
  helper does this for fetch + logger; reuse or factor out).
- At least one test must assert that when the no-match branch is taken,
  a diagnostic log line is emitted that names the failing step (e.g.
  `logger.info("syncPlayerCharactersForUser: 0/N names matched mirror
  export for uid=…")`). If no such log line exists in the current
  implementation, **add one** as part of the fix — this is the
  "read the logs in prod" answer for future occurrences. Keep log
  messages PII-free (no raw email or character name in the message;
  uid is fine).

## Acceptance Criteria
- [ ] PR description names the failing pipeline step (1, 2, 3, or 4)
      and its root cause in one sentence.
- [ ] PR description states whether the test user's RoleKeeper auth
      email matches their LarpManager registration email.
- [ ] A test in `functions/src/larpmanager/` reproduces the exact bug
      (would have failed before the fix, passes after).
- [ ] Tests for all four scenarios listed above exist and pass.
- [ ] At least one test asserts on a captured diagnostic log line
      emitted by the production code path.
- [ ] No new test depends on the Firestore emulator or any network call.
- [ ] All existing `node --test` and `flutter test` suites still pass.
- [ ] `scripts/lint.sh` and `scripts/test.sh` both clean.
- [ ] Production logs (`firebase functions:log --only
      checkLarpManagerPlayerAccessCallable`) emitted after the fix
      include a diagnostic line that would have pinpointed this bug
      class in <5 seconds of log reading. (Manual verification by the
      human after deploy, not gated by CI.)

## Files Likely Affected
- `functions/src/larpmanager/playerCharacters.ts` (likely fix site)
- `functions/src/larpmanager/playerCharacters.test.ts` (new tests)
- `functions/src/larpmanager/playerAccess.ts` (possible fix site if the
  bug is the call-site condition `if (isOrganizer || registered)`)
- `functions/src/larpmanager/playerAccess.test.ts` (possible new file)
- `functions/src/larpmanager/registrations.ts` (possible fix site if
  the CSV column header isn't matched in the test user's event)
- `functions/src/_testing/firestoreStub.ts` (new, only if extracted)

## Context
- Existing test pattern reference:
  `functions/src/larpmanager/client.test.ts` shows how to mock
  `globalThis.fetch` and silence/spy `firebase-functions` logger inside
  a test. Follow the same scaffolding for any test that touches LM HTTP
  code or emits logs.
- `resolveCharactersByNames` and `shortIdForLmCharacter` already have
  pure tests in `playerCharacters.test.ts`. New tests should call the
  exported `syncPlayerCharactersForUser` end-to-end with a stubbed `db`.
- Multi-tenant note: every Firestore path used in the test must include
  the `games/{instanceId}/events/{eventSlug}/` base — built via
  `gameEventBase(tenant)`. Do NOT hard-code paths in tests; use the
  helper so a future tenant-path refactor only breaks the helper.
- Logging in fix code should use `firebase-functions/logger` (the
  existing tests stub it). Do not use `console.log`.

## Out of Scope
- Wiring up the Firestore emulator into `scripts/test.sh` (separate ADR
  required if we decide to).
- Adding a fixture-capture developer script (covered by Task 002).
- Flutter-side rendering changes in `characters_screen.dart` or
  `home_screen.dart` — only touch Flutter if DEBUG_ANALYSIS proves the
  Functions side is correct and the bug is in the reader.
- Refactoring `syncPlayerCharactersForUser` for clarity — keep the diff
  minimal.


# 📊 Agent Report

undefined

---
DONE
