import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";

// Must match `.firebaserc` default project so Storage cross-service
// firestore.get() lookups hit the same emulator namespace.
export const STORAGE_RULES_PROJECT_ID = "rolekeeper-7ddcc";

const REPO_ROOT = join(__dirname, "../../..");

export function storageBucketUrl(): string {
  return `gs://${STORAGE_RULES_PROJECT_ID}.appspot.com`;
}

export function tenantBase(instanceId: string, eventSlug: string): string {
  return `games/${instanceId}/events/${eventSlug}`;
}

export function tenantCharacterPortraitPath(
  instanceId: string,
  eventSlug: string,
  characterId: string
): string {
  return `${tenantBase(instanceId, eventSlug)}/characters/${characterId}/portrait.jpg`;
}

export function tenantEventMediaPath(
  instanceId: string,
  eventSlug: string,
  fileName: string
): string {
  return `${tenantBase(instanceId, eventSlug)}/media/${fileName}`;
}

export async function createStorageRulesTestEnv(): Promise<RulesTestEnvironment> {
  return initializeTestEnvironment({
    projectId: STORAGE_RULES_PROJECT_ID,
    firestore: {
      rules: readFileSync(join(REPO_ROOT, "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
    storage: {
      rules: readFileSync(join(REPO_ROOT, "storage.rules"), "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });
}

export async function seedTenantCharacter(
  testEnv: RulesTestEnvironment,
  opts: {
    instanceId: string;
    eventSlug: string;
    characterId: string;
    ownerId: string;
  }
): Promise<void> {
  const { instanceId, eventSlug, characterId, ownerId } = opts;
  const base = tenantBase(instanceId, eventSlug);

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`${base}/characters/${characterId}`).set({ ownerId });
    await db.doc(`${base}/members/${ownerId}`).set({
      role: "player",
      instanceId,
      eventSlug,
    });
  });
}

export async function seedTenantMember(
  testEnv: RulesTestEnvironment,
  opts: {
    instanceId: string;
    eventSlug: string;
    uid: string;
    role: "player" | "staff" | "owner" | "superAdmin";
  }
): Promise<void> {
  const { instanceId, eventSlug, uid, role } = opts;

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .doc(`${tenantBase(instanceId, eventSlug)}/members/${uid}`)
      .set({
        role,
        instanceId,
        eventSlug,
      });
  });
}

export function uploadBytes(
  testEnv: RulesTestEnvironment,
  uid: string | null,
  objectPath: string
): Promise<void> {
  const ctx =
    uid === null
      ? testEnv.unauthenticatedContext()
      : testEnv.authenticatedContext(uid);
  const storage = ctx.storage(storageBucketUrl());
  return storage
    .ref(objectPath)
    .put(Buffer.from("rules-test-payload"))
    .then(() => undefined);
}
