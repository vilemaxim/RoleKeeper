# Task 005: Surface "LM sync degraded" banner on CharactersScreen

## Objective
After Task 003, `checkLarpManagerRegistrationCallable` can return
`organizerSyncError`, `registrationSyncError`, or `characterSyncError` strings
alongside a useful result. Show these on `CharactersScreen` as a non-blocking
warning banner so users know their data may be stale even when characters do
render, instead of silently falling back to the empty-state copy.

## Requirements
- Extend the Dart model that backs the registration-callable response
  (`lib/services/larp_manager_registration_service.dart` and any
  `LarpManagerRegistrationCheckResult` model) to carry the three new
  nullable strings from Task 003.
- On `CharactersScreen`:
  - When the callable returns ANY non-null `*SyncError`, render a Material
    banner (`MaterialBanner` or a `Card` with `errorContainer` color) above
    the character list / empty-state body that names which sync degraded and
    suggests the next step.
  - When `hasCharacter: true` but a sync errored, the banner is the ONLY
    error surfaced — do NOT show the existing red `_syncError` text, since
    the data is fine.
  - When `hasCharacter: false` AND a sync errored, prefer the banner over the
    generic "Create a character on LarpManager…" copy, so users aren't told
    to create something they may already have.
  - Banner has a "Retry sync" button that calls
    `_refreshCharacterStatus(forceRefresh: true)`.
- Copy:
  - Organizer error: "Couldn't refresh organizer permissions from LarpManager.
    Your character data is current; ask your event organizer to check LM
    Integration."
  - Registration error: "Couldn't refresh event registrations from LarpManager.
    If your character is missing, retry or contact your organizer."
  - Character error: "Couldn't sync characters from LarpManager. Showing
    last-known data."
- Use `reportAppError` (see `.cursor/rules/error-handling.mdc`) for any
  exception path; the new banner pulls from the *server-returned strings*,
  not from a thrown exception.

## Acceptance Criteria
- [ ] Widget test: callable returns `hasCharacter: true` + non-null
      `organizerSyncError` → list of characters renders AND banner with
      organizer copy is visible AND no red `_syncError` text.
- [ ] Widget test: callable returns `hasCharacter: false` + non-null
      `organizerSyncError` + cached `_characterMessage` null →
      banner is visible AND the generic "Create a character" body is NOT
      shown.
- [ ] Widget test: all three `*SyncError` fields null → no banner, existing
      behavior unchanged.
- [ ] Tap "Retry sync" triggers `verifyRegistrationForCurrentGame(forceRefresh: true)`.
- [ ] `flutter analyze` clean; `flutter test` passes.

## Files Likely Affected
- `lib/services/larp_manager_registration_service.dart` (extend model)
- `lib/screens/characters_screen.dart` (banner widget + state plumbing)
- `test/screens/characters_screen_test.dart` (new or extended)

## Context
- The existing `_syncError` UI path catches `FirebaseFunctionsException` —
  keep that as the fallback for unexpected errors. The new banner is driven
  by the new `*SyncError` fields on the *successful* callable response.
- Banner color: use `Theme.of(context).colorScheme.errorContainer` /
  `onErrorContainer` (matches existing Material 3 usage in the app).
- Depends on Task 003 — don't start until 003 is merged, since the result
  fields don't exist yet.

## Out of Scope
- Backend changes (Task 003 owns the new fields).
- Diagnosing why the LM sync is failing (Task 004 owns that).
- Restyling the existing empty-state body.


# 📊 Agent Report

Refactor pass: no code changes required. The implementation was already in a clean state — CharactersScreen vs CharactersScreenBody split has a clear single responsibility (gating vs. content), _LmSyncDegradedBanner is appropriately scoped as a private widget local to the screen (no other caller in this PR), the model change is a minimal additive extension, and the comments that exist explain intent (why the empty-state body is suppressed, why error copies are joined with a blank-line separator) rather than restating the code. Lint and tests already verified clean during implementation phase.

---
DONE
