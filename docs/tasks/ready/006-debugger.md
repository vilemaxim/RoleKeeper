# Task 006: Organizer's own LarpManager character not surfacing in Characters screen

## Objective
Find out why an organizer's existing LarpManager character is not associated to
their RoleKeeper account when they open the Characters screen, and fix it so
that an organizer (and any other affected user category) reliably sees their
own LM character listed. This is currently broken end-to-end on first use of
the live event.

## Symptom (reproduction)
- Sign in to RoleKeeper with the same email used for an existing LarpManager
  account that owns a character on the linked event (e.g. Crucible).
- Make this user an organizer on RoleKeeper for that LARP.
- Open the Characters screen.
- Expected: the LM character appears in the list.
- Actual: empty state ("No character yet" + organizer-flavored body copy from
  `lib/screens/characters_screen.dart:489-502`).

## Evidence captured before this task was queued

`firebase functions:log --only checkLarpManagerRegistrationCallable` (run
2026-06-06, latest entries 2026-06-01) showed:

```
status: 200, hasRolesTable: false, finalUrl: .../crucible/manage/roles/
bodySnippet: <!DOCTYPE HTML> ... <title> Access denied - Sovereign Scrolls
</title> ...
checkLarpManagerRegistrationCallable failed Error: ... Response did not
include the roles table — the service account may lack orga_roles
permission or the event slug may be wrong.
```

Two facts follow from this log:

1. **The deployed code is pre-Task-004.** The hedged error message above
   ("may lack orga_roles permission OR the event slug may be wrong") and the
   throw bubbling all the way up to the callable indicate the deployed
   functions package predates the Task-004 access-denied detector
   (`organizers.ts:87-109` `looksLikeLarpManagerAccessDeniedPage`) and the
   Task-003 `Promise.allSettled` resilience in `playerAccess.ts:86`. Latest
   `main` must be deployed before any further analysis.
2. **The LM service account genuinely lacks the `orga_roles` permission on
   the Crucible Organizer role.** The 200-with-Access-Denied-body pattern is
   diagnostic; it isn't markup drift, slug error, or session expiry. This
   must be granted on the LarpManager side (operator action) before the
   character flow can complete end-to-end.

## Operator preconditions before DEBUG_ANALYSIS

These are not Worker actions — they are human operator actions and must be
done first. The DEBUG_ANALYSIS phase begins **after** both are confirmed:

1. Deploy the current `main` to Firebase Functions (CI on merge, or manual
   `firebase deploy --only functions`). Confirm the deployed Functions
   image contains `looksLikeLarpManagerAccessDeniedPage` (e.g. by triggering
   the callable and checking the new log line
   `fetchOrganizerEmailsFromLarpManager: LM access-denied page returned`).
2. On LarpManager (`https://sovereignscrolls.larpmanager.com/crucible/manage/roles/`),
   grant the service-account user **`orga_roles`**, **`orga_registrations`**,
   and **`orga_characters`** permissions on the Organizer role. Without
   these, the underlying scrapes will keep failing on different pages with
   the same Access Denied response.

## Hypotheses (ranked by likelihood)

A. **Organizers aren't in the registrations CSV.** `syncPlayerCharactersForUser`
   (`functions/src/larpmanager/playerCharacters.ts:129-164`) keys *every* user's
   character lookup off `larpManagerRegistrations/{sha256(email)}.characterNames`.
   Organizers in LarpManager are typically not "registered" as players on the
   event they organize, so `regSnap.exists` is `false`, `characterNames` is `[]`,
   and the function returns early without ever writing a character doc under
   the organizer's `ownerId`. The Characters screen then queries Firestore
   directly (`lib/services/characters_repository.dart:39-48`) and gets nothing.
   Compounded by the fact that `resolveLarpManagerPlayerAccess` reports
   `hasCharacter = isOrganizer || charSync.hasCharacter`
   (`functions/src/larpmanager/playerAccess.ts:250`), so the server claims
   success, suppressing the diagnostic `characterMessage`.

