import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";

import {
  seedTenantMember,
  tenantBase,
} from "./storageRulesTestEnv";

export { seedTenantMember, tenantBase };

const REPO_ROOT = join(__dirname, "../../..");

/** Separate emulator namespace from Storage rules tests (parallel-safe). */
export const FIRESTORE_RULES_PROJECT_ID = "rolekeeper-firestore-rules-test";

export async function createFirestoreRulesTestEnv(): Promise<RulesTestEnvironment> {
  return initializeTestEnvironment({
    projectId: FIRESTORE_RULES_PROJECT_ID,
    firestore: {
      rules: readFileSync(join(REPO_ROOT, "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
}

export async function seedGameInstance(
  testEnv: RulesTestEnvironment,
  instanceId: string,
  data: Record<string, unknown> = {}
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .doc(`games/${instanceId}`)
      .set({
        instanceId,
        larpManagerBaseUrl: `https://${instanceId}`,
        createdAt: new Date(),
        updatedAt: new Date(),
        ...data,
      });
  });
}

export async function seedLegacyTopLevelEvent(
  testEnv: RulesTestEnvironment,
  eventId: string,
  organizerId: string
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`events/${eventId}`).set({
      organizerId,
      visibility: "public",
      title: "Legacy event",
    });
  });
}

export async function seedItemTransfer(
  testEnv: RulesTestEnvironment,
  transferId: string
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`itemTransfers/${transferId}`).set({
      fromCharacterId: "char-a",
      toCharacterId: "char-b",
      itemId: "item-1",
    });
  });
}

export async function seedLarpManagerMirrorChar(
  testEnv: RulesTestEnvironment,
  opts: {
    instanceId: string;
    eventSlug: string;
    characterUuid: string;
    displayName?: string;
  }
): Promise<void> {
  const { instanceId, eventSlug, characterUuid, displayName = "Mirror Char" } =
    opts;

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .doc(
        `${tenantBase(instanceId, eventSlug)}/larpManagerMirrorChars/${characterUuid}`
      )
      .set({
        characterUuid,
        displayName,
        syncedAt: new Date(),
      });
  });
}

export async function seedDeathInterventionClaim(
  testEnv: RulesTestEnvironment,
  opts: {
    instanceId: string;
    eventSlug: string;
    activityEventId: string;
    medicPlayerId: string;
    fallenPlayerId: string;
  }
): Promise<void> {
  const {
    instanceId,
    eventSlug,
    activityEventId,
    medicPlayerId,
    fallenPlayerId,
  } = opts;

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .doc(
        `${tenantBase(instanceId, eventSlug)}/deathInterventionClaims/${activityEventId}`
      )
      .set({
        activityEventId,
        medicPlayerId,
        fallenPlayerId,
      });
  });
}
