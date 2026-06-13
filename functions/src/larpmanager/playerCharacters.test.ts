import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import type * as admin from "firebase-admin";

import {
  buildCharacterCreatePageUrl,
  findCharactersByEmailInExportMap,
  resolveCharactersByNames,
  shortIdForLmCharacter,
  syncPlayerCharactersForUser,
} from "./playerCharacters";
import { registrationDocIdForEmail } from "./registrations";
import { gameEventBase } from "../gameTenant";
import {
  makeFirestoreStub,
  type StubDocSeed,
  withCapturedLogs,
} from "../_testing/firestoreStub";
import type { LarpManagerCharacterExport, LarpManagerSyncConfig } from "./types";

const TENANT = { instanceId: "g1", eventSlug: "evt1" };
const BASE = gameEventBase(TENANT);
const CONFIG: LarpManagerSyncConfig = {
  baseUrl: "https://lm.example",
  eventSlug: "evt1",
  fetchDetails: false,
};
const UID = "user-1";
const EMAIL = "player@example.com";
const REG_DOC_ID = registrationDocIdForEmail(EMAIL);

test("buildCharacterCreatePageUrl", () => {
  const cfg: LarpManagerSyncConfig = {
    baseUrl: "https://lm.example/",
    eventSlug: "my-event-1",
    fetchDetails: false,
  };
  assert.equal(
    buildCharacterCreatePageUrl(cfg),
    "https://lm.example/my-event-1/character/create/"
  );
});

test("resolveCharactersByNames matches export by name", () => {
  const exportMap = {
    "1": { number: 1, name: "Alice Hero", uuid: "uuid-a" },
    "2": { number: 42, name: "Bob Scout", uuid: "uuid-b" },
  };
  const resolved = resolveCharactersByNames(exportMap, [
    "alice hero",
    "Bob Scout",
    "Unknown",
  ]);
  assert.equal(resolved.length, 2);
  assert.deepEqual(resolved[0], {
    uuid: "uuid-a",
    name: "Alice Hero",
    number: 1,
  });
});

test("shortIdForLmCharacter uses number when present", () => {
  assert.equal(
    shortIdForLmCharacter({ uuid: "x", name: "A", number: 7 }),
    "007"
  );
});

// --- syncPlayerCharactersForUser end-to-end (Task 001 regression coverage) ---

