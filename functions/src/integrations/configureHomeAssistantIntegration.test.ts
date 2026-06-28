import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, type GameTenant } from "../gameTenant";
import { makeFirestoreStub } from "../_testing/firestoreStub";
import { hashApiKey, verifyApiKey } from "./apiKey";
import {
  runConfigureHomeAssistantIntegration,
  type ConfigureHomeAssistantBody,
  type ConfigureHomeAssistantDeps,
} from "./configureHomeAssistantIntegration";

const TENANT: GameTenant = { instanceId: "g1", eventSlug: "crucible" };
const BASE = gameEventBase(TENANT);
const STAFF_UID = "staff-one";

function configPath(): string {
  return `${BASE}/integrations/homeAssistant`;
}

function memberPath(uid: string): string {
  return `${BASE}/members/${uid}`;
}

function callableRequest(
  body: ConfigureHomeAssistantBody,
  uid?: string
): CallableRequest<ConfigureHomeAssistantBody> {
  return {
    data: body,
    auth: uid ? { uid, token: {} as never } : undefined,
  } as CallableRequest<ConfigureHomeAssistantBody>;
}

function depsForStub(
  stub: ReturnType<typeof makeFirestoreStub>
): ConfigureHomeAssistantDeps {
  return { db: stub.db as unknown as admin.firestore.Firestore };
}

test("staff enabling integration generates api key and stores hash only", async () => {
  const stub = makeFirestoreStub();
  stub.store.set(memberPath(STAFF_UID), { role: "staff" });

  const result = await runConfigureHomeAssistantIntegration(
    depsForStub(stub),
    callableRequest(
      { gameId: "g1::crucible", enabled: true, regenerateKey: true },
      STAFF_UID
    )
  );

  assert.ok(result.apiKey);
  const write = stub.writes.find((w) => w.path === configPath());
  assert.ok(write);
  assert.equal(write!.data.enabled, true);
  assert.equal(typeof write!.data.apiKeyHash, "string");
  assert.equal(
    verifyApiKey(result.apiKey!, write!.data.apiKeyHash as string),
    true
  );
});

test("rejects players", async () => {
  const stub = makeFirestoreStub();
  stub.store.set(memberPath("player"), { role: "player" });

  await assert.rejects(
    () =>
      runConfigureHomeAssistantIntegration(
        depsForStub(stub),
        callableRequest({ gameId: "g1::crucible", enabled: true }, "player")
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("regenerate replaces stored hash", async () => {
  const stub = makeFirestoreStub();
  stub.store.set(memberPath(STAFF_UID), { role: "owner" });
  stub.store.set(configPath(), {
    enabled: true,
    apiKeyHash: hashApiKey("old-key"),
  });

  const result = await runConfigureHomeAssistantIntegration(
    depsForStub(stub),
    callableRequest(
      { gameId: "g1::crucible", enabled: true, regenerateKey: true },
      STAFF_UID
    )
  );

  assert.ok(result.apiKey);
  const write = stub.writes.at(-1);
  assert.ok(write);
  assert.notEqual(write!.data.apiKeyHash, hashApiKey("old-key"));
});
