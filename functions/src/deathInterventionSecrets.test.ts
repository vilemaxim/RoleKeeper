import { test } from "node:test";
import * as assert from "node:assert/strict";
import type { CallableRequest } from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import type * as admin from "firebase-admin";

import * as index from "./index";
import { gameEventBase, type GameTenant } from "./gameTenant";
import { makeFirestoreStub } from "./_testing/firestoreStub";
import {
  runGetDeathInterventionSecrets,
  type DeathInterventionSecretsBody,
} from "./deathInterventionSecrets";

const TENANT: GameTenant = { instanceId: "rk-test.local", eventSlug: "default" };
const BASE = gameEventBase(TENANT);
const MEMBER_UID = "member-uid-1";

function callableRequest(
  body: DeathInterventionSecretsBody,
  uid?: string
): CallableRequest<DeathInterventionSecretsBody> {
  return {
    data: body,
    auth: uid ? { uid } : undefined,
  } as CallableRequest<DeathInterventionSecretsBody>;
}

test("getDeathInterventionSecrets callable is exported for per-event TOTP and QR signing", () => {
  assert.equal(
    "getDeathInterventionSecrets" in index,
    true,
    "getDeathInterventionSecrets must be exported so clients can fetch per-event secrets"
  );
});

test("runGetDeathInterventionSecrets rejects unauthenticated callers", async () => {
  const stub = makeFirestoreStub();
  await assert.rejects(
    () =>
      runGetDeathInterventionSecrets(
        { db: stub.db as unknown as admin.firestore.Firestore },
        callableRequest({ gameId: `${TENANT.instanceId}::${TENANT.eventSlug}` })
      ),
    (err: unknown) => err instanceof HttpsError && err.code === "unauthenticated"
  );
});

test("runGetDeathInterventionSecrets rejects non-members", async () => {
  const stub = makeFirestoreStub();
  await assert.rejects(
    () =>
      runGetDeathInterventionSecrets(
        { db: stub.db as unknown as admin.firestore.Firestore },
        callableRequest(
          { gameId: `${TENANT.instanceId}::${TENANT.eventSlug}` },
          MEMBER_UID
        )
      ),
    (err: unknown) => err instanceof HttpsError && err.code === "permission-denied"
  );
});

test("runGetDeathInterventionSecrets generates and persists secrets on first fetch", async () => {
  const stub = makeFirestoreStub([
    {
      path: `${BASE}/members/${MEMBER_UID}`,
      data: { role: "player" },
    },
  ]);

  const result = await runGetDeathInterventionSecrets(
    { db: stub.db as unknown as admin.firestore.Firestore },
    callableRequest(
      { gameId: `${TENANT.instanceId}::${TENANT.eventSlug}` },
      MEMBER_UID
    )
  );

  assert.ok(result.totpSecret.length >= 16);
  assert.ok(result.qrSigningSecret.length >= 32);

  const config = stub.store.get(`${BASE}/eventSession/config`);
  assert.equal(config?.deathTotpSecret, result.totpSecret);
  assert.equal(config?.deathQrSigningSecret, result.qrSigningSecret);
});

test("runGetDeathInterventionSecrets returns existing secrets without regenerating", async () => {
  const existingTotp = "JBSWY3DPEHPK3PXP";
  const existingQr = "deadbeef".repeat(8);
  const stub = makeFirestoreStub([
    {
      path: `${BASE}/members/${MEMBER_UID}`,
      data: { role: "player" },
    },
    {
      path: `${BASE}/eventSession/config`,
      data: {
        deathTotpSecret: existingTotp,
        deathQrSigningSecret: existingQr,
      },
    },
  ]);

  const result = await runGetDeathInterventionSecrets(
    { db: stub.db as unknown as admin.firestore.Firestore },
    callableRequest(
      { gameId: `${TENANT.instanceId}::${TENANT.eventSlug}` },
      MEMBER_UID
    )
  );

  assert.equal(result.totpSecret, existingTotp);
  assert.equal(result.qrSigningSecret, existingQr);
  assert.equal(stub.writes.length, 0);
});

test("runGetDeathInterventionSecrets rejects missing tenant", async () => {
  const stub = makeFirestoreStub([
    {
      path: `${BASE}/members/${MEMBER_UID}`,
      data: { role: "player" },
    },
  ]);

  await assert.rejects(
    () =>
      runGetDeathInterventionSecrets(
        { db: stub.db as unknown as admin.firestore.Firestore },
        callableRequest({}, MEMBER_UID)
      ),
    (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument"
  );
});
