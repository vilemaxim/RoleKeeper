import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";

import { resolveLarpManagerPlayerAccess } from "./playerAccess";
import { registrationDocIdForEmail } from "./registrations";
import { gameEventBase } from "../gameTenant";
import {
  makeFirestoreStub,
  withCapturedLogs,
  type StubDocSeed,
} from "../_testing/firestoreStub";
import type { LarpManagerSyncConfig } from "./types";

const TENANT = { instanceId: "g1", eventSlug: "evt1" };
const BASE = gameEventBase(TENANT);
const CONFIG: LarpManagerSyncConfig = {
  baseUrl: "https://lm.example",
  eventSlug: "evt1",
  fetchDetails: false,
};
const UID = "user-1";
const EMAIL = "Player@Example.COM";
const EMAIL_LOWER = "player@example.com";
const REG_DOC_ID = registrationDocIdForEmail(EMAIL);

const ORG_META_PATH = `${BASE}/larpManagerOrganizersMeta/summary`;
const REG_META_PATH = `${BASE}/larpManagerRegistrationsMeta/summary`;

function freshTimestampSeed(): StubDocSeed[] {
  const ms = Date.now();
  const ts = { toMillis: () => ms, toDate: () => new Date(ms) };
  // Seed both sync-meta docs with a fresh `lastSyncedAt` so the in-process
  // sync helpers (organizers + registrations) short-circuit on cache without
  // attempting any real HTTP fetch. The actual sync logic is covered by
  // dedicated tests in registrations.test.ts and organizers.test.ts.
  return [
    {
      path: `${BASE}/larpManagerOrganizersMeta/summary`,
      data: { lastSyncedAt: ts, organizerCount: 0, syncRunId: "stub" },
    },
    {
      path: `${BASE}/larpManagerRegistrationsMeta/summary`,
      data: { lastSyncedAt: ts, registrationCount: 1, syncRunId: "stub" },
    },
  ];
}

test(
  "resolveLarpManagerPlayerAccess: no registration doc → " +
    "'complete event registration' message, no characterMessage",
  async () => {
    const { db } = makeFirestoreStub(freshTimestampSeed());
    await withCapturedLogs(async () => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.registered, false);
      assert.equal(r.isOrganizer, false);
      assert.equal(r.hasCharacter, false);
      assert.equal(r.characterMessage, null);
      assert.ok(
        r.message?.includes("complete event registration"),
        `expected registration copy, got ${JSON.stringify(r.message)}`
      );
    });
  }
);

test(
  "resolveLarpManagerPlayerAccess: registered + empty characterNames + " +
    "no existing characters → server returns 'Create a character on LarpManager…' copy",
  async () => {
    const { db } = makeFirestoreStub([
      ...freshTimestampSeed(),
      {
        path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
        data: { emailLower: EMAIL_LOWER, characterNames: [] },
      },
    ]);
    await withCapturedLogs(async () => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.registered, true);
      assert.equal(r.isOrganizer, false);
      assert.equal(r.hasCharacter, false);
      assert.equal(r.message, null, "no top-level message when registered");
      assert.ok(
        r.characterMessage?.startsWith("Create a character on LarpManager"),
        `expected create-character copy, got ${JSON.stringify(r.characterMessage)}`
      );
      assert.ok(
        r.characterMessage?.includes("Check character status"),
        "should be the exact server-side copy (matches task 001 symptom)"
      );
    });
  }
);

