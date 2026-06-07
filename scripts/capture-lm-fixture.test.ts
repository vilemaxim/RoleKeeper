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
    exportJsonString,
    scrubbed: true,
    seed: "my-event-2026-1::stamp",
  });

  assert.equal(meta.baseUrl, "https://lm.example.test");
  assert.equal(meta.eventSlug, "my-event-2026-1");
  assert.equal(meta.capturedAt, "2026-06-02T14:00:00.000Z");
  assert.equal(meta.characterCount, 1);
  assert.equal(meta.registrationCount, 2);
  assert.equal(meta.scrubbed, true);
  assert.equal(meta.seed, "my-event-2026-1::stamp");

  // sha256 of the export JSON string, hex-encoded, 64 chars.
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
    exportJsonString: "{}",
    seed: "s",
  };
  const yes = buildCaptureMeta({ ...base, scrubbed: true });
  const no = buildCaptureMeta({ ...base, scrubbed: false });
  assert.equal(yes.scrubbed, true);
  assert.equal(no.scrubbed, false);
});
