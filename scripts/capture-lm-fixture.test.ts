/**
 * Unit tests for the PURE scrub helpers exported by `capture-lm-fixture.ts`.
 *
 * Only the pure helpers (email replacement, JSON field redaction) are tested
 * in CI — the HTTP-touching parts (`establishLarpManagerSession`,
 * `fetchCharacterExportJson`, `fetchRegistrationsExportZip`) are validated
 * manually against a live LarpManager instance per task 002 acceptance
 * criteria. These tests must run without any network access and without
 * needing the Firestore emulator.
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";

import {
  scrubEmailsInCsv,
  scrubCharacterExportJson,
  scrubManageRegistrationsHtml,
  scrubCharacterSheetHtml,
  countCsvRows,
  buildCaptureMeta,
} from "./capture-lm-fixture";

// --- scrubEmailsInCsv -------------------------------------------------------

test("scrubEmailsInCsv replaces every email with a user{N}@example.test placeholder", () => {
  const csv = [
    "Name,Email,Characters",
    "Alice,alice@example.com,Alice Hero",
    'Bob,"bob@test.org","Hero One"',
  ].join("\n");
  const r = scrubEmailsInCsv(csv, "seed-1");
  assert.ok(
    !r.scrubbed.includes("alice@example.com"),
    "raw alice email must be gone"
  );
  assert.ok(
    !r.scrubbed.includes("bob@test.org"),
    "raw bob email must be gone"
  );
  assert.match(
    r.scrubbed,
    /user\d+@example\.test/,
    "placeholder pattern must appear"
  );
});

test("scrubEmailsInCsv is stable: same email → same placeholder within one capture", () => {
  const csv = [
    "Name,Email,Characters",
    "Alice,alice@example.com,Alice Hero",
    "Alice2,alice@example.com,Second Char",
    "Bob,bob@test.org,Bobby",
  ].join("\n");
  const r = scrubEmailsInCsv(csv, "seed-1");
  const placeholders = r.scrubbed.match(/user\d+@example\.test/g) ?? [];
  assert.equal(placeholders.length, 3, "alice appears 2x + bob 1x = 3 placeholders");
  assert.equal(
    new Set(placeholders).size,
    2,
    "two distinct real emails → two distinct placeholders"
  );
  // The two alice occurrences must map to the SAME placeholder.
  assert.equal(placeholders[0], placeholders[1], "stable mapping per email");
});

test("scrubEmailsInCsv preserves non-email CSV content (headers, names, character names)", () => {
  const csv = [
    "Name,Email,Characters",
    "Alice,alice@example.com,Alice Hero",
  ].join("\n");
  const r = scrubEmailsInCsv(csv, "seed-1");
  assert.ok(r.scrubbed.includes("Name,Email,Characters"), "header row preserved");
  assert.ok(r.scrubbed.includes("Alice"), "non-email Name column preserved");
  assert.ok(r.scrubbed.includes("Alice Hero"), "Characters column preserved");
});

test("scrubEmailsInCsv is deterministic given the same seed and input", () => {
  const csv = "Email\nalice@example.com\nbob@test.org\n";
  const r1 = scrubEmailsInCsv(csv, "seed-1");
  const r2 = scrubEmailsInCsv(csv, "seed-1");
  assert.equal(r1.scrubbed, r2.scrubbed, "same seed → identical scrubbed output");
  assert.deepEqual(r1.mapping, r2.mapping, "same seed → identical mapping");
});

test("scrubEmailsInCsv differing seeds may produce different placeholder ordering", () => {
  // We don't require placeholders to differ across seeds (user1@ might collide
  // by happenstance), only that the mapping is stable within a single seed.
  // What we DO require is that the mapping records each replacement.
  const csv = "Email\nalice@example.com\n";
  const r = scrubEmailsInCsv(csv, "seed-1");
  assert.equal(Object.keys(r.mapping).length, 1);
  assert.ok(r.mapping["alice@example.com"]?.endsWith("@example.test"));
});

test("scrubEmailsInCsv returns the CSV unchanged when no emails are present", () => {
  const csv = "Name,Number\nAlice,1\nBob,2\n";
  const r = scrubEmailsInCsv(csv, "seed-1");
  assert.equal(r.scrubbed, csv);
  assert.deepEqual(r.mapping, {});
});

// --- scrubCharacterExportJson ----------------------------------------------

test("scrubCharacterExportJson replaces `name` with a same-length placeholder", () => {
  const input = {
    "1": { number: 1, uuid: "uuid-a", name: "Alice Hero", teaser: "A short tale" },
  };
  const out = scrubCharacterExportJson(input, "seed-1");
  assert.equal(
    String(out["1"]?.name).length,
    "Alice Hero".length,
    "scrubbed name length must match"
  );
  assert.notEqual(out["1"]?.name, "Alice Hero", "scrubbed name content differs");
});

test("scrubCharacterExportJson replaces `teaser` with a same-length placeholder", () => {
  const input = {
    "1": { number: 1, uuid: "uuid-a", name: "X", teaser: "A long teaser string" },
  };
  const out = scrubCharacterExportJson(input, "seed-1");
  assert.equal(
    String(out["1"]?.teaser).length,
    "A long teaser string".length
  );
  assert.notEqual(out["1"]?.teaser, "A long teaser string");
});

test("scrubCharacterExportJson keeps `uuid` and `number` untouched (matching tests still resolve)", () => {
  const input = {
    "42": { number: 42, uuid: "uuid-z", name: "X", teaser: "Y" },
  };
  const out = scrubCharacterExportJson(input, "seed-1");
  assert.equal(out["42"]?.uuid, "uuid-z", "uuid must be preserved");
  assert.equal(out["42"]?.number, 42, "number must be preserved");
});

test(
  "scrubCharacterExportJson scrubs any string key matching " +
    "/email|player|user|real_name/i",
  () => {
    const input = {
      "1": {
        number: 1,
        uuid: "uuid-a",
        name: "X",
        teaser: "Y",
        player_name: "Bob Player",
        contact_email: "bob@x.com",
        real_name: "Robert",
        User: "BobUser",
      } as Record<string, unknown>,
    };
    const out = scrubCharacterExportJson(
      input as never,
      "seed-1"
    ) as unknown as Record<string, Record<string, unknown>>;
    const c = out["1"]!;
    assert.notEqual(c.player_name, "Bob Player");
    assert.notEqual(c.contact_email, "bob@x.com");
    assert.notEqual(c.real_name, "Robert");
    assert.notEqual(c.User, "BobUser");
    assert.equal(String(c.player_name).length, "Bob Player".length);
    assert.equal(String(c.contact_email).length, "bob@x.com".length);
    assert.equal(String(c.real_name).length, "Robert".length);
    assert.equal(String(c.User).length, "BobUser".length);
  }
);

test("scrubCharacterExportJson leaves unrelated string keys alone", () => {
  const input = {
    "1": {
      number: 1,
      uuid: "uuid-a",
      name: "X",
      teaser: "Y",
      faction: "Red Hand",
      title: "Captain",
    } as Record<string, unknown>,
  };
  const out = scrubCharacterExportJson(
    input as never,
    "seed-1"
  ) as unknown as Record<string, Record<string, unknown>>;
  const c = out["1"]!;
  assert.equal(c.faction, "Red Hand", "non-sensitive key faction must be intact");
  assert.equal(c.title, "Captain", "non-sensitive key title must be intact");
});

test("scrubCharacterExportJson handles nested objects recursively", () => {
  const input = {
    "1": {
      number: 1,
      uuid: "uuid-a",
      name: "Top",
      nested: { player_name: "Inner Bob", value: 42 },
    } as Record<string, unknown>,
  };
  const out = scrubCharacterExportJson(
    input as never,
    "seed-1"
  ) as unknown as Record<string, Record<string, unknown>>;
  const nested = out["1"]!.nested as Record<string, unknown>;
  assert.notEqual(nested.player_name, "Inner Bob");
  assert.equal(String(nested.player_name).length, "Inner Bob".length);
  assert.equal(nested.value, 42, "non-string nested value untouched");
});

test("scrubCharacterExportJson is deterministic for the same seed and input", () => {
  const input = {
    "1": { number: 1, uuid: "uuid-a", name: "Alice Hero", teaser: "story" },
  };
  const a = scrubCharacterExportJson(input, "seed-1");
  const b = scrubCharacterExportJson(input, "seed-1");
  assert.deepEqual(a, b, "same seed + input must produce identical output");
});

test("scrubCharacterExportJson different seed → different placeholder text (same length)", () => {
  const input = {
    "1": { number: 1, uuid: "uuid-a", name: "Alice Hero", teaser: "story" },
  };
  const a = scrubCharacterExportJson(input, "seed-1");
  const b = scrubCharacterExportJson(input, "seed-2");
  assert.notEqual(
    a["1"]?.name,
    b["1"]?.name,
    "different seeds should produce different placeholder text"
  );
  assert.equal(
    String(a["1"]?.name).length,
    String(b["1"]?.name).length,
    "length is still preserved regardless of seed"
  );
});

test("scrubCharacterExportJson handles arrays recursively", () => {
  const input = {
    "1": {
      number: 1,
      uuid: "uuid-a",
      name: "X",
      teaser: "Y",
      players: [
        { player_name: "P1", role: "lead" },
        { player_name: "P22", role: "support" },
      ],
    } as Record<string, unknown>,
  };
  const out = scrubCharacterExportJson(
    input as never,
    "seed-1"
  ) as unknown as Record<string, Record<string, unknown>>;
  const players = out["1"]!.players as Array<Record<string, unknown>>;
  assert.equal(players.length, 2);
  assert.notEqual(players[0]?.player_name, "P1");
  assert.equal(String(players[0]?.player_name).length, "P1".length);
  assert.equal(players[0]?.role, "lead", "non-sensitive role preserved");
  assert.notEqual(players[1]?.player_name, "P22");
  assert.equal(String(players[1]?.player_name).length, "P22".length);
});

test("scrubCharacterExportJson never copies the input by reference (no mutation of caller's object)", () => {
  const input = {
    "1": { number: 1, uuid: "uuid-a", name: "Alice", teaser: "T" },
  };
  const original = JSON.stringify(input);
  scrubCharacterExportJson(input, "seed-1");
  assert.equal(
    JSON.stringify(input),
    original,
    "caller's input object must not be mutated"
  );
});

// --- countCsvRows -----------------------------------------------------------
//
// countCsvRows underpins meta.json.registrationCount. The capture script
// must not mis-report the row count when a CSV is empty, has only a header,
// uses CRLF line endings, or has trailing blank lines. These tests pin
// that behavior so a future refactor cannot quietly regress it.

test("countCsvRows: returns 0 for an empty string", () => {
  assert.equal(countCsvRows(""), 0);
});

test("countCsvRows: returns 0 when only a header row is present", () => {
  assert.equal(countCsvRows("Name,Email,Characters\n"), 0);
});

test("countCsvRows: counts data rows (header + 2 → 2)", () => {
  const csv = "Name,Email\nAlice,a@x.test\nBob,b@x.test\n";
  assert.equal(countCsvRows(csv), 2);
});

test("countCsvRows: handles CRLF line endings", () => {
  const csv = "Name,Email\r\nAlice,a@x.test\r\nBob,b@x.test\r\n";
  assert.equal(countCsvRows(csv), 2);
});

test("countCsvRows: skips blank lines (trailing newlines / stray blanks)", () => {
  const csv = "Name,Email\nAlice,a@x.test\n\nBob,b@x.test\n\n\n";
  assert.equal(countCsvRows(csv), 2);
});

// --- buildCaptureMeta -------------------------------------------------------
//
// buildCaptureMeta is the pure packaging step for the values that end up in
// meta.json. Tests pass an explicit `capturedAt` and `exportJsonString` so
// the helper is fully deterministic — the live captureFromLm() supplies
// `new Date().toISOString()` and the stringified export. By extracting this,
// the meta shape (sha256OfExport, scrubbed flag, seed) becomes verifiable
// in CI without any LarpManager network round-trip.

test("buildCaptureMeta: produces all required fields with correct values", () => {
  const exportJsonString = '{"1":{"uuid":"uuid-a","number":1,"name":"X"}}';
  const meta = buildCaptureMeta({
    baseUrl: "https://lm.example.test",
    eventSlug: "my-event-2026-1",
    capturedAt: "2026-06-02T14:00:00.000Z",
    characterCount: 1,
    registrationCount: 2,
    manageRegistrationRowCount: 3,
    exportJsonString,
    scrubbed: true,
    seed: "my-event-2026-1::stamp",
  });

  assert.equal(meta.baseUrl, "https://lm.example.test");
  assert.equal(meta.eventSlug, "my-event-2026-1");
  assert.equal(meta.capturedAt, "2026-06-02T14:00:00.000Z");
  assert.equal(meta.characterCount, 1);
  assert.equal(meta.registrationCount, 2);
  assert.equal(meta.manageRegistrationRowCount, 3);
  assert.equal(meta.scrubbed, true);
  assert.equal(meta.seed, "my-event-2026-1::stamp");

  assert.match(meta.sha256OfExport, /^[0-9a-f]{64}$/);
});

test("buildCaptureMeta: sha256OfExport is the SHA-256 of the export JSON string", () => {
  const exportJsonString = '{"hello":"world"}';
  // Pre-computed: echo -n '{"hello":"world"}' | sha256sum
  const expected =
    "93a23971a914e5eacbf0a8d25154cda309c3c1c72fbb9914d47c60f3cb681588";
  const meta = buildCaptureMeta({
    baseUrl: "https://lm.example.test",
    eventSlug: "e",
    capturedAt: "2026-01-01T00:00:00.000Z",
    characterCount: 0,
    registrationCount: 0,
    manageRegistrationRowCount: 0,
    exportJsonString,
    scrubbed: false,
    seed: "s",
  });
  assert.equal(meta.sha256OfExport, expected);
});

test("buildCaptureMeta: scrubbed flag is preserved as-is (true and false both round-trip)", () => {
  const base = {
    baseUrl: "https://lm.example.test",
    eventSlug: "e",
    capturedAt: "2026-01-01T00:00:00.000Z",
    characterCount: 0,
    registrationCount: 0,
    manageRegistrationRowCount: 0,
    exportJsonString: "{}",
    seed: "s",
  };
  const yes = buildCaptureMeta({ ...base, scrubbed: true });
  const no = buildCaptureMeta({ ...base, scrubbed: false });
  assert.equal(yes.scrubbed, true);
  assert.equal(no.scrubbed, false);
});

// --- scrubManageRegistrationsHtml -------------------------------------------
//
// Scrubs the LarpManager /manage/registrations/ HTML page for capture
// before it's written into a fixture. Contract pinned here so future
// changes can't silently regress what's published to the repo.

const SAMPLE_ROW_HTML = `
<tr id="reg00000001">
  <td>
    <a href="/evt/manage/registrations/reg00000001/edit/" qtip="Edit"><i></i></a>
  </td>
  <td>
    Jeffrey Brite
    <a href="#" class="post_popup_member" pop="te93m14a7lly"><i></i></a>
  </td>
  <td class="email">jeffrey@example.com</td>
  <td>
    <a href="/evt/manage/characters/charuuid0001/edit/">#1 Heldrek</a>
  </td>
</tr>
<tr id="reg00000002">
  <td>
    <a href="/evt/manage/registrations/reg00000002/edit/" qtip="Edit"><i></i></a>
  </td>
  <td>
    Alice Player
    <a href="#" class="post_popup_member" pop="usr222222222"><i></i></a>
  </td>
  <td class="email">alice@example.com</td>
  <td></td>
</tr>`.trim();

test("scrubManageRegistrationsHtml: removes every email", () => {
  const r = scrubManageRegistrationsHtml(SAMPLE_ROW_HTML, "seed-1");
  assert.ok(
    !r.scrubbed.includes("jeffrey@example.com"),
    "jeffrey email must be gone"
  );
  assert.ok(
    !r.scrubbed.includes("alice@example.com"),
    "alice email must be gone"
  );
  assert.match(r.scrubbed, /user\d+@example\.test/, "placeholder pattern appears");
  assert.equal(
    Object.keys(r.emailMapping).length,
    2,
    "two real emails → two mapping entries"
  );
});

test(
  "scrubManageRegistrationsHtml: replaces every pop='<lm_user_uuid>' " +
    "with a deterministic synthetic id of the same shape",
  () => {
    const r = scrubManageRegistrationsHtml(SAMPLE_ROW_HTML, "seed-1");
    assert.ok(
      !r.scrubbed.includes("te93m14a7lly"),
      "jeffrey's lm user uuid must be gone"
    );
    assert.ok(
      !r.scrubbed.includes("usr222222222"),
      "alice's lm user uuid must be gone"
    );
    // Synthetic ids still match the parser's pop attribute regex.
    const popMatches = r.scrubbed.match(/\bpop=["']([a-z0-9]{4,40})["']/gi);
    assert.equal(popMatches?.length, 2, "two pop= attrs preserved with new values");
    assert.equal(Object.keys(r.userUuidMapping).length, 2);
  }
);

test(
  "scrubManageRegistrationsHtml: replaces the row 'name' td free text " +
    "with a 'Player N' placeholder",
  () => {
    const r = scrubManageRegistrationsHtml(SAMPLE_ROW_HTML, "seed-1");
    assert.ok(
      !r.scrubbed.includes("Jeffrey Brite"),
      "display name must be gone"
    );
    assert.ok(
      !r.scrubbed.includes("Alice Player"),
      "display name must be gone"
    );
    assert.match(r.scrubbed, /Player 1/);
    assert.match(r.scrubbed, /Player 2/);
    assert.equal(r.displayNameReplacements, 2);
  }
);

test(
  "scrubManageRegistrationsHtml: preserves all the structural elements the " +
    "parser depends on (registration ids, character uuids, post_popup_member, " +
    "td.email)",
  () => {
    const r = scrubManageRegistrationsHtml(SAMPLE_ROW_HTML, "seed-1");
    // Registration <tr id> uuids are NOT scrubbed (event-internal, not PII).
    assert.ok(
      r.scrubbed.includes('<tr id="reg00000001">'),
      "registration id preserved"
    );
    assert.ok(
      r.scrubbed.includes('<tr id="reg00000002">'),
      "second registration id preserved"
    );
    // Character uuids inside manage/characters/<uuid>/edit/ are NOT scrubbed.
    assert.ok(r.scrubbed.includes("charuuid0001"), "character uuid preserved");
    // Discriminating attributes the parser anchors on remain present.
    assert.ok(
      r.scrubbed.includes('class="post_popup_member"'),
      "post_popup_member class preserved"
    );
    assert.ok(r.scrubbed.includes('class="email"'), 'td class="email" preserved');
    // The pop= attribute still carries an id of the parser-required shape.
    assert.match(
      r.scrubbed,
      /\bpop=["'][a-z0-9]{4,40}["']/,
      "pop= attr still parses"
    );
    // And the email td now carries the placeholder email shape.
    assert.match(
      r.scrubbed,
      /<td\b[^>]*class=["']email["'][^>]*>\s*user\d+@example\.test/,
      "td.email now contains a scrubbed placeholder email"
    );
  }
);

test(
  "scrubManageRegistrationsHtml: deterministic — same seed + input → " +
    "identical scrubbed output",
  () => {
    const a = scrubManageRegistrationsHtml(SAMPLE_ROW_HTML, "seed-1");
    const b = scrubManageRegistrationsHtml(SAMPLE_ROW_HTML, "seed-1");
    assert.equal(a.scrubbed, b.scrubbed);
    assert.deepEqual(a.emailMapping, b.emailMapping);
    assert.deepEqual(a.userUuidMapping, b.userUuidMapping);
  }
);

// --- scrubCharacterSheetHtml ------------------------------------------------
//
// Scrubs the LarpManager `/{slug}/character/{uuid}/` HTML for fixture
// capture. Contract pinned here so the committed scrubbed fixture is
// reliably PII-free. See `functions/src/larpmanager/characterSheet.test.ts`
// for the downstream parser contract that consumes the scrubbed output.

/** Minimal-but-representative sample mirroring the live LM character
 * sheet template: og:url meta + Player anchor (with /public/<uuid>/)
 * + an owner_uuid attribute + a `pop=` attribute + the topbar "Hi, Name!"
 * greeting that re-uses the display name. */