test(
  "resolveLarpManagerPlayerAccess: registered + characterNames + matching " +
    "mirror entry → hasCharacter:true, characterMessage null",
  async () => {
    const { db, store } = makeFirestoreStub([
      ...freshTimestampSeed(),
      {
        path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
        data: { emailLower: EMAIL_LOWER, characterNames: ["Alice Hero"] },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-a`,
        data: { name: "Alice Hero", uuid: "uuid-a", number: 1 },
      },
    ]);
    await withCapturedLogs(async () => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.registered, true);
      assert.equal(r.hasCharacter, true);
      assert.equal(r.characterCount, 1);
      assert.equal(r.characterMessage, null);
      assert.ok(
        store.get(`${BASE}/characters/uuid-a`),
        "should have written the character doc to /characters/uuid-a"
      );
    });
  }
);

test(
  "resolveLarpManagerPlayerAccess: registered + characterNames + NO matching " +
    "mirror entry → 'Create a character' copy + diagnostic log fires",
  async () => {
    const { db } = makeFirestoreStub([
      ...freshTimestampSeed(),
      {
        path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
        data: { emailLower: EMAIL_LOWER, characterNames: ["Alice Hero"] },
      },
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-b`,
        data: { name: "Bob Scout", uuid: "uuid-b", number: 2 },
      },
    ]);
    await withCapturedLogs(async (logs) => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.registered, true);
      assert.equal(r.hasCharacter, false);
      assert.ok(
        r.characterMessage?.startsWith("Create a character on LarpManager"),
        "should return the create-character copy on name-format drift"
      );
      assert.ok(
        logs.some((l) =>
          /0\/\d+\s+names?\s+matched\s+mirror\s+export/i.test(l.msg)
        ),
        "should emit the '0/N matched mirror export' diagnostic line"
      );
    });
  }
);

// --- Task 003: degraded-sync behaviour -----------------------------------
//
// These four tests cover the resilience contract: a failure in any of the
// three sync collaborators (organizers, registrations, characters) must not
// reject the callable nor block the others from running. Failed syncs are
// surfaced as `*SyncError` fields on the result, with one `logger.error`
// per failure naming the sync step (no email / character / credential PII).

test(
  "task003: org sync fails + cached organizer doc + cached reg with mirror char " +
    "→ isOrganizer:true, hasCharacter:true, organizerSyncError populated",
  async () => {
    const { db } = makeFirestoreStub(
      [
        ...freshTimestampSeed(),
        // Cached organizer doc for this user — populated by a prior successful sync.
        {
          path: `${BASE}/larpManagerOrganizers/${REG_DOC_ID}`,
          data: { emailLower: EMAIL_LOWER, source: "larpmanager" },
        },
        {
          path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
          data: { emailLower: EMAIL_LOWER, characterNames: ["Alice Hero"] },
        },
        {
          path: `${BASE}/larpManagerMirrorChars/uuid-a`,
          data: { name: "Alice Hero", uuid: "uuid-a", number: 1 },
        },
      ],
      {
        failOnGet: (path) =>
          path === ORG_META_PATH
            ? new Error("LM /manage/roles/ HTTP 500 (simulated)")
            : null,
      }
    );
    await withCapturedLogs(async (logs) => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.isOrganizer, true);
      assert.equal(r.registered, true);
      assert.equal(r.hasCharacter, true);
      assert.equal(r.role, "owner");
      assert.equal(r.registrationSyncError, null);
      assert.equal(r.characterSyncError, null);
      assert.ok(
        r.organizerSyncError && r.organizerSyncError.length > 0,
        `expected organizerSyncError populated, got ${JSON.stringify(r.organizerSyncError)}`
      );
      assert.ok(
        logs.some(
          (l) =>
            l.level === "error" &&
            /organizer sync failed/i.test(l.msg) &&
            (l.meta as { sync?: string } | undefined)?.sync ===
              "syncLarpManagerOrganizers"
        ),
        "should log one logger.error naming syncLarpManagerOrganizers"
      );
    });
  }
);

test(
  "task003: org sync fails + no cached organizer doc + cached reg with matching " +
    "mirror char → isOrganizer:false, registered:true, hasCharacter:true",
  async () => {
    const { db } = makeFirestoreStub(
      [
        ...freshTimestampSeed(),
        {
          path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
          data: { emailLower: EMAIL_LOWER, characterNames: ["Alice Hero"] },
        },
        {
          path: `${BASE}/larpManagerMirrorChars/uuid-a`,
          data: { name: "Alice Hero", uuid: "uuid-a", number: 1 },
        },
      ],
      {
        failOnGet: (path) =>
          path === ORG_META_PATH
            ? new Error("LM /manage/roles/ HTTP 500 (simulated)")
            : null,
      }
    );
    await withCapturedLogs(async () => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.isOrganizer, false);
      assert.equal(r.registered, true);
      assert.equal(r.hasCharacter, true);
      assert.equal(r.characterCount, 1);
      assert.equal(r.role, "player");
      assert.equal(r.registrationSyncError, null);
      assert.equal(r.characterSyncError, null);
      assert.ok(
        r.organizerSyncError && r.organizerSyncError.length > 0,
        "organizerSyncError must be populated"
      );
      assert.equal(r.characterMessage, null);
    });
  }
);

