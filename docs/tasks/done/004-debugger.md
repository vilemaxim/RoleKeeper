# Task 004: Diagnose and harden organizer-roles HTML fetch

## Objective
Find out why `fetchOrganizerEmailsFromLarpManager` is returning
"Response did not include the roles table" for the live Crucible event on
sovereignscrolls.larpmanager.com, and either parse the new markup, give the
organizer an actionable error, or both. The Task 003 resilience fix prevents
this from locking players out; this task restores organizer-elevation sync.

## Symptom (reproduction)
- Live error from `home screen.lmStatus`:
  "Could not find the Organizer role on LarpManager
  https://sovereignscrolls.larpmanager.com/crucible/manage/roles/.
  Response did not include the roles table — the service account may lack
  orga_roles permission or the event slug may be wrong."
- The detection logic is in `organizers.ts:findOrganizerRoleUuidFromRolesHtml`
  (regex for `<tr id="..."> ... </tr>` inside `<tbody>` + trash-icon exclusion).
- Three possible root causes: (a) service account lacks `orga_roles` permission
  on Crucible's Organizer role, (b) the LM page markup changed and our regex
  no longer matches, (c) wrong event slug being sent to LM.

## Requirements

### DEBUG_ANALYSIS phase (no code changes)
- Read the most recent `firebase functions:log --only checkLarpManagerRegistrationCallable`
  (or whatever the callable is named in `functions/src/index.ts`) and capture the
  `bodySnippet` field emitted by `fetchOrganizerEmailsFromLarpManager`'s error
  branch. State in the PR description which of (a)/(b)/(c) is the actual cause.
- If markup-drift: capture a real (scrubbed) sample of the roles HTML using the
  Task 002 capture script (extend it if it doesn't already pull `/manage/roles/`).
- If service-account perms: state which LM permission(s) need granting and to
  which role.

### DEBUG_IMPLEMENTATION phase
- If markup drift: update `findOrganizerRoleUuidFromRolesHtml` to handle the
  new markup AND keep the old regex as a fallback so both versions of LM work.
  Add a unit test with the captured fixture.
- If perms: improve the error message to name the exact LM permission to grant
  and on which role, and link to the organizer-setup docs section.
- Either way: add a unit test pinned to the captured HTML fixture so future LM
  drift fails CI rather than production.
- If the cause is something else (e.g. session expired silently): pick the
  smallest fix that closes that path.

## Acceptance Criteria
- [ ] PR description names the actual root cause (a/b/c/other) with evidence
      from the captured HTML.
- [ ] If parser fix: new unit test uses a captured roles.html fixture under
      `functions/test/fixtures/` and asserts the Organizer UUID is extracted.
- [ ] If error-message fix: organizer error copy now contains the specific
      LM-side remediation step.
- [ ] `scripts/lint.sh` and `scripts/test.sh` both clean.
- [ ] Manual verification: after deploy, `syncLarpManagerOrganizers` succeeds
      for Crucible (not gated by CI).

## Files Likely Affected
- `functions/src/larpmanager/organizers.ts`
- `functions/src/larpmanager/organizers.test.ts`
- `functions/test/fixtures/crucible-roles/roles.html` (captured + scrubbed)
- Possibly `scripts/capture-lm-fixture.ts` (extend to also capture the roles
  page if not already)

## Context
- Existing organizer-row-detection logic at
  `functions/src/larpmanager/organizers.ts:45-70` already includes a one-row
  fallback. Keep both heuristics. Add new ones — don't replace.
- The `bodySnippet` (first 800 chars) is already logged by the existing
  `logger.error` — that's the analysis input. No new logging needed.
- Multi-tenant note: the affected event is `crucible` on
  `https://sovereignscrolls.larpmanager.com`. Any captured fixture must be
  scrubbed via the Task 002 PII scrubber.

## Out of Scope
- Anything in `playerAccess.ts` — Task 003 owns the resilience fix.
- Auto-retry / backoff on sync failures.
- Replacing HTML scraping with an LM REST API (separate ADR if such an API exists).


# 📊 Agent Report

undefined

---
DONE