const CHARACTER_SHEET_SAMPLE = `
<!DOCTYPE html>
<html><head>
<meta property="og:url" content="/crucible/character/oxe9sb0w02ig/">
</head><body>
<div id="topbar"><span>Hi, Jeffrey Brite!</span></div>
<div class="page_character_view"><div class="character" data-owner_uuid="te93m14a7lly">
  <div class="presentation"><div class="first">
    <div class="go-inline" id="char_player">
      <b>Player:</b>
      <a href="https://sovereignscrolls.larpmanager.com/public/te93m14a7lly/">
          Jeffrey Brite
      </a>
    </div>
    <div class="go-inline"><b>Status:&nbsp;</b>Proposed</div>
    <div class="go-inline"><b>Hit Points/Essence:&nbsp;</b>42</div>
  </div>
    <h2 class="c">Presentation</h2>
    <div class="teaser"><p>Fire Mage</p></div>
  </div>
</div></div>
<a href="mailto:jeffrey@example.com">contact</a>
<a class="post_popup_member" pop="te93m14a7lly">peer</a>
</body></html>`.trim();

test(
  "scrubCharacterSheetHtml: removes every email-shaped substring",
  () => {
    const r = scrubCharacterSheetHtml(CHARACTER_SHEET_SAMPLE, "seed-1");
    assert.ok(
      !r.scrubbed.includes("jeffrey@example.com"),
      "raw jeffrey email must be gone"
    );
    assert.match(
      r.scrubbed,
      /user\d+@example\.test/,
      "placeholder pattern must appear"
    );
    assert.equal(
      Object.keys(r.emailMapping).length,
      1,
      "single real email → single mapping entry"
    );
  }
);