test(
  "task003: BOTH org and registration sync fail + user has a pre-existing " +
    "/characters doc they own → hasCharacter:true via legacy fallback",
  async () => {
    const { db } = makeFirestoreStub(
      [
        ...freshTimestampSeed(),
        // User is "registered" via the cached reg doc (with empty
        // characterNames — exercise the legacy /characters fallback).
        {
          path: `${BASE}/larpManagerRegistrations/${REG_DOC_ID}`,
          data: { emailLower: EMAIL_LOWER, characterNames: [] },
        },
        // Pre-existing character doc owned by this user.
        {
          path: `${BASE}/characters/uuid-legacy`,
          data: { ownerId: UID, isArchived: false, name: "Legacy Char" },
        },
      ],
      {
        failOnGet: (path) => {
          if (path === ORG_META_PATH) {
            return new Error("LM /manage/roles/ HTTP 500 (simulated)");
          }
          if (path === REG_META_PATH) {
            return new Error("LM registrations.zip HTTP 502 (simulated)");
          }
          return null;
        },
      }
    );
    await withCapturedLogs(async (logs) => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.isOrganizer, false);
      assert.equal(r.registered, true, "cached reg doc still grants registered");
      assert.equal(
        r.hasCharacter,
        true,
        "legacy /characters ownerId fallback should apply"
      );
      assert.ok(
        r.organizerSyncError && r.organizerSyncError.length > 0,
        "organizerSyncError populated"
      );
      assert.ok(
        r.registrationSyncError && r.registrationSyncError.length > 0,
        "registrationSyncError populated"
      );
      // The character sync itself runs successfully against the cached
      // registration's empty characterNames + the /characters fallback.
      assert.equal(r.characterSyncError, null);
      assert.equal(
        r.characterMessage,
        null,
        "no create-character copy when the legacy fallback found a character"
      );
      assert.ok(
        logs.filter(
          (l) => l.level === "error" && /sync failed/i.test(l.msg)
        ).length >= 2,
        "should log logger.error for both failed syncs"
      );
    });
  }
);

test(
  "task003: BOTH syncs fail + nothing cached for user → registered:false, " +
    "hasCharacter:false, characterMessage:null, callable does not throw",
  async () => {
    const { db } = makeFirestoreStub([...freshTimestampSeed()], {
      failOnGet: (path) => {
        if (path === ORG_META_PATH) {
          return new Error("LM /manage/roles/ HTTP 500 (simulated)");
        }
        if (path === REG_META_PATH) {
          return new Error("LM registrations.zip HTTP 502 (simulated)");
        }
        return null;
      },
    });
    await withCapturedLogs(async () => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.isOrganizer, false);
      assert.equal(r.registered, false);
      assert.equal(r.hasCharacter, false);
      assert.equal(
        r.characterMessage,
        null,
        "no misleading 'create a character' copy when we don't actually know"
      );
      assert.ok(
        r.organizerSyncError && r.organizerSyncError.length > 0,
        "organizerSyncError populated"
      );
      assert.ok(
        r.registrationSyncError && r.registrationSyncError.length > 0,
        "registrationSyncError populated"
      );
      assert.equal(r.characterSyncError, null);
      assert.ok(
        r.message?.includes("complete event registration"),
        "fall back to the standard 'sign in to LarpManager' copy"
      );
    });
  }
);

// --- Task 006: organizer-with-no-character honesty -------------------------
//
// Before the fix, `playerAccess` short-circuited `hasCharacter = isOrganizer
// || charSync.hasCharacter`, so every organizer was told "you have a
// character" even when /characters had zero docs under their ownerId. The
// Flutter Characters screen (which reads /characters directly) then showed
// the empty state with no actionable message. These tests pin the fix:
// `hasCharacter` reflects reality, and `characterMessage` carries the
// LM-side remediation copy.

