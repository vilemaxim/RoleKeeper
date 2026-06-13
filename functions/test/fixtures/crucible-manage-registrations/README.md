# crucible-manage-registrations fixture

Pinned shape of LarpManager's `/{slug}/manage/registrations/` HTML page —
the structure that Task 006 ultimately resolves the organizer → character
join against (see `functions/src/larpmanager/charactersByEmail.ts`).

All identifiers, names, and emails in `manage-registrations.html` are
**synthetic**. The shape — `<tr id="…">`, `<a class="post_popup_member"
pop="…">`, `<td class="email">…</td>`, `<a href="…/manage/characters/…/edit/">`
— mirrors a live capture taken on 2026-06-07 from
`sovereignscrolls.larpmanager.com/crucible/manage/registrations/`, but no
real PII appears in this file.

## Why this fixture exists

Task 006's first attempt (`organizer-character-by-email/`) assumed the bulk
`/export/char/` JSON would carry a `player_email` field that LM does not
actually expose for the affected event. The captured production data
showed three character rows where the only player-identifying fields are
`owner` (a free-text display name) and `owner_uuid` (an opaque 12-char LM
UuidMixin id) — neither matchable from a RoleKeeper email.

The `/manage/registrations/` HTML page is the canonical join table on
LarpManager's side: each `<tr>` carries an exact `(email, lm_user_uuid,
character_uuid…)` tuple regardless of whether the registration appears in
the CSV export (organizers, in particular, are present here but absent
from the CSV).

## Coverage rows

| Row | Scenario |
| --- | --- |
| `r0000001` | Player with one character assignment — the normal case |
| `r0000002` | Organizer / staff with no character assigned yet (empty character `<td>`) — must not error |
| `r0000003` | Player with two characters in one `<td>` — defensive multi-character coverage |
| `r0000004` | Row with a `<td class="email">` but missing `pop=…` user uuid — must be skipped, not crash |
| `r0000005` | Row missing the email td entirely — must be skipped |

The parser test (`charactersByEmail.test.ts`) reads this file and asserts
the exact output shape so future LM markup drift fails CI loudly.