B. **Bulk character mirror is empty.** Nobody has run
   `runLarpManagerSyncCallable` for this event yet, so
   `games/.../larpManagerMirrorChars` is empty and even if the user had a
   `characterNames` row, no name would match. `mirrorSize: 0` in the
   `syncPlayerCharactersForUser: resolved` log.

C. **Email mismatch.** Firebase Auth email differs from LM registration email
   (e.g. case, plus-aliasing, alternate address). `regExists: false`,
   `namesCount: 0` — same outward symptom as A but caused by the wrong email.

D. **Name mismatch in `resolveCharactersByNames`** (only relevant if A/B/C are
   ruled out). `namesCount > 0` but `matchedCount: 0`. Strict trimmed
   case-insensitive equality misses things like trailing punctuation,
   accented characters normalized differently, or a "Lyra" vs
   "Lyra Stormcrest" full-name discrepancy.

## Requirements

### DEBUG_ANALYSIS phase (no code changes)

0. Verify the operator preconditions above are done. If
   `firebase functions:log` still shows the pre-Task-004 hedged error
   message, or shows `LM access-denied page returned`, STOP and report
   back — the problem is operator-side, not code-side, and this task's
   implementation phase will not help.

1. With preconditions met, reproduce the failure against the deployed
   project for the affected user. Capture the latest entries from:
   ```
   firebase functions:log --only checkLarpManagerRegistrationCallable
   firebase functions:log --only runLarpManagerSyncCallable
   ```
   Specifically extract these structured fields from `playerCharacters.ts`:
   `regExists`, `namesCount`, `mirrorSize`, `matchedCount`, `existingChars`.
   Also capture any `organizerSyncError` / `registrationSyncError` /
   `characterSyncError` strings on the callable response.

2. Inspect Firestore for the affected event (`games/{instanceId}/events/{slug}/`):
   - Does `larpManagerMirrorMeta/summary` exist? `characterCount`?
   - Does `larpManagerRegistrationsMeta/summary` exist? `registrationCount`?
   - Does `larpManagerRegistrations/{sha256(emailLower)}` exist for the
     affected user's email? If yes, what's in `characterNames`?
   - Does `larpManagerMirrorChars` contain the user's character (search by
     name)? Capture one sample mirror doc (scrubbed) — specifically
     whether `export.player_email` (or any other email-bearing field) exists.

3. State which hypothesis (A/B/C/D/other) is the actual root cause, with
   evidence from the captured logs + Firestore data, in the PR description.

### DEBUG_IMPLEMENTATION phase

Apply the fix that matches the confirmed root cause. **All branches must add
a regression test pinned to a captured fixture so this doesn't silently
break again.**

- **If A (organizer-not-in-registrations):** Extend `syncPlayerCharactersForUser`
  with an organizer fallback path. When `regSnap` doesn't exist OR
  `characterNames` is empty AND the caller is an organizer, look the user up
  against the bulk character mirror by email instead — using whichever
  email-bearing field LM puts on each character (`export.player_email`,
  `export.player`, `export.user_email`, etc.; the analysis phase identifies
  the actual key). If found, write the same character doc structure. If not
  found, set a new `characterMessage` like
  *"Your LarpManager email doesn't match a character on this event. Confirm
  the email on your LM character matches your RoleKeeper login email."*
  Also fix the misleading `hasCharacter = isOrganizer || charSync.hasCharacter`
  short-circuit in `playerAccess.ts:250` so an organizer who actually has no
  character isn't told they do.

- **If B (mirror empty):** When `mirrorSize === 0` in
  `syncPlayerCharactersForUser`, surface a specific
  `characterSyncError = "LarpManager bulk sync hasn't run yet — run LM sync
  on the home screen."`, AND make the empty-state CTA on the organizer
  branch a one-tap "Run LarpManager sync now" that invokes
  `runLarpManagerSyncCallable`.

- **If C (email mismatch):** Improve `characterMessage` to name the exact
  email the server checked (obfuscated, e.g. `j***@example.com`) so the
  user can spot the mismatch. Add an organizer-only diagnostic in the empty
  state listing the emails the LM registrations CSV does contain
  (count + sample, scrubbed) so they can fix LM-side.

