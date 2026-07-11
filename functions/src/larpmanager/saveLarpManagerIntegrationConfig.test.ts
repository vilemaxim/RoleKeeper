/**
 * Task 005: Server-attest organizerAccessConfigured and LM-verified owner bootstrap.
 *
 * Pins acceptance criteria from `docs/tasks/ready/005-coder.md`:
 *   - M1: only verified credential save sets `organizerAccessConfigured` server-side
 *   - M2: first credential save promotes to owner only when LM confirms organizer status
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, tenantKey, type GameTenant } from "../gameTenant";
import { makeFirestoreStub } from "../_testing/firestoreStub";
import { registrationDocIdForEmail } from "./registrations";
import {
  larpRegistryEventPath,
  resolveCallerOrganizerStatusFromMirror,
  runSaveLarpManagerIntegrationConfig,
  type SaveLarpManagerIntegrationConfigBody,
  type SaveLarpManagerIntegrationConfigDeps,
} from "./saveLarpManagerIntegrationConfig";

const TENANT: GameTenant = { instanceId: "lm.example", eventSlug: "crucible" };
const BASE = gameEventBase(TENANT);
const T_KEY = tenantKey(TENANT);
const PLAYER_UID = "player-dan";
const ORGANIZER_UID = "organizer-alice";
const PLAYER_EMAIL = "dan@example.com";
const ORGANIZER_EMAIL = "alice@example.com";

function memberPath(uid: string): string {
  return `${BASE}/members/${uid}`;
}

function membershipPath(uid: string): string {
  return `users/${uid}/gameMemberships/${T_KEY}`;
}

function registryPath(): string {
  return larpRegistryEventPath(TENANT);
}

function callableRequest(
  body: SaveLarpManagerIntegrationConfigBody,
  uid: string,
  email: string
): CallableRequest<SaveLarpManagerIntegrationConfigBody> {
  return {
    data: body,
    auth: {
      uid,
      token: { email } as never,
    },
  } as unknown as CallableRequest<SaveLarpManagerIntegrationConfigBody>;
}

function depsForStub(
  stub: ReturnType<typeof makeFirestoreStub>
): SaveLarpManagerIntegrationConfigDeps {
  return {
    db: stub.db as unknown as admin.firestore.Firestore,
    getProjectId: () => "test-project",
    upsertSecret: async () => undefined,
    resolveCallerOrganizerStatus: resolveCallerOrganizerStatusFromMirror,
  };
}

function saveBody(
  overrides: Partial<SaveLarpManagerIntegrationConfigBody> = {}
): SaveLarpManagerIntegrationConfigBody {
  return {
    gameId: T_KEY,
    baseUrl: "https://lm.example",
    eventSlug: "crucible",
    loginPath: "/login/",
    username: "svc",
    password: "secret",
    ...overrides,
  };
}

function seedLmOrganizer(
  stub: ReturnType<typeof makeFirestoreStub>,
  email: string
): void {
  const docId = registrationDocIdForEmail(email);
  stub.store.set(`${BASE}/larpManagerOrganizers/${docId}`, {
    emailLower: email.toLowerCase(),
    source: "larpmanager",
    eventRoleNumber: 1,
  });
}

test(
  "Task 005 M2: player first credential save does NOT bootstrap to owner " +
    "when LM has not confirmed organizer status",
  async () => {
    const stub = makeFirestoreStub();
    stub.store.set(memberPath(PLAYER_UID), { role: "player" });
    stub.store.set(membershipPath(PLAYER_UID), { role: "player" });

    const result = await runSaveLarpManagerIntegrationConfig(
      depsForStub(stub),
      callableRequest(saveBody(), PLAYER_UID, PLAYER_EMAIL)
    );

    assert.equal(result.bootstrapOwner, false);
    assert.equal(stub.store.get(memberPath(PLAYER_UID))?.role, "player");
    assert.equal(stub.store.get(membershipPath(PLAYER_UID))?.role, "player");
  }
);

test(
  "Task 005 M2: LM-confirmed organizer first credential save bootstraps to owner",
  async () => {
    const stub = makeFirestoreStub();
    stub.store.set(memberPath(ORGANIZER_UID), { role: "player" });
    stub.store.set(membershipPath(ORGANIZER_UID), { role: "player" });
    seedLmOrganizer(stub, ORGANIZER_EMAIL);

    const result = await runSaveLarpManagerIntegrationConfig(
      depsForStub(stub),
      callableRequest(saveBody(), ORGANIZER_UID, ORGANIZER_EMAIL)
    );

    assert.equal(result.bootstrapOwner, true);
    assert.equal(stub.store.get(memberPath(ORGANIZER_UID))?.role, "owner");
    assert.equal(stub.store.get(membershipPath(ORGANIZER_UID))?.role, "owner");
    assert.equal(
      stub.store.get(registryPath())?.organizerAccessConfigured,
      true,
      "verified save must attest organizerAccessConfigured on larpRegistry"
    );
  }
);

test(
  "Task 005 M1: verified credential save sets organizerAccessConfigured on " +
    "larpRegistry server-side",
  async () => {
    const stub = makeFirestoreStub();
    stub.store.set(memberPath(ORGANIZER_UID), { role: "player" });
    stub.store.set(membershipPath(ORGANIZER_UID), { role: "player" });
    seedLmOrganizer(stub, ORGANIZER_EMAIL);

    await runSaveLarpManagerIntegrationConfig(
      depsForStub(stub),
      callableRequest(saveBody(), ORGANIZER_UID, ORGANIZER_EMAIL)
    );

    const registry = stub.store.get(registryPath());
    assert.ok(registry, "expected larpRegistry doc after verified save");
    assert.equal(registry!.organizerAccessConfigured, true);
    assert.equal(registry!.larpManagerBaseUrl, "https://lm.example");
    assert.equal(registry!.larpManagerEventSlug, "crucible");
  }
);

test(
  "Task 005 M2: rejects bootstrap when caller email is not in LM organizers mirror",
  async () => {
    const stub = makeFirestoreStub();
    stub.store.set(memberPath(PLAYER_UID), { role: "player" });
    stub.store.set(membershipPath(PLAYER_UID), { role: "player" });
    // Deliberately seed a *different* organizer — caller is not listed.
    seedLmOrganizer(stub, ORGANIZER_EMAIL);

    await assert.rejects(
      () =>
        runSaveLarpManagerIntegrationConfig(
          depsForStub(stub),
          callableRequest(saveBody(), PLAYER_UID, PLAYER_EMAIL)
        ),
      (err: unknown) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, "permission-denied");
        return true;
      }
    );

    assert.equal(stub.store.get(memberPath(PLAYER_UID))?.role, "player");
  }
);
