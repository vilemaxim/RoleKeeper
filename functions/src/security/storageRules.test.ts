/**
 * Task 002: Storage rules ownership enforcement.
 *
 * Pins acceptance criteria from `docs/tasks/ready/002-coder.md`:
 *   - Unauthenticated writes denied on all Storage paths
 *   - Character portrait writes require Firestore-backed ownership (tenant paths)
 *   - Event media writes require staff/owner membership (tenant paths)
 *   - Legacy top-level `characters/` and `events/` paths are denied
 *
 * Requires Firebase emulators (auth, firestore, storage) — started by `scripts/test.sh`.
 */

import { after, before, beforeEach, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";

import {
  createStorageRulesTestEnv,
  seedTenantCharacter,
  seedTenantMember,
  tenantCharacterPortraitPath,
  tenantEventMediaPath,
  uploadBytes,
} from "./storageRulesTestEnv";

const INSTANCE_ID = "lm.example.com";
const EVENT_SLUG = "crucible";
const CHARACTER_ID = "charuuid0001";
const OWNER_UID = "owner-alice";
const STRANGER_UID = "stranger-bob";
const STAFF_UID = "staff-carol";
const PLAYER_UID = "player-dan";

let testEnv: RulesTestEnvironment;

before(async () => {
  testEnv = await createStorageRulesTestEnv();
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

test("unauthenticated write denied on user avatar path", async () => {
  await assertFails(uploadBytes(testEnv, null, "users/someone/avatar.jpg"));
});

test("unauthenticated write denied on tenant character portrait path", async () => {
  await assertFails(
    uploadBytes(
      testEnv,
      null,
      tenantCharacterPortraitPath(INSTANCE_ID, EVENT_SLUG, CHARACTER_ID)
    )
  );
});

test("unauthenticated write denied on tenant event media path", async () => {
  await assertFails(
    uploadBytes(
      testEnv,
      null,
      tenantEventMediaPath(INSTANCE_ID, EVENT_SLUG, "banner.jpg")
    )
  );
});

test("unauthenticated write denied on legacy character path", async () => {
  await assertFails(
    uploadBytes(testEnv, null, `characters/${CHARACTER_ID}/portrait.jpg`)
  );
});

test("unauthenticated write denied on legacy event path", async () => {
  await assertFails(
    uploadBytes(testEnv, null, `events/${EVENT_SLUG}/banner.jpg`)
  );
});

test("authenticated user can write own avatar", async () => {
  await assertSucceeds(
    uploadBytes(testEnv, OWNER_UID, `users/${OWNER_UID}/avatar.jpg`)
  );
});

test("authenticated user cannot write another user's avatar", async () => {
  await assertFails(
    uploadBytes(testEnv, STRANGER_UID, `users/${OWNER_UID}/avatar.jpg`)
  );
});

test("character owner can write tenant-scoped portrait", async () => {
  await seedTenantCharacter(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    characterId: CHARACTER_ID,
    ownerId: OWNER_UID,
  });

  await assertSucceeds(
    uploadBytes(
      testEnv,
      OWNER_UID,
      tenantCharacterPortraitPath(INSTANCE_ID, EVENT_SLUG, CHARACTER_ID)
    )
  );
});

test("random authenticated user cannot write another user's tenant portrait", async () => {
  await seedTenantCharacter(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    characterId: CHARACTER_ID,
    ownerId: OWNER_UID,
  });
  await seedTenantMember(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    uid: STRANGER_UID,
    role: "player",
  });

  await assertFails(
    uploadBytes(
      testEnv,
      STRANGER_UID,
      tenantCharacterPortraitPath(INSTANCE_ID, EVENT_SLUG, CHARACTER_ID)
    )
  );
});

test("staff can write tenant event media", async () => {
  await seedTenantMember(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    uid: STAFF_UID,
    role: "staff",
  });

  await assertSucceeds(
    uploadBytes(
      testEnv,
      STAFF_UID,
      tenantEventMediaPath(INSTANCE_ID, EVENT_SLUG, "banner.jpg")
    )
  );
});

test("owner can write tenant event media", async () => {
  await seedTenantMember(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    uid: OWNER_UID,
    role: "owner",
  });

  await assertSucceeds(
    uploadBytes(
      testEnv,
      OWNER_UID,
      tenantEventMediaPath(INSTANCE_ID, EVENT_SLUG, "schedule.pdf")
    )
  );
});

test("plain player cannot write tenant event media", async () => {
  await seedTenantMember(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    uid: PLAYER_UID,
    role: "player",
  });

  await assertFails(
    uploadBytes(
      testEnv,
      PLAYER_UID,
      tenantEventMediaPath(INSTANCE_ID, EVENT_SLUG, "banner.jpg")
    )
  );
});

test("authenticated user cannot write legacy character portrait path", async () => {
  await seedTenantCharacter(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    characterId: CHARACTER_ID,
    ownerId: OWNER_UID,
  });

  await assertFails(
    uploadBytes(
      testEnv,
      OWNER_UID,
      `characters/${CHARACTER_ID}/portrait.jpg`
    )
  );
});

test("authenticated user cannot write legacy event media path", async () => {
  await seedTenantMember(testEnv, {
    instanceId: INSTANCE_ID,
    eventSlug: EVENT_SLUG,
    uid: STAFF_UID,
    role: "staff",
  });

  await assertFails(
    uploadBytes(testEnv, STAFF_UID, `events/${EVENT_SLUG}/banner.jpg`)
  );
});