- **If D (name mismatch):** Harden `resolveCharactersByNames` —
  trim, lowercase, normalize unicode (`String.prototype.normalize("NFKC")`),
  collapse internal whitespace, strip wrapping quotes/punctuation. Add a
  fallback that matches a registration name as a prefix of a mirror name
  (so "Lyra" matches "Lyra Stormcrest") **only when the prefix match is
  unique** — multiple matches must NOT auto-pick. Add a unit-test fixture
  pair (registrations row + mirror chars) under
  `functions/test/fixtures/character-name-match/`.

## Acceptance Criteria
- [ ] PR description names the actual root cause (A/B/C/D/other) with
      evidence from the captured logs and (scrubbed) Firestore data.
- [ ] After the fix is deployed, the affected organizer (and any test player
      provisioned the same way) sees their LM character on the Characters
      screen on first sync — no manual re-sync needed.
- [ ] A new unit test pinned to a captured fixture under
      `functions/test/fixtures/` reproduces the original failure when run
      against the *pre-fix* code path (or a clearly named variant), so a
      future regression of this exact bug fails CI.
- [ ] `hasCharacter` in `LarpManagerPlayerAccessResult` no longer reports
      `true` for an organizer who actually has zero character docs. Update
      `functions/src/larpmanager/playerAccess.test.ts` to cover this.
- [ ] `scripts/lint.sh` and `scripts/test.sh` both clean.
- [ ] No new prod logging contains raw email addresses or character names
      (existing PII-free convention from `playerCharacters.ts:127-128`).

## Files Likely Affected
- `functions/src/larpmanager/playerCharacters.ts`
- `functions/src/larpmanager/playerCharacters.test.ts`
- `functions/src/larpmanager/playerAccess.ts`
- `functions/src/larpmanager/playerAccess.test.ts`
- `functions/test/fixtures/character-name-match/` (new, branch D) OR
  `functions/test/fixtures/organizer-character-by-email/` (new, branch A)
- Possibly `lib/screens/characters_screen.dart` (only if branch B or C
  changes the empty-state UX)
- Possibly `functions/src/larpmanager/types.ts` (if branch A surfaces a
  typed `player_email` field on `LarpManagerCharacterExport`)

## Context
- The three syncs that must all line up: bulk export →
  `larpManagerMirrorChars`; registrations CSV → `larpManagerRegistrations`;
  joiner (`syncPlayerCharactersForUser`) → `characters` keyed by `ownerId`.
- The Flutter Characters screen reads `characters` directly via
  `CharactersRepository.watchCharacters()`
  (`lib/services/characters_repository.dart:39-48`). The callable response's
  `hasCharacter` is **not** the source of truth for the list — it only
  controls the `characterMessage` empty-state copy.
- Existing structured logs in `functions/src/larpmanager/playerCharacters.ts`
  (`regExists`, `namesCount`, `mirrorSize`, `matchedCount`) are sufficient to
  pinpoint root cause; analysis should not require any new logging.
- LarpManager character export currently typed as
  `LarpManagerCharacterExport { number?, name?, uuid?, teaser?, [key]: unknown }`
  (`functions/src/larpmanager/types.ts:20-26`) — branch A may need to extend
  this with a typed `player_email` once analysis confirms the field name.
- Multi-tenant: any new code paths must scope by `gameEventBase(tenant)` and
  must never let one LARP's data influence another's character associations.
- Related: Tasks 001/004 (done) addressed the "Characters" header drift and
  organizer-roles HTML scrape. This task extends the same defensive posture
  to the player-character join.

## Out of Scope
- Replacing HTML/CSV scraping with an LM REST API (separate ADR if/when
  available).
- Auto-retry / backoff on sync failures.
- Changes to the per-character details fetch (`fetchDetails` path in
  `sync.ts`) — a stale or absent `inventory` / `abilities` doesn't affect
  the join.
- Allowing players to manually "claim" a LM character via shortId entry —
  that's a separate UX feature, not a bug fix.
