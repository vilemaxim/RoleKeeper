import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";

import {
  buildCharacterCreatePageUrl,
  resolveCharactersByNames,
  shortIdForLmCharacter,
  syncPlayerCharactersForUser,
} from "./playerCharacters";
import { registrationDocIdForEmail } from "./registrations";
import { gameEventBase } from "../gameTenant";
import {
  makeFirestoreStub,
  withCapturedLogs,
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