test(
  "TASK 006: organizer + bulk mirror has matching player_email → " +
    "isOrganizer:true, hasCharacter:true, characterMessage null",
  async () => {
    const { db, store } = makeFirestoreStub([
      ...freshTimestampSeed(),
      // Cached organizer doc: this user is recognised as an organizer.
      {
        path: `${BASE}/larpManagerOrganizers/${REG_DOC_ID}`,
        data: { emailLower: EMAIL_LOWER, source: "larpmanager" },
      },
      // Organizer is NOT in the registrations CSV (the bug scenario).
      // Mirror has a character whose `export.player_email` matches them.
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
            player_email: EMAIL_LOWER,
          },
        },
      },
    ]);
    await withCapturedLogs(async () => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.isOrganizer, true);
      assert.equal(r.role, "owner");
      assert.equal(r.hasCharacter, true);
      assert.equal(r.characterCount, 1);
      assert.equal(r.characterMessage, null);
      assert.ok(
        store.get(`${BASE}/characters/uuid-cassandra`),
        "organizer fallback should write the character doc"
      );
    });
  }
);

test(
  "TASK 006: organizer + bulk mirror has NO matching email → " +
    "hasCharacter:false (no more isOrganizer-lie) + LM-email-mismatch copy",
  async () => {
    const { db } = makeFirestoreStub([
      ...freshTimestampSeed(),
      {
        path: `${BASE}/larpManagerOrganizers/${REG_DOC_ID}`,
        data: { emailLower: EMAIL_LOWER, source: "larpmanager" },
      },
      // Mirror has chars, but none belong to this organizer.
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
    await withCapturedLogs(async () => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.isOrganizer, true);
      assert.equal(
        r.hasCharacter,
        false,
        "hasCharacter must NOT be short-circuited true for organizers"
      );
      assert.equal(r.characterCount, 0);
      assert.ok(
        r.characterMessage &&
          /LarpManager email/i.test(r.characterMessage) &&
          /sign in to RoleKeeper/i.test(r.characterMessage),
        `expected LM-email-mismatch copy, got ${JSON.stringify(r.characterMessage)}`
      );
    });
  }
);

test(
  "TASK 006: organizer + bulk mirror has MULTIPLE matching chars → " +
    "hasCharacter:false + ambiguity copy (no auto-pick)",
  async () => {
    const { db, writes } = makeFirestoreStub([
      ...freshTimestampSeed(),
      {
        path: `${BASE}/larpManagerOrganizers/${REG_DOC_ID}`,
        data: { emailLower: EMAIL_LOWER, source: "larpmanager" },
      },
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
            player_email: EMAIL_LOWER,
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
            player_email: EMAIL_LOWER,
          },
        },
      },
    ]);
    await withCapturedLogs(async () => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.isOrganizer, true);
      assert.equal(r.hasCharacter, false);
      assert.equal(r.characterCount, 0);
      assert.ok(
        r.characterMessage &&
          /multiple/i.test(r.characterMessage) &&
          /reassign/i.test(r.characterMessage),
        `expected ambiguity copy, got ${JSON.stringify(r.characterMessage)}`
      );
      assert.equal(
        writes.filter((w) => w.path.startsWith(`${BASE}/characters/`)).length,
        0,
        "ambiguous matches must not write any /characters doc"
      );
    });
  }
);

test(
  "TASK 006: organizer + already has a /characters doc → hasCharacter:true, " +
    "characterMessage null (legacy probe still works under the fix)",
  async () => {
    const { db } = makeFirestoreStub([
      ...freshTimestampSeed(),
      {
        path: `${BASE}/larpManagerOrganizers/${REG_DOC_ID}`,
        data: { emailLower: EMAIL_LOWER, source: "larpmanager" },
      },
      // Mirror has no characters for this organizer's email…
      {
        path: `${BASE}/larpManagerMirrorChars/uuid-other`,
        data: {
          number: 1,
          name: "Other",
          uuid: "uuid-other",
          export: {
            number: 1,
            uuid: "uuid-other",
            player_email: "someone-else@example.test",
          },
        },
      },
      // …but a previously-synced character doc already exists for the organizer.
      {
        path: `${BASE}/characters/legacy-org-char`,
        data: { ownerId: UID, isArchived: false, name: "Legacy" },
      },
    ]);
    await withCapturedLogs(async () => {
      const r = await resolveLarpManagerPlayerAccess(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        CONFIG,
        UID,
        EMAIL
      );
      assert.equal(r.isOrganizer, true);
      assert.equal(r.hasCharacter, true, "legacy /characters probe wins");
      assert.equal(r.characterCount, 1);
      assert.equal(r.characterMessage, null);
    });
  }
);