test(
  "syncPlayerCharactersForUser: registration present but characterNames empty " +
    "and no existing /characters doc → hasCharacter:false + diagnostic log",
  async () => {
    const { db, writes } = makeFirestoreStub([
      {
        path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
        data: { emailLower: EMAIL, characterNames: [] },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(result.hasCharacter, false);
      assert.equal(result.characterCount, 0);
      assert.equal(writes.length, 0, "no character writes should occur");
      assert.ok(
        logs.some((l) =>
          l.msg.includes("registration has empty characterNames")
        ),
        "should emit the empty-characterNames diagnostic log line"
      );
    });
  }
);

test(
  "syncPlayerCharactersForUser: characterNames has one entry that matches " +
    "the mirror export → writes /characters/{uuid} + lookup doc",
  async () => {
    const { db, store } = makeFirestoreStub([
      {
        path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
        data: { emailLower: EMAIL, characterNames: ["Alice Hero"] },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-a`,
        data: { name: "Alice Hero", uuid: "uuid-a", number: 1 },
      },
    ]);
    await withCapturedLogs(async () => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(result.hasCharacter, true);
      assert.equal(result.characterCount, 1);

      const charDoc = store.get(`${BASE}/characters/uuid-a`);
      assert.ok(charDoc, "character doc should be written at /characters/uuid-a");
      assert.equal(charDoc?.ownerId, UID);
      assert.equal(charDoc?.shortId, "001");
      assert.equal(charDoc?.larpManagerUuid, "uuid-a");
      assert.equal(charDoc?.isArchived, false);
      assert.equal(charDoc?.source, "larpmanager");
      assert.equal(charDoc?.name, "Alice Hero");

      const lookup = store.get(`${BASE}/characterShortIdLookup/001`);
      assert.ok(lookup, "lookup doc should be written at /.../001");
      assert.equal(lookup?.ownerId, UID);
      assert.equal(lookup?.characterId, "uuid-a");
    });
  }
);

test(
  "syncPlayerCharactersForUser: characterNames present but no name matches " +
    "the mirror export → hasCharacter:false + '0/N matched' diagnostic log",
  async () => {
    const { db, writes } = makeFirestoreStub([
      {
        path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
        data: { emailLower: EMAIL, characterNames: ["Alice Hero"] },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-b`,
        data: { name: "Bob Scout", uuid: "uuid-b", number: 2 },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(result.hasCharacter, false);
      assert.equal(result.characterCount, 0);
      assert.equal(writes.length, 0, "no writes when no name resolves");
      assert.ok(
        logs.some((l) => /0\/\d+\s+names?\s+matched\s+mirror\s+export/i.test(l.msg)),
        "should emit a '0/N names matched mirror export' diagnostic"
      );
    });
  }
);

test(
  "syncPlayerCharactersForUser: characterNames empty but uid already owns " +
    "a /characters doc → hasCharacter:true (legacy fallback)",
  async () => {
    const { db } = makeFirestoreStub([
      {
        path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
        data: { emailLower: EMAIL, characterNames: [] },
      },
      {
        path: `${BASE}/characters/legacy-1`,
        data: { ownerId: UID, isArchived: false, name: "Legacy" },
      },
    ]);
    await withCapturedLogs(async () => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(result.hasCharacter, true);
      assert.equal(result.characterCount, 1);
    });
  }
);

test(
  "syncPlayerCharactersForUser: PII safety — diagnostic logs never include " +
    "raw email or character names",
  async () => {
    const { db } = makeFirestoreStub([
      {
        path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
        data: { emailLower: EMAIL, characterNames: ["Secret Char Name"] },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-z`,
        data: { name: "Other", uuid: "uuid-z", number: 9 },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      const serialised = JSON.stringify(logs);
      assert.ok(
        !serialised.includes(EMAIL),
        `logs should never contain raw email, got: ${serialised}`
      );
      assert.ok(
        !serialised.includes("Secret Char Name"),
        `logs should never contain character name, got: ${serialised}`
      );
    });
  }
);

// --- Task 006 regression: organizer email-mirror fallback ------------------
//
// These tests cover the new organizer fallback path in
// `syncPlayerCharactersForUser`. The original bug: an organizer's character
// silently failed to write because organizers are not in the registrations
// CSV (`regExists: false` / `namesCount: 0`). The fix: when
// `options.isOrganizer === true` AND the registration-name path produces no
// characters, walk the bulk character mirror for an exact email match on any
// string field of the export entry. Matched 1 → write; 0 → return with a
// structured signal so `playerAccess` can show actionable copy; > 1 → don't
// auto-pick, surface ambiguity.

test("findCharactersByEmailInExportMap: matches exact email in any string field", () => {
  const exportMap: Record<string, LarpManagerCharacterExport> = {
    "1": { number: 1, name: "Alice", uuid: "u-a", player_email: "alice@x.test" },
    "2": { number: 2, name: "Bob", uuid: "u-b", player_email: "bob@x.test" },
    "3": { number: 3, name: "Carol", uuid: "u-c", user_email: "carol@x.test" },
  };
  const matched = findCharactersByEmailInExportMap(exportMap, "carol@x.test");
  assert.equal(matched.length, 1);
  assert.equal(matched[0]?.uuid, "u-c");
  assert.equal(matched[0]?.name, "Carol");
});

test("findCharactersByEmailInExportMap: case-insensitive and whitespace-tolerant", () => {
  const exportMap: Record<string, LarpManagerCharacterExport> = {
    "1": {
      number: 1,
      name: "Alice",
      uuid: "u-a",
      player_email: "  ALICE@X.TEST  ",
    },
  };
  const matched = findCharactersByEmailInExportMap(exportMap, "alice@x.test");
  assert.equal(matched.length, 1);
  assert.equal(matched[0]?.uuid, "u-a");
});

test(
  "findCharactersByEmailInExportMap: substring matches are rejected (no false " +
    "positives from free-text fields that mention the email)",
  () => {
    const exportMap: Record<string, LarpManagerCharacterExport> = {
      "1": {
        number: 1,
        name: "Decoy",
        uuid: "u-decoy",
        teaser: "Send fan mail to alice@x.test (placeholder).",
      },
      "2": {
        number: 2,
        name: "Alice",
        uuid: "u-alice",
        player_email: "alice@x.test",
      },
    };
    const matched = findCharactersByEmailInExportMap(exportMap, "alice@x.test");
    assert.equal(matched.length, 1, "decoy must NOT match — only exact-equal");
    assert.equal(matched[0]?.uuid, "u-alice");
  }
);

test("findCharactersByEmailInExportMap: dedupes by uuid across duplicate entries", () => {
  const exportMap: Record<string, LarpManagerCharacterExport> = {
    "1": { number: 1, name: "Alice", uuid: "u-a", player_email: "alice@x.test" },
    "2": { number: 1, name: "Alice", uuid: "u-a", email: "alice@x.test" },
  };
  const matched = findCharactersByEmailInExportMap(exportMap, "alice@x.test");
  assert.equal(matched.length, 1);
});

test("findCharactersByEmailInExportMap: returns multiple when email is genuinely shared", () => {
  const exportMap: Record<string, LarpManagerCharacterExport> = {
    "1": { number: 1, name: "Main", uuid: "u-1", player_email: "shared@x.test" },
    "2": { number: 2, name: "Alt", uuid: "u-2", player_email: "shared@x.test" },
  };
  const matched = findCharactersByEmailInExportMap(exportMap, "shared@x.test");
  assert.equal(matched.length, 2);
});

test("findCharactersByEmailInExportMap: empty email returns no matches", () => {
  const exportMap: Record<string, LarpManagerCharacterExport> = {
    "1": { number: 1, name: "Alice", uuid: "u-a", player_email: "alice@x.test" },
  };
  assert.equal(findCharactersByEmailInExportMap(exportMap, "").length, 0);
});

test(
  "syncPlayerCharactersForUser: TASK 006 — organizer + no registration + bulk " +
    "mirror has char with matching player_email → writes /characters",
  async () => {
    const { db, store } = makeFirestoreStub([
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-cassandra`,
        data: {
          number: 7,
          name: "Cassandra Quartermaster",
          uuid: "uuid-cassandra",
          export: {
            number: 7,
            name: "Cassandra Quartermaster",
            uuid: "uuid-cassandra",
            player_email: EMAIL,
          },
        },
      },
    ]);
    await withCapturedLogs(async () => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL,
        { isOrganizer: true }
      );
      assert.equal(result.hasCharacter, true);
      assert.equal(result.characterCount, 1);
      assert.equal(result.organizerLookupAttempted, true);
      assert.equal(result.organizerLookupMatches, 1);

      const charDoc = store.get(`${BASE}/characters/uuid-cassandra`);
      assert.ok(charDoc, "should write /characters/uuid-cassandra");
      assert.equal(charDoc?.ownerId, UID);
      assert.equal(charDoc?.larpManagerUuid, "uuid-cassandra");
      assert.equal(charDoc?.shortId, "007");
      assert.equal(charDoc?.name, "Cassandra Quartermaster");
      assert.equal(charDoc?.source, "larpmanager");
      assert.equal(charDoc?.isArchived, false);

      const lookup = store.get(`${BASE}/characterShortIdLookup/007`);
      assert.ok(lookup, "should write the short-id lookup");
      assert.equal(lookup?.characterId, "uuid-cassandra");
    });
  }
);

