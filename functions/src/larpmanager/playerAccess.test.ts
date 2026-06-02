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
