/**
 * Task 003: Firestore rules hardening.
 *
 * Pins acceptance criteria from `docs/tasks/ready/003-coder.md`:
 *   - Top-level `events/{eventId}` denied (legacy removal)
 *   - `games/{instanceId}` field-limited updates (join bootstrap preserved)
 *   - `deathInterventionClaims` create requires staff or above
 *   - `itemTransfers` not readable
 *
 * Requires Firestore emulator on port 8080 — started by `scripts/test.sh`.
 */

import { after, before, beforeEach, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";

import {
  createFirestoreRulesTestEnv,
  seedGameInstance,
  seedItemTransfer,
  seedLegacyTopLevelEvent,
  seedTenantMember,
  tenantBase,
} from "./firestoreRulesTestEnv";

const INSTANCE_ID = "lm.example.com";
const EVENT_SLUG = "crucible";
const ACTIVITY_ID = "activity-event-123";
const PLAYER_UID = "player-dan";
const STAFF_UID = "staff-carol";
const ORGANIZER_UID = "organizer-alice";

let testEnv: RulesTestEnvironment;

before(async () => {
  testEnv = await createFirestoreRulesTestEnv();
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

function gameInstancePath(): string {
  return `games/${INSTANCE_ID}`;
}

function deathClaimPath(): string {
  return `${tenantBase(INSTANCE_ID, EVENT_SLUG)}/deathInterventionClaims/${ACTIVITY_ID}`;
}

function claimPayload(medicUid: string): Record<string, unknown> {
  return {
    medicPlayerId: medicUid,
    fallenPlayerId: "fallen-player-uid",
    activityEventId: ACTIVITY_ID,
  };
}

// --- H1: legacy top-level events/ ---

test("authenticated user cannot read top-level events collection", async () => {
  await seedLegacyTopLevelEvent(testEnv, "legacy-evt-1", ORGANIZER_UID);

  const db = testEnv.authenticatedContext(PLAYER_UID).firestore();
  await assertFails(getDoc(doc(db, "events/legacy-evt-1")));
});

test("authenticated user cannot create top-level events document", async () => {
  const db = testEnv.authenticatedContext(ORGANIZER_UID).firestore();
  await assertFails(
    setDoc(doc(db, "events/new-legacy-evt"), {
      organizerId: ORGANIZER_UID,
      visibility: "public",
      title: "Should not be creatable",
    })
  );
});

// --- H2: games/{instanceId} field-limited updates ---

test("authenticated user cannot mutate arbitrary games instance metadata", async () => {
  await seedGameInstance(testEnv, INSTANCE_ID);

  const db = testEnv.authenticatedContext(PLAYER_UID).firestore();
  await assertFails(
    setDoc(
      doc(db, gameInstancePath()),
      { compromisedBy: PLAYER_UID },
      { merge: true }
    )
  );
});

test("join bootstrap can create games instance with allowed fields", async () => {
  const db = testEnv.authenticatedContext(PLAYER_UID).firestore();
  const now = new Date();

  await assertSucceeds(
    setDoc(doc(db, gameInstancePath()), {
      instanceId: INSTANCE_ID,
      larpManagerBaseUrl: `https://${INSTANCE_ID}`,
      createdAt: now,
      updatedAt: now,
    })
  );
});

test("join bootstrap can merge-update games instance with allowed fields", async () => {
  await seedGameInstance(testEnv, INSTANCE_ID);

  const db = testEnv.authenticatedContext(PLAYER_UID).firestore();
  await assertSucceeds(
    setDoc(
      doc(db, gameInstancePath()),
      {
        instanceId: INSTANCE_ID,
        larpManagerBaseUrl: "https://updated.example.com",
        updatedAt: new Date(),
      },
      { merge: true }
    )
  );
});

// --- H4: deathInterventionClaims staff gate ---

test("plain player cannot create deathInterventionClaims", async () => {
  await seedTenantMember(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    uid: PLAYER_UID,
    role: "player",
  });

  const db = testEnv.authenticatedContext(PLAYER_UID).firestore();
  await assertFails(
    setDoc(doc(db, deathClaimPath()), claimPayload(PLAYER_UID))
  );
});

test("staff member can create deathInterventionClaims", async () => {
  await seedTenantMember(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    uid: STAFF_UID,
    role: "staff",
  });

  const db = testEnv.authenticatedContext(STAFF_UID).firestore();
  await assertSucceeds(
    setDoc(doc(db, deathClaimPath()), claimPayload(STAFF_UID))
  );
});

// --- M4: itemTransfers read denied ---

test("authenticated user cannot read itemTransfers", async () => {
  await seedItemTransfer(testEnv, "transfer-001");

  const db = testEnv.authenticatedContext(PLAYER_UID).firestore();
  await assertFails(getDoc(doc(db, "itemTransfers/transfer-001")));
});