test(
  "syncPlayerCharactersForUser: TASK 006 — organizer + no registration + bulk " +
    "mirror has NO char with matching email → no writes, " +
    "organizerLookupAttempted:true, matches:0",
  async () => {
    const { db, writes } = makeFirestoreStub([
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-other`,
        data: {
          number: 1,
          name: "Other Player",
          uuid: "uuid-other",
          export: {
            number: 1,
            name: "Other Player",
            uuid: "uuid-other",
            player_email: "someone-else@example.test",
          },
        },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL,
        { isOrganizer: true }
      );
      assert.equal(result.hasCharacter, false);
      assert.equal(result.characterCount, 0);
      assert.equal(result.organizerLookupAttempted, true);
      assert.equal(result.organizerLookupMatches, 0);
      assert.equal(writes.length, 0, "no character writes when no email match");
      assert.ok(
        logs.some((l) => /organizer email-mirror lookup/i.test(l.msg)),
        "should emit the organizer email-mirror lookup diagnostic"
      );
    });
  }
);

test(
  "syncPlayerCharactersForUser: TASK 006 — organizer + multiple matching chars " +
    "→ no writes (ambiguous), organizerLookupMatches:2",
  async () => {
    const { db, writes } = makeFirestoreStub([
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-main`,
        data: {
          number: 1,
          name: "Main Character",
          uuid: "uuid-main",
          export: {
            number: 1,
            name: "Main Character",
            uuid: "uuid-main",
            player_email: EMAIL,
          },
        },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-alt`,
        data: {
          number: 2,
          name: "Alt Character",
          uuid: "uuid-alt",
          export: {
            number: 2,
            name: "Alt Character",
            uuid: "uuid-alt",
            player_email: EMAIL,
          },
        },
      },
    ]);
    await withCapturedLogs(async () => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL,
        { isOrganizer: true }
      );
      assert.equal(result.hasCharacter, false);
      assert.equal(result.characterCount, 0);
      assert.equal(result.organizerLookupAttempted, true);
      assert.equal(result.organizerLookupMatches, 2);
      assert.equal(writes.length, 0, "ambiguous matches must NOT auto-pick");
    });
  }
);

test(
  "syncPlayerCharactersForUser: TASK 006 — plain player (isOrganizer:false) " +
    "with no registration row does NOT trigger the email-mirror fallback",
  async () => {
    const { db, writes } = makeFirestoreStub([
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-cassandra`,
        data: {
          number: 7,
          name: "Cassandra",
          uuid: "uuid-cassandra",
          export: {
            number: 7,
            name: "Cassandra",
            uuid: "uuid-cassandra",
            player_email: EMAIL,
          },
        },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
        // isOrganizer omitted → defaults to false
      );
      assert.equal(result.hasCharacter, false);
      assert.equal(result.organizerLookupAttempted, false);
      assert.equal(result.organizerLookupMatches, 0);
      assert.equal(writes.length, 0, "plain players must not auto-claim by email");
      assert.ok(
        !logs.some((l) => /organizer email-mirror lookup/i.test(l.msg)),
        "should NOT emit the organizer fallback diagnostic for plain players"
      );
    });
  }
);

