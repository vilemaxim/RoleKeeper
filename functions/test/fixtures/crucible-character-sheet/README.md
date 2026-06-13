# crucible-character-sheet fixture

Pinned shape of LarpManager's `/{slug}/character/{uuid}/` HTML page —
the per-character sheet that RoleKeeper scrapes (via Task 009's sync
wiring) to surface the rich gameplay stats LM renders server-side but
never exposes through `/export/char/` or the `abilities`/`inventory`
JSON endpoints (HP/Essence, Total/Effective affinities, Iron DR, Race,
Cultivation Tier, etc.).

The HTML in `character-sheet-oxe9sb0w02ig.html` was captured from
`https://sovereignscrolls.larpmanager.com/crucible/character/oxe9sb0w02ig/`
and then scrubbed via `scrubCharacterSheetHtml` (see
`scripts/capture-lm-fixture.ts`) with seed
`task-008-crucible-character-sheet`. All emails, LM user uuids
(`pop="…"`, `owner_uuid="…"`, `/public/<uuid>/` URLs), and human
display names are synthetic placeholders. The character uuid
`oxe9sb0w02ig` is preserved intact — needed for the stable fixture
filename and for the parser tests that pin the `/character/<uuid>/`
URL shape.

## Why this fixture exists

Task 008's parser (`functions/src/larpmanager/characterSheet.ts`) reads
`<b>Label:</b>Value` rows out of LM's character-sheet HTML so Task 010
can render Player / Status / Race / Cultivation Tier / Hit
Points/Essence / Total + Effective affinities / Iron DR in the Flutter
character detail screen.

Synthesising the fixture by hand would not match the real LM template
and the parser would silently fail in production. A scrubbed real
capture is the only way to keep the parser pinned to the actual
server-rendered markup.

## Coverage rows

The single committed sheet (`character-sheet-oxe9sb0w02ig.html`) is
the Heldrek character used elsewhere in the Task 007/008 test suite,
chosen to keep end-to-end testing coherent. The pinned parser test
(`functions/src/larpmanager/characterSheet.test.ts`,
"committed Heldrek fixture — exact ordered sections[]") asserts the
exact 23-row stats block in source order:

| # | Label | Value |
| --- | --- | --- |
| 1 | Player | Player 1 _(scrubbed display name)_ |
| 2 | Status | Proposed |
| 3 | Race | Human (Fire Affinity) |
| 4 | Cultivation Tier | Silver (C) |
| 5 | Hit Points/Essence | 42 |
| 6 | Total Fire Affinity | 12 |
| 7 | Total Metal Affinity | 4 |
| 8 | Total Attack Affinity | 2 |
| 9 | Total Body Affinity | 8 |
| 10 | Total Shadow Affinity | 1 |
| 11 | Iron DR | 2 |
| 12 | Effective Attack Affinity | 0 |
| 13 | Effective Body Affinity | 6 |
| 14 | Effective Death Affinity | -2 |
| 15 | Effective Earth Affinity | -2 |
| 16 | Effective Fate Affinity | -2 |
| 17 | Effective Fire Affinity | 10 |
| 18 | Effective Life Affinity | -2 |
| 19 | Effective Light Affinity | -2 |
| 20 | Effective Metal Affinity | 2 |
| 21 | Effective Shadow Affinity | -1 |
| 22 | Effective Water Affinity | -2 |
| 23 | Effective Wood Affinity | -2 |

The `<h2 class="c">Presentation</h2>` + `<div class="teaser">…</div>`
block is carved out into `CharacterSheet.teaserHtml` / `.presentationHtml`
so Task 010's UI can render it next to the existing
`CharacterStats.teaser`/`CharacterStats.presentation` fields without
double-rendering.

## Re-capturing

1. Drop a fresh raw HTML at
   `functions/test/fixtures/crucible-character-sheet-unscrubbed/character-sheet-oxe9sb0w02ig.html`.
   That path is gitignored (`.gitignore` line 39:
   `functions/test/fixtures/*-unscrubbed/`), so the raw file stays
   local and never enters version control.
2. Run the scrubber once:
   ```sh
   node -e '
     const fs = require("fs");
     const { scrubCharacterSheetHtml } = require("./scripts/lib/capture-lm-fixture.js");
     const raw = fs.readFileSync("functions/test/fixtures/crucible-character-sheet-unscrubbed/character-sheet-oxe9sb0w02ig.html", "utf8");
     const { scrubbed } = scrubCharacterSheetHtml(raw, "task-008-crucible-character-sheet");
     fs.writeFileSync("functions/test/fixtures/crucible-character-sheet/character-sheet-oxe9sb0w02ig.html", scrubbed, "utf8");
   '
   ```
3. Verify no PII leaked:
   ```sh
   grep -E '@sovereignscrolls\.larpmanager\.com' functions/test/fixtures/crucible-character-sheet/
   ```
   (Returns nothing on a clean scrub.)
4. Re-run `scripts/test.sh` — if the LM template drifted, the pinned
   parser test will fail with a diff that tells you which row changed.