test(
  "scrubCharacterSheetHtml: replaces LM user uuids in pop=, owner_uuid=, " +
    "and /public/<uuid>/ URLs with deterministic synthetic ids of the " +
    "same [a-z0-9]{4,40} shape",
  () => {
    const r = scrubCharacterSheetHtml(CHARACTER_SHEET_SAMPLE, "seed-1");
    assert.ok(
      !r.scrubbed.includes("te93m14a7lly"),
      "real LM user uuid must be gone from every site (pop, owner_uuid, /public/)"
    );
    // All three sites still carry an id of the parser-compatible shape.
    assert.match(
      r.scrubbed,
      /\bpop=["'][a-z0-9]{4,40}["']/,
      "pop= attribute still carries a [a-z0-9]{4,40} value"
    );
    assert.match(
      r.scrubbed,
      /data-owner_uuid=["'][a-z0-9]{4,40}["']/,
      "owner_uuid attribute still carries a [a-z0-9]{4,40} value"
    );
    assert.match(
      r.scrubbed,
      /\/public\/[a-z0-9]{4,40}\//,
      "/public/<uuid>/ URL still carries a [a-z0-9]{4,40} segment"
    );
    // One real uuid (te93m14a7lly) maps to one synthetic uuid even though
    // it appears in three sites in the source HTML.
    assert.equal(Object.keys(r.userUuidMapping).length, 1);
    const placeholder = r.userUuidMapping["te93m14a7lly"];
    assert.ok(
      placeholder && /^usr\d+[a-f0-9]{8}$/.test(placeholder),
      `placeholder must be 'usr<N><8-char hash>', got: ${String(placeholder)}`
    );
  }
);

test(
  "scrubCharacterSheetHtml: replaces the display name LM renders next to " +
    "the <b>Player:</b> row with a deterministic 'Player N' placeholder, " +
    "and propagates that replacement to every other occurrence of the " +
    "same name in the document (e.g. the 'Hi, {name}!' topbar)",
  () => {
    const r = scrubCharacterSheetHtml(CHARACTER_SHEET_SAMPLE, "seed-1");
    assert.ok(
      !r.scrubbed.includes("Jeffrey Brite"),
      "display name must be gone from every occurrence (sheet + topbar)"
    );
    assert.match(r.scrubbed, /Player 1\b/);
    assert.deepEqual(
      Object.keys(r.displayNameMapping),
      ["Jeffrey Brite"],
      "single display name → single mapping entry"
    );
  }
);

test(
  "scrubCharacterSheetHtml: PRESERVES the character uuid in /character/<uuid>/ " +
    "URLs and in the og:url meta tag (needed for the stable fixture filename)",
  () => {
    const r = scrubCharacterSheetHtml(CHARACTER_SHEET_SAMPLE, "seed-1");
    assert.ok(
      r.scrubbed.includes("oxe9sb0w02ig"),
      "character uuid must survive scrubbing"
    );
    assert.match(
      r.scrubbed,
      /\/crucible\/character\/oxe9sb0w02ig\//,
      "character uuid still appears inside its /character/<uuid>/ URL"
    );
    assert.match(
      r.scrubbed,
      /og:url[^>]*content=["']\/crucible\/character\/oxe9sb0w02ig\//,
      "character uuid still appears in og:url meta"
    );
  }
);

test(
  "scrubCharacterSheetHtml: deterministic — same seed + input → identical " +
    "scrubbed output and identical mappings",
  () => {
    const a = scrubCharacterSheetHtml(CHARACTER_SHEET_SAMPLE, "seed-1");
    const b = scrubCharacterSheetHtml(CHARACTER_SHEET_SAMPLE, "seed-1");
    assert.equal(a.scrubbed, b.scrubbed);
    assert.deepEqual(a.emailMapping, b.emailMapping);
    assert.deepEqual(a.userUuidMapping, b.userUuidMapping);
    assert.deepEqual(a.displayNameMapping, b.displayNameMapping);
  }
);

test(
  "scrubCharacterSheetHtml: idempotent under double-scrub — re-running the " +
    "scrubber on already-scrubbed output produces the same bytes " +
    "(placeholders are skipped, not escalated)",
  () => {
    const once = scrubCharacterSheetHtml(CHARACTER_SHEET_SAMPLE, "seed-1");
    const twice = scrubCharacterSheetHtml(once.scrubbed, "seed-1");
    assert.equal(
      twice.scrubbed,
      once.scrubbed,
      "double-scrub must be a no-op — committed fixture stays stable when " +
        "the scrubber accidentally runs twice in a capture pipeline"
    );
  }
);

// --- buildCaptureMeta: characterSheetUuids round-trip ---------------------

test(
  "buildCaptureMeta: characterSheetUuids round-trips into the returned meta " +
    "in the order supplied (downstream readers know which sheets were captured)",
  () => {
    const meta = buildCaptureMeta({
      baseUrl: "https://lm.example.test",
      eventSlug: "my-event-2026-1",
      capturedAt: "2026-06-02T14:00:00.000Z",
      characterCount: 1,
      registrationCount: 2,
      manageRegistrationRowCount: 3,
      characterSheetUuids: ["oxe9sb0w02ig", "anotheruuid01"],
      exportJsonString: "{}",
      scrubbed: true,
      seed: "s",
    });
    assert.deepEqual(meta.characterSheetUuids, [
      "oxe9sb0w02ig",
      "anotheruuid01",
    ]);
  }
);

test(
  "buildCaptureMeta: omits characterSheetUuids (or emits an empty array) " +
    "when none was supplied, so existing fixture meta.json files round-trip",
  () => {
    const meta = buildCaptureMeta({
      baseUrl: "https://lm.example.test",
      eventSlug: "my-event-2026-1",
      capturedAt: "2026-06-02T14:00:00.000Z",
      characterCount: 1,
      registrationCount: 2,
      manageRegistrationRowCount: 3,
      exportJsonString: "{}",
      scrubbed: true,
      seed: "s",
    });
    // Either the field is absent or it's an empty array — never a leaked
    // non-empty list from a different capture.
    const value = meta.characterSheetUuids ?? [];
    assert.deepEqual(value, []);
  }
);