test(
  "syncPlayerCharactersForUser: TASK 006 — organizer fallback diagnostic " +
    "log is PII-free (no raw email, no character name)",
  async () => {
    const { db } = makeFirestoreStub([
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-secret`,
        data: {
          number: 1,
          name: "Secret Character Name",
          uuid: "uuid-secret",
          export: {
            number: 1,
            name: "Secret Character Name",
            uuid: "uuid-secret",
            player_email: EMAIL,
          },
        },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL,
        { isOrganizer: true }
      );
      const serialised = JSON.stringify(logs);
      assert.ok(
        !serialised.includes(EMAIL),
        `logs must never contain raw email, got: ${serialised}`
      );
      assert.ok(
        !serialised.includes("Secret Character Name"),
        `logs must never contain character name, got: ${serialised}`
      );
    });
  }
);

// --- Task 006 fixture-pinned regression -----------------------------------
//
// Loads `functions/test/fixtures/organizer-character-by-email/` and replays
// the exact production shape: an organizer (`organizer-svc@example.test`)
// who isn't in registration.csv but owns Cassandra Quartermaster via
// `player_email` on the bulk character export. Pre-fix, the join silently
// produced zero characters; post-fix the organizer fallback resolves
// `uuid-cassandra` and writes the character doc.

const FIXTURE_DIR = path.join(
  __dirname,
  "..",
  "..",
  "test",
  "fixtures",
  "organizer-character-by-email"
);

interface FixtureCharacter {
  number?: number;
  name?: string;
  uuid?: string;
  teaser?: string;
  player_email?: string;
  [key: string]: unknown;
}

function loadFixtureMirrorSeeds(eventBase: string): StubDocSeed[] {
  const exportPath = path.join(FIXTURE_DIR, "character-export.json");
  const raw = fs.readFileSync(exportPath, "utf8");
  const exportJson = JSON.parse(raw) as Record<string, FixtureCharacter>;
  const seeds: StubDocSeed[] = [];
  for (const ch of Object.values(exportJson)) {
    const uuid = ch.uuid;
    if (!uuid) continue;
    seeds.push({
      path: `${eventBase}/larpManagerMirrorChars/${uuid}`,
      data: {
        number: ch.number ?? null,
        name: ch.name ?? null,
        uuid,
        teaser: ch.teaser ?? null,
        export: ch as unknown as Record<string, unknown>,
        source: "larpmanager",
      },
    });
  }
  return seeds;
}

test(
  "syncPlayerCharactersForUser: TASK 006 fixture — pinned regression " +
    "(organizer-character-by-email/) resolves Cassandra via player_email",
  async () => {
    const FIXTURE_EMAIL = "organizer-svc@example.test";
    const fixtureSeeds = loadFixtureMirrorSeeds(BASE);
    const { db, store } = makeFirestoreStub(fixtureSeeds);

    await withCapturedLogs(async () => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        FIXTURE_EMAIL,
        { isOrganizer: true }
      );

      assert.equal(
        result.hasCharacter,
        true,
        "post-fix: organizer's Cassandra must resolve via email"
      );
      assert.equal(result.characterCount, 1);
      assert.equal(result.organizerLookupAttempted, true);
      assert.equal(result.organizerLookupMatches, 1);

      const charDoc = store.get(`${BASE}/characters/uuid-cassandra`);
      assert.ok(
        charDoc,
        "the fixture's uuid-cassandra must be written under /characters"
      );
      assert.equal(charDoc?.ownerId, UID);
      assert.equal(charDoc?.name, "Cassandra Quartermaster");
      assert.equal(charDoc?.larpManagerUuid, "uuid-cassandra");
    });
  }
);

test(
  "syncPlayerCharactersForUser: TASK 006 fixture — pre-fix variant " +
    "(no organizer fallback) leaves the organizer with zero characters",
  async () => {
    const FIXTURE_EMAIL = "organizer-svc@example.test";
    const fixtureSeeds = loadFixtureMirrorSeeds(BASE);
    const { db, writes } = makeFirestoreStub(fixtureSeeds);

    await withCapturedLogs(async () => {
      // Calling without `isOrganizer: true` reproduces the original bug:
      // the organizer-fallback path doesn't fire, the registration-name
      // path has no characterNames to consume, and no /characters doc is
      // ever written. This is the exact shape of the production failure
      // captured in `firebase functions:log` (Task 006 analysis).
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        FIXTURE_EMAIL
      );

      assert.equal(
        result.hasCharacter,
        false,
        "pre-fix shape: organizer has no character without the fallback"
      );
      assert.equal(result.characterCount, 0);
      assert.equal(result.organizerLookupAttempted, false);
      assert.equal(writes.length, 0);
    });
  }
);

// --- Task 006, second iteration: characters-by-email HTML join (Path 0) ---
//
// These tests cover the new top-of-funnel resolution path that pulls
// (email → character_uuid) tuples from the `larpManagerCharactersByEmail`
// collection (populated by `ingestManageRegistrationsHtml` from LM's
// manage/registrations HTML page). The HTML join is the most authoritative
// available signal: it uses LM's own user_uuid ↔ character_uuid mapping
// and includes organizers who never appear in the CSV export.
//
// Why this lives alongside the existing Task-006 email-mirror tests: the
// email-mirror path is still useful for LM events whose bulk export DOES
// expose `player_email` (some installations / event configs do); the
// HTML join is the only thing that works for the production crucible
// event where the bulk export carries no email at all.

const CHARS_BY_EMAIL_COL = "larpManagerCharactersByEmail";

test(
  "Task006-v2: Path-0 — characters-by-email doc with one uuid → " +
    "resolves via mirror lookup and writes /characters",
  async () => {
    const { db, store } = makeFirestoreStub([
      {
        path: `${BASE}/${CHARS_BY_EMAIL_COL}/${REG_DOC_ID}`,
        data: {
          emailLower: EMAIL,
          lmUserUuid: "usrjef0000ab",
          characterUuids: ["charuuid0001"],
        },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/charuuid0001`,
        data: {
          name: "Heldrek",
          uuid: "charuuid0001",
          number: 1,
        },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(result.hasCharacter, true);
      assert.equal(result.characterCount, 1);
      assert.equal(result.htmlLookupAttempted, true);
      assert.equal(result.htmlLookupMatches, 1);
      // The email-mirror path must NOT have run — Path 0 short-circuits.
      assert.equal(result.organizerLookupAttempted, false);

      const charDoc = store.get(`${BASE}/characters/charuuid0001`);
      assert.ok(charDoc, "should write /characters/charuuid0001");
      assert.equal(charDoc?.ownerId, UID);
      assert.equal(charDoc?.name, "Heldrek");
      assert.equal(charDoc?.shortId, "001");
      assert.equal(charDoc?.larpManagerUuid, "charuuid0001");
      assert.equal(charDoc?.source, "larpmanager");
      assert.equal(charDoc?.isArchived, false);

      assert.ok(
        logs.some((l) =>
          /characters-by-email HTML lookup/i.test(l.msg)
        ),
        "should emit the HTML-lookup diagnostic"
      );
      assert.ok(
        logs.some((l) =>
          /wrote characters \(HTML fallback\)/i.test(l.msg)
        ),
        "should emit the HTML-fallback wrote-characters diagnostic"
      );
    });
  }
);

