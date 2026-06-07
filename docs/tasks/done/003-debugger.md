# Task 003: Organizer-roles sync failure shouldn't block player character sync

## Objective
A failure in `syncLarpManagerOrganizers` (or `syncLarpManagerRegistrations`) currently
rejects the entire `checkLarpManagerRegistrationCallable`, so `syncPlayerCharactersForUser`
never runs and every player on the event sees "No character yet" + the "create on
LarpManager" CTA. Decouple the three sync paths so a single failure degrades gracefully
instead of locking every player out of their character.

## Symptom (reproduction)
- Verified live: home screen logs `[firebase_functions/internal] Could not find the
  Organizer role on LarpManager …/crucible/manage/roles/. Response did not include the
  roles table — the service account may lack orga_roles permission or the event slug
  may be wrong.` from `fetchOrganizerEmailsFromLarpManager`.
- Same event, regular player (also holds the Organizer role): registered in LM with a
  character assigned, but RoleKeeper shows "No character yet".
- Pipeline reading: `resolveLarpManagerPlayerAccess` runs
  `Promise.all([syncLarpManagerOrganizers, syncLarpManagerRegistrations])` at
  `functions/src/larpmanager/playerAccess.ts:57-60`. When org sync rejects, the
  promise rejects, the callable wrapper at `functions/src/index.ts:696-700` converts
  it to `HttpsError("internal", …)`, and `syncPlayerCharactersForUser` is never
  invoked. No `/characters/{uuid}` doc is written. Flutter's `watchCharacters()`
  stream stays empty → empty-state body.

## Background: the wider sync pipeline
`resolveLarpManagerPlayerAccess` orchestrates four collaborators:
1. `syncLarpManagerOrganizers` — refreshes `larpManagerOrganizers/*` from LM's
   `/manage/roles/` page.
2. `syncLarpManagerRegistrations` — refreshes `larpManagerRegistrations/*` from
   LM's registration export ZIP.
3. `isEmailLarpManagerOrganizer` + registration doc read — these consult the
   **cached** Firestore collections written by 1 and 2.
4. `syncPlayerCharactersForUser` — only called when `isOrganizer || registered`.

Steps 3 and 4 already work off the Firestore cache, so a failed (1) or (2) doesn't
invalidate previously-good data — they just fail to refresh it. The current code
throws away that resilience by tying every collaborator into one `Promise.all`.

## Requirements

### DEBUG_ANALYSIS phase (no code changes)
- Confirm by reading the two callsites
  (`playerAccess.ts:57-60` and `index.ts:687-700`) that org-sync rejection is the
  only thing preventing `syncPlayerCharactersForUser` from running for the affected
  user.
- Note in the PR description which of {org sync, registration sync, character sync}
  currently has independent failure handling (none) and which gets surfaced to the
  caller as `internal` (all of them, indiscriminately).

### DEBUG_IMPLEMENTATION phase
- Replace `Promise.all` with independent `try/catch` (or `Promise.allSettled`) so
  each of `syncLarpManagerOrganizers` and `syncLarpManagerRegistrations` can fail
  without blocking the other or the downstream character sync.
- Add the same protection around `syncPlayerCharactersForUser`: if it throws, log
  and fall through to a `hasCharacter: false, characterCount: 0` result rather
  than rejecting the callable.
- On any sync failure, fall back to the cached Firestore docs:
  - `isEmailLarpManagerOrganizer` already reads the cache — no change.
  - For `registered`, the existing `regSnap.exists` check already reads the cache
    — no change.
  - For character data, the existing `syncPlayerCharactersForUser` "legacy
    fallback" (registration empty + uid owns a `/characters` doc → `hasCharacter:
    true`) covers cached chars. If org sync failed but the user has cached
    `/characters` docs they own, return `hasCharacter: true`.
- Extend `LarpManagerPlayerAccessResult` with three nullable string fields:
  - `organizerSyncError: string | null`
  - `registrationSyncError: string | null`
  - `characterSyncError: string | null`
  Each is `null` on success, or a short user-safe message on failure (no stack
  trace, no secrets).
- Keep one diagnostic `logger.error` per sync failure with the underlying error
  message, the sync name, and the event base path. **Never** log raw email,
  character names, or service-account credentials.
- The callable wrapper in `index.ts` should no longer throw `internal` for these
  sync failures — they now show up as fields on the returned result. Keep
  `internal` only for genuinely unexpected exceptions (e.g. Firestore unavailable).

## Acceptance Criteria
- [ ] PR description names the root cause in one sentence ("Promise.all rejection in
      resolveLarpManagerPlayerAccess hard-blocks character sync when org-roles fetch
      fails").
- [ ] New test in `playerAccess.test.ts`:
      org sync throws + cached organizer doc exists for user + cached registration
      doc with matching character → `isOrganizer: true`, `hasCharacter: true`,
      `organizerSyncError` is a non-empty string, callable does NOT throw.
- [ ] New test: org sync throws + no cached organizer doc + cached registration
      doc with matching mirror char → `isOrganizer: false`, `registered: true`,
      `hasCharacter: true`, `organizerSyncError` populated.
- [ ] New test: BOTH org sync and registration sync throw + user has a pre-existing
      `/characters` doc they own → `hasCharacter: true` via legacy fallback,
      both `*SyncError` fields populated, callable does NOT throw.
- [ ] New test: BOTH syncs throw + nothing cached for user → `registered: false`,
      `hasCharacter: false`, both `*SyncError` populated, `characterMessage` is
      null (no misleading "create a character" copy when we don't actually know),
      callable does NOT throw.
- [ ] Existing 4 tests in `playerAccess.test.ts` still pass unchanged.
- [ ] `scripts/lint.sh` and `scripts/test.sh` both clean.
- [ ] At least one test asserts a `logger.error` diagnostic was captured naming
      the failed sync step.

## Files Likely Affected
- `functions/src/larpmanager/playerAccess.ts` (fix site)
- `functions/src/larpmanager/playerAccess.test.ts` (new tests)
- `functions/src/index.ts` (callable wrapper may tighten its catch)
- `functions/src/_testing/firestoreStub.ts` (extend stub if needed to throw on
  configured paths — keep additions minimal)

## Context
- The Task 001 regression fix (CSV `Character` vs `Characters` header) is **not**
  the cause here. `syncPlayerCharactersForUser` never runs at all in the failing
  flow; the bug is upstream.
- The cached `larpManagerOrganizers/*` and `larpManagerRegistrations/*` docs
  are intentionally the source of truth for `isEmailLarpManagerOrganizer` and
  the registration lookup — the "sync" functions only refresh them. This design
  already supports degraded operation; we just need to stop propagating sync
  exceptions past the orchestrator.
- Test fixtures should use `makeFirestoreStub` from
  `functions/src/_testing/firestoreStub.ts` and (if needed) a small extension
  that lets the stub throw on a configured collection path so we can simulate a
  failing sync without touching HTTP.

## Out of Scope
- Diagnosing/fixing the underlying `manage/roles/` HTTP failure — covered by
  Task 004.
- Flutter UI surfacing of the new `*SyncError` fields — covered by Task 005.
- Caching policy changes for `larpManagerOrganizers` / `larpManagerRegistrations`
  beyond what already exists.


# 📊 Agent Report

undefined

---
DONE
