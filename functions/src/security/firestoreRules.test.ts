/**
 * Task 003 / 006: Firestore rules hardening + unit test harness.
 *
 * Pins acceptance criteria from `docs/tasks/ready/003-coder.md` and
 * `docs/tasks/ready/006-coder.md`:
 *   - Top-level `events/{eventId}` denied (legacy removal)
 *   - `games/{instanceId}` field-limited updates (join bootstrap preserved)
 *   - Tenant membership read/write boundaries on members
 *   - `deathInterventionClaims` medic/staff gate + read boundaries
 *   - `larpManagerMirrorChars` read policy (all members)
 *   - `itemTransfers` not readable
 *   - Harness wired into `scripts/test.sh`, CI, and FIREBASE_SETUP.md
 *
 * Requires Firestore emulator on port 8080 — started by `scripts/test.sh`.
 *
 * Run only Firestore rules tests locally (emulators must be up):
 *   cd functions && npm run build && \\
 *     GOOGLE_APPLICATION_CREDENTIALS= FIRESTORE_EMULATOR_HOST=localhost:8080 \\
 *     node --test lib/security/firestoreRules.test.js
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { after, before, beforeEach, test } from "node:test";
import assert from "node:assert/strict";

import {
  assertFails,
  assertSucceeds,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";

import {
  createFirestoreRulesTestEnv,
  seedDeathInterventionClaim,
  seedGameInstance,
  seedItemTransfer,
  seedLarpManagerMirrorChar,
  seedLegacyTopLevelEvent,
  seedTenantMember,
  tenantBase,
} from "./firestoreRulesTestEnv";

const INSTANCE_ID = "lm.example.com";
const EVENT_SLUG = "crucible";
const ACTIVITY_ID = "activity-event-123";
const PLAYER_UID = "player-dan";
const OTHER_PLAYER_UID = "player-eve";
const STAFF_UID = "staff-carol";
const ORGANIZER_UID = "organizer-alice";
const OUTSIDER_UID = "outsider-frank";

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

function memberPath(uid: string): string {
  return `${tenantBase(INSTANCE_ID, EVENT_SLUG)}/members/${uid}`;
}

function mirrorCharPath(characterUuid: string): string {
  return `${tenantBase(INSTANCE_ID, EVENT_SLUG)}/larpManagerMirrorChars/${characterUuid}`;
}

function memberPayload(): Record<string, unknown> {
  return {
    role: "player",
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
  };
}

function claimPayload(medicUid: string): Record<string, unknown> {
  return {
    medicPlayerId: medicUid,
    fallenPlayerId: "fallen-player-uid",
    activityEventId: ACTIVITY_ID,
  };
}

async function seedMember(
  uid: string,
  role: "player" | "staff" | "owner" | "superAdmin" = "player"
): Promise<void> {
  await seedTenantMember(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    uid,
    role,
  });
}

async function seedClaim(
  medicPlayerId: string,
  fallenPlayerId: string
): Promise<void> {
  await seedDeathInterventionClaim(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    activityEventId: ACTIVITY_ID,
    medicPlayerId,
    fallenPlayerId,
  });
}

function authDb(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

// --- H1: legacy top-level events/ ---

test("authenticated user cannot read top-level events collection", async () => {
  await seedLegacyTopLevelEvent(testEnv, "legacy-evt-1", ORGANIZER_UID);

  await assertFails(getDoc(doc(authDb(PLAYER_UID), "events/legacy-evt-1")));
});

test("authenticated user cannot create top-level events document", async () => {
  await assertFails(
    setDoc(doc(authDb(ORGANIZER_UID), "events/new-legacy-evt"), {
      organizerId: ORGANIZER_UID,
      visibility: "public",
      title: "Should not be creatable",
    })
  );
});

// --- H2: games/{instanceId} field-limited updates ---

test("authenticated user cannot mutate arbitrary games instance metadata", async () => {
  await seedGameInstance(testEnv, INSTANCE_ID);

  await assertFails(
    setDoc(
      doc(authDb(PLAYER_UID), gameInstancePath()),
      { compromisedBy: PLAYER_UID },
      { merge: true }
    )
  );
});

test("join bootstrap can create games instance with allowed fields", async () => {
  const now = new Date();

  await assertSucceeds(
    setDoc(doc(authDb(PLAYER_UID), gameInstancePath()), {
      instanceId: INSTANCE_ID,
      larpManagerBaseUrl: `https://${INSTANCE_ID}`,
      createdAt: now,
      updatedAt: now,
    })
  );
});

test("join bootstrap can merge-update games instance with allowed fields", async () => {
  await seedGameInstance(testEnv, INSTANCE_ID);

  await assertSucceeds(
    setDoc(
      doc(authDb(PLAYER_UID), gameInstancePath()),
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
  await seedMember(PLAYER_UID);

  await assertFails(
    setDoc(doc(authDb(PLAYER_UID), deathClaimPath()), claimPayload(PLAYER_UID))
  );
});

test("staff member can create deathInterventionClaims", async () => {
  await seedMember(STAFF_UID, "staff");

  await assertSucceeds(
    setDoc(doc(authDb(STAFF_UID), deathClaimPath()), claimPayload(STAFF_UID))
  );
});

test("fallen player can read their deathInterventionClaim", async () => {
  const fallenUid = "fallen-player-uid";
  await seedMember(fallenUid);
  await seedClaim(STAFF_UID, fallenUid);

  await assertSucceeds(getDoc(doc(authDb(fallenUid), deathClaimPath())));
});

test("medic can read deathInterventionClaim they created", async () => {
  await seedMember(STAFF_UID, "staff");
  await seedClaim(STAFF_UID, "fallen-player-uid");

  await assertSucceeds(getDoc(doc(authDb(STAFF_UID), deathClaimPath())));
});

test("unrelated member cannot read deathInterventionClaim", async () => {
  await seedMember(OTHER_PLAYER_UID);
  await seedClaim(STAFF_UID, "fallen-player-uid");

  await assertFails(getDoc(doc(authDb(OTHER_PLAYER_UID), deathClaimPath())));
});

// --- Task 006: tenant membership read/write boundaries ---

test("player can read their own membership document", async () => {
  await seedMember(PLAYER_UID);

  await assertSucceeds(getDoc(doc(authDb(PLAYER_UID), memberPath(PLAYER_UID))));
});

test("player cannot read another member's membership document", async () => {
  await seedMember(PLAYER_UID);
  await seedMember(OTHER_PLAYER_UID);

  await assertFails(
    getDoc(doc(authDb(PLAYER_UID), memberPath(OTHER_PLAYER_UID)))
  );
});

test("staff can read any member's membership document", async () => {
  await seedMember(STAFF_UID, "staff");
  await seedMember(PLAYER_UID);

  await assertSucceeds(getDoc(doc(authDb(STAFF_UID), memberPath(PLAYER_UID))));
});

test("player can create their own membership as player role", async () => {
  await assertSucceeds(
    setDoc(doc(authDb(PLAYER_UID), memberPath(PLAYER_UID)), memberPayload())
  );
});

test("player cannot create membership document for another user", async () => {
  await assertFails(
    setDoc(doc(authDb(PLAYER_UID), memberPath(OTHER_PLAYER_UID)), memberPayload())
  );
});

test("non-member cannot read tenant membership documents", async () => {
  await seedMember(PLAYER_UID);

  await assertFails(getDoc(doc(authDb(OUTSIDER_UID), memberPath(PLAYER_UID))));
});

// --- Task 006: larpManagerMirrorChars read policy (all members) ---

test("tenant member can read larpManagerMirrorChars", async () => {
  const characterUuid = "mirror-char-001";
  await seedMember(PLAYER_UID);
  await seedLarpManagerMirrorChar(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    characterUuid,
  });

  await assertSucceeds(
    getDoc(doc(authDb(PLAYER_UID), mirrorCharPath(characterUuid)))
  );
});

test("non-member cannot read larpManagerMirrorChars", async () => {
  const characterUuid = "mirror-char-002";
  await seedLarpManagerMirrorChar(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    characterUuid,
  });

  await assertFails(
    getDoc(doc(authDb(OUTSIDER_UID), mirrorCharPath(characterUuid)))
  );
});

test("tenant member cannot write larpManagerMirrorChars", async () => {
  const characterUuid = "mirror-char-003";
  await seedMember(STAFF_UID, "staff");

  await assertFails(
    setDoc(doc(authDb(STAFF_UID), mirrorCharPath(characterUuid)), {
      characterUuid,
      displayName: "Client write attempt",
    })
  );
});

// --- Task 005 M1: larpRegistry organizerAccessConfigured server-only ---

function larpRegistryEventPath(instanceId: string, eventSlug: string): string {
  return `larpRegistry/${instanceId}/events/${eventSlug}`;
}

function larpRegistryCreatePayload(
  instanceId: string,
  eventSlug: string,
  uid: string,
  extra: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    tenantKey: `${instanceId}::${eventSlug}`,
    instanceId,
    eventSlug,
    larpManagerBaseUrl: `https://${instanceId}`,
    larpManagerEventSlug: eventSlug,
    displayName: "Test event",
    createdByUid: uid,
    createdAt: new Date(),
    updatedAt: new Date(),
    ...extra,
  };
}

test(
  "authenticated user cannot create larpRegistry event with client-supplied organizerAccessConfigured:true (Task 005 M1)",
  async () => {
    await assertFails(
      setDoc(
        doc(authDb(PLAYER_UID), larpRegistryEventPath(INSTANCE_ID, EVENT_SLUG)),
        larpRegistryCreatePayload(INSTANCE_ID, EVENT_SLUG, PLAYER_UID, {
          organizerAccessConfigured: true,
        })
      )
    );
  }
);

test(
  "authenticated user can create larpRegistry event without organizerAccessConfigured flag (Task 005 M1)",
  async () => {
    await assertSucceeds(
      setDoc(
        doc(authDb(PLAYER_UID), larpRegistryEventPath(INSTANCE_ID, "new-event")),
        larpRegistryCreatePayload(INSTANCE_ID, "new-event", PLAYER_UID)
      )
    );
  }
);

test(
  "authenticated user cannot update larpRegistry event to set organizerAccessConfigured:true (Task 005 M1)",
  async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .doc(larpRegistryEventPath(INSTANCE_ID, EVENT_SLUG))
        .set(
          larpRegistryCreatePayload(INSTANCE_ID, EVENT_SLUG, PLAYER_UID, {
            organizerAccessConfigured: false,
          })
        );
    });

    await assertFails(
      setDoc(
        doc(authDb(PLAYER_UID), larpRegistryEventPath(INSTANCE_ID, EVENT_SLUG)),
        { organizerAccessConfigured: true },
        { merge: true }
      )
    );
  }
);

// --- M4: itemTransfers read denied ---

test("authenticated user cannot read itemTransfers", async () => {
  await seedItemTransfer(testEnv, "transfer-001");

  await assertFails(getDoc(doc(authDb(PLAYER_UID), "itemTransfers/transfer-001")));
});

// --- Task 006: harness wiring ---

const REPO_ROOT = join(__dirname, "../../..");

test("scripts/test.sh includes a dedicated Firestore rules test step (Task 006)", () => {
  const testSh = readFileSync(join(REPO_ROOT, "scripts/test.sh"), "utf8");
  assert.match(
    testSh,
    /Firestore rules tests/,
    "scripts/test.sh must run Firestore rules tests as an explicit step"
  );
});

test("CI workflow runs Firestore rules tests on PR (Task 006)", () => {
  const ci = readFileSync(join(REPO_ROOT, ".github/workflows/ci.yml"), "utf8");
  assert.match(
    ci,
    /firestoreRules\.test/,
    "ci.yml must invoke firestoreRules.test explicitly"
  );
});

test("FIREBASE_SETUP.md documents how to run Firestore rules tests locally (Task 006)", () => {
  const doc = readFileSync(join(REPO_ROOT, "FIREBASE_SETUP.md"), "utf8");
  assert.match(
    doc,
    /firestoreRules\.test/,
    "FIREBASE_SETUP.md must document the local firestoreRules.test command"
  );
});