test(
  "Task006-v2: Path-0 — works for plain players (not just organizers); " +
    "the HTML join is deterministic so it's safe for every role",
  async () => {
    const { db, store } = makeFirestoreStub([
      {
        path: `${BASE}/${CHARS_BY_EMAIL_COL}/${REG_DOC_ID}`,
        data: {
          emailLower: EMAIL,
          lmUserUuid: "usrplyr00001",
          characterUuids: ["charuuid0002"],
        },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/charuuid0002`,
        data: { name: "Tabor", uuid: "charuuid0002", number: 2 },
      },
    ]);
    await withCapturedLogs(async () => {
      // isOrganizer: false → still resolves via Path 0 because the HTML
      // join is exact (not the "don't auto-claim by email" heuristic).
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(result.hasCharacter, true);
      assert.equal(result.htmlLookupAttempted, true);
      assert.equal(result.htmlLookupMatches, 1);
      assert.ok(store.get(`${BASE}/characters/charuuid0002`));
    });
  }
);

test(
  "Task006-v2: Path-0 — multiple uuids resolve all matching mirror chars",
  async () => {
    const { db, store } = makeFirestoreStub([
      {
        path: `${BASE}/${CHARS_BY_EMAIL_COL}/${REG_DOC_ID}`,
        data: {
          emailLower: EMAIL,
          lmUserUuid: "usrjef0000ab",
          characterUuids: ["charuuid0001", "charuuid0099"],
        },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/charuuid0001`,
        data: { name: "Heldrek", uuid: "charuuid0001", number: 1 },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/charuuid0099`,
        data: { name: "Tabor", uuid: "charuuid0099", number: 99 },
      },
    ]);
    await withCapturedLogs(async () => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(result.hasCharacter, true);
      assert.equal(result.characterCount, 2);
      assert.equal(result.htmlLookupMatches, 2);
      assert.ok(store.get(`${BASE}/characters/charuuid0001`));
      assert.ok(store.get(`${BASE}/characters/charuuid0099`));
    });
  }
);

test(
  "Task006-v2: Path-0 — uuids present in HTML join but mirror sync hasn't " +
    "caught up yet → falls through to legacy paths, no false write",
  async () => {
    const { db, writes } = makeFirestoreStub([
      {
        path: `${BASE}/${CHARS_BY_EMAIL_COL}/${REG_DOC_ID}`,
        data: {
          emailLower: EMAIL,
          lmUserUuid: "usrjef0000ab",
          // Mirror has data, but NOT this uuid.
          characterUuids: ["charuuid0001"],
        },
      },
      // Mirror is populated but only has an unrelated character — the
      // realistic shape of "the bulk export ran but doesn't yet have
      // the user's char" (e.g. brand-new assignment not yet exported).
      // `loadCharacterExportMap` short-circuits on a non-empty mirror,
      // so this avoids the HTTP fallback path.
      {
        path: `${BASE}/larpManagerMirrorChars/unrelated01`,
        data: { name: "Someone Else", uuid: "unrelated01", number: 50 },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(result.hasCharacter, false);
      assert.equal(result.htmlLookupAttempted, true);
      // We had 1 uuid but mirror resolved 0 — log records the gap.
      assert.equal(result.htmlLookupMatches, 1);
      assert.equal(
        writes.filter((w) => w.path.startsWith(`${BASE}/characters/`)).length,
        0,
        "no /characters write when the mirror doesn't yet have the uuid"
      );
      const htmlLog = logs.find((l) =>
        /characters-by-email HTML lookup/i.test(l.msg)
      );
      assert.ok(htmlLog, "HTML lookup diagnostic should fire");
      const meta = htmlLog?.meta as
        | { htmlUuidsCount?: number; resolvedFromMirror?: number }
        | undefined;
      assert.equal(meta?.htmlUuidsCount, 1);
      assert.equal(meta?.resolvedFromMirror, 0);
    });
  }
);

test(
  "Task006-v2: Path-0 — empty characterUuids array (organizer staff row) → " +
    "lookup is not attempted, falls straight through to legacy paths",
  async () => {
    const { db, writes } = makeFirestoreStub([
      {
        path: `${BASE}/${CHARS_BY_EMAIL_COL}/${REG_DOC_ID}`,
        data: {
          emailLower: EMAIL,
          lmUserUuid: "usrstff00001",
          characterUuids: [],
        },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(result.hasCharacter, false);
      assert.equal(result.htmlLookupAttempted, false);
      assert.equal(result.htmlLookupMatches, 0);
      assert.equal(writes.length, 0);
      assert.ok(
        !logs.some((l) =>
          /characters-by-email HTML lookup/i.test(l.msg)
        ),
        "no HTML lookup log when characterUuids is empty"
      );
    });
  }
);

test(
  "Task006-v2: Path-0 PII safety — HTML lookup log carries no raw email, " +
    "character name, or LM user uuid",
  async () => {
    const { db } = makeFirestoreStub([
      {
        path: `${BASE}/${CHARS_BY_EMAIL_COL}/${REG_DOC_ID}`,
        data: {
          emailLower: EMAIL,
          lmUserUuid: "usrjef0000ab",
          characterUuids: ["charuuid0001"],
        },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/charuuid0001`,
        data: { name: "Secret Character Name", uuid: "charuuid0001", number: 1 },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      const serialised = JSON.stringify(logs);
      assert.ok(
        !serialised.includes(EMAIL),
        `HTML-path logs must not contain raw email, got: ${serialised}`
      );
      assert.ok(
        !serialised.includes("Secret Character Name"),
        `HTML-path logs must not contain character name, got: ${serialised}`
      );
      assert.ok(
        !serialised.includes("usrjef0000ab"),
        `HTML-path logs must not contain LM user uuid, got: ${serialised}`
      );
    });
  }
);

test(
  "Task006-v2: production-shape regression — organizer with no CSV row but " +
    "a manage/registrations HTML entry mapping their email to a character " +
    "uuid IS resolved (this is the exact crucible failure mode)",
  async () => {
    const ORGANIZER_EMAIL = "organizer-svc@example.test";
    const ORGANIZER_REG_DOC_ID = registrationDocIdForEmail(ORGANIZER_EMAIL);
    const { db, store } = makeFirestoreStub([
      // No registration CSV doc for this email — organizer is absent from
      // the CSV export, exactly like production.
      // Mirror char with NO email field anywhere (real LM crucible shape):
      // only `owner` (display name) and `owner_uuid` (opaque LM id).
      {
        path: `${BASE}/larpManagerMirrorChars/realuuid001`,
        data: {
          name: "Heldrek",
          uuid: "realuuid001",
          number: 1,
          export: {
            number: 1,
            name: "Heldrek",
            uuid: "realuuid001",
            owner: "Jeffrey Brite",
            owner_uuid: "te93m14a7lly",
            // Critically: NO player_email, no email, no user_email — this
            // is what made the first Task-006 fix unable to resolve.
          },
        },
      },
      // The HTML-derived join table HAS the (email → character_uuid) tuple
      // because LM's manage/registrations page exposes it explicitly.
      {
        path: `${BASE}/${CHARS_BY_EMAIL_COL}/${ORGANIZER_REG_DOC_ID}`,
        data: {
          emailLower: ORGANIZER_EMAIL,
          lmUserUuid: "te93m14a7lly",
          characterUuids: ["realuuid001"],
        },
      },
    ]);
    await withCapturedLogs(async () => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        ORGANIZER_EMAIL,
        { isOrganizer: true }
      );
      assert.equal(
        result.hasCharacter,
        true,
        "production fix: HTML-join MUST resolve where email-mirror cannot"
      );
      assert.equal(result.characterCount, 1);
      assert.equal(result.htmlLookupMatches, 1);

      const charDoc = store.get(`${BASE}/characters/realuuid001`);
      assert.ok(charDoc);
      assert.equal(charDoc?.ownerId, UID);
      assert.equal(charDoc?.larpManagerUuid, "realuuid001");
      assert.equal(charDoc?.name, "Heldrek");
    });
  }
);

