# ADR 0001: Remove the `fetchDetails` toggle from LarpManager sync

**Status:** Accepted, 2026-06-13.

## Context
The LarpManager integration originally carried a `fetchDetails: boolean`
flag that gated per-character `/character/{uuid}/inventory/` and
`/character/{uuid}/abilities/` HTTP calls in `runLarpManagerSync`. The
default was `false` (lightweight mode) so events that only needed
character names could sync cheaply. The toggle lived behind the
integration screen's "Advanced" expander, labeled "Fetch inventory &
abilities JSON," and defaulted OFF.

Task 009 (the LM character-sheet HTML scrape that surfaces Status,
Race, Cultivation, Hit Points/Essence, Affinities, Iron DR, etc.)
hooked an additional per-character fetch onto the same flag with the
intent of keeping the "lightweight vs heavyweight" mode coherent.

In practice this turned the flag into a silent partial-sync trap.
Organizers who saved the integration with default settings — even
after Tasks 009/010 shipped — got teaser-only sync with no log line,
no `lastError`, no UI indication that the user-visible stats block
(the entire payoff of Tasks 008/009/010) was being skipped. The trap
surfaced in production: the very first organizer to test the shipped
batch saw cleaned teasers but no stats and asked "why didn't the data
sync?" — the answer being "you needed to flip a hidden toggle whose
label doesn't mention the feature you're missing."

## Decision
Remove `fetchDetails` entirely. `runLarpManagerSync` always fetches
`inventory`, `abilities`, and `sheet` for any character with a uuid.
There is one sync mode: full.

## Consequences
- **Cost:** ~3 per-character HTTP calls per sync where there were 0
  before for default-config events. For Crucible-size events (~100
  characters) that's ~300 requests per sync. The serial per-character
  loop preserves LM's implicit rate-limit posture.
- **Simplicity:** one mode, no trap. Removes one config flag, one UI
  toggle, the corresponding model field, and the gating logic from
  the sync function.
- **Scheduled sync:** still opt-in per
  `larpManagerSyncSettings/config.scheduledSyncEnabled` (default
  false). Operators worried about LM bandwidth keep scheduled OFF and
  rely on manual sync, which is the existing posture.
- **Backwards compat:** existing `larpManagerIntegration/config` docs
  with `fetchDetails: bool` are tolerated; the field is ignored on
  read and not written on next save. Existing
  `larpManagerMirrorMeta/summary` docs may still have the field; same
  tolerance — next sync writes the new shape with no `fetchDetails`
  key.

## Alternatives Considered
- **Keep flag, rename to "Fetch full character data (inventory +
  abilities + stats)."** Preserves the bandwidth knob but doesn't
  help operators who already saved with the default and now silently
  get partial data forever.
- **Manual sync always full, scheduled sync respects flag.**
  Split-mode complexity for marginal gain; the scheduled-sync gate is
  already controlled by `scheduledSyncEnabled` for the same purpose.
- **Default the flag ON for new integrations.** Does nothing for
  existing trapped configs and still leaves the silent trap for
  anyone who deliberately turns it off.

Removing the flag entirely was chosen for simplicity and to close the
trap permanently. The bandwidth knob is preserved at a coarser
granularity (scheduled sync on/off).

## Related Tasks
- Task 008 — LM character-sheet HTML parser.
- Task 009 — Wire scrape into sync, gated by `fetchDetails` (the
  hooking step that turned the flag into a trap).
- Task 010 — UI rendering of the scraped sheet.
- Task 011 — Strip HTML from displayed teaser.
- Task 012 — This ADR's implementation.
- Task 013 — Per-character self-sync (independent follow-up,
  triggered by the same partial-sync investigation).