test(
  "Task006-v2: PRE-fix variant of the production-shape regression — without " +
    "the HTML-join data, the existing email-mirror fallback finds nothing " +
    "(this is the bug as it shipped in commit 25bb7f0)",
  async () => {
    const ORGANIZER_EMAIL = "organizer-svc@example.test";
    const { db, writes } = makeFirestoreStub([
      // Same mirror char with no email field, as captured from production.
      {
        path: `${BASE}/larpManagerMirrorChars/realuuid001`,
        data: {
          name: "Heldrek",
          uuid: "realuuid001",
          number: 1,
          export: {
            number: 1,
            name: "Heldrek",
            uuid: "realuuid001",
            owner: "Jeffrey Brite",
            owner_uuid: "te93m14a7lly",
          },
        },
      },
      // No larpManagerCharactersByEmail doc — simulating "Task 006 v2
      // didn't run / orga_registrations permission not granted".
    ]);
    await withCapturedLogs(async () => {
      const result = await syncPlayerCharactersForUser(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        ORGANIZER_EMAIL,
        { isOrganizer: true }
      );
      assert.equal(
        result.hasCharacter,
        false,
        "pre-fix shape: email-mirror finds nothing because no email is exported"
      );
      assert.equal(result.htmlLookupAttempted, false);
      assert.equal(result.organizerLookupAttempted, true);
      assert.equal(result.organizerLookupMatches, 0);
      assert.equal(
        writes.filter((w) => w.path.startsWith(`${BASE}/characters/`)).length,
        0
      );
    });
  }
);
