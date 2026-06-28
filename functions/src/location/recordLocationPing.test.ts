/**
 * Unit tests for Task 005 `recordLocationPing` callable body.
 *
 * Pins requirements from `docs/tasks/ready/005-coder.md`:
 *   - Happy path writes ping with presenceState, inGame, location.source
 *   - Accepts out_of_game opted-in players (does not reject on presence)
 *   - Rejects: unauthenticated, non-member, tracking disabled, event not live,
 *     not opted in, invalid location
 *
 * Task 007 additions (ADR 002 hot path):
 *   - Batch-writes ping + members/{uid}.lastLocation snapshot
 *   - Slim ping payloads omit redundant tenant fields
 *   - lastLocation not overwritten when existing timestamp is newer
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, type GameTenant } from "../gameTenant";
import { makeFirestoreStub } from "../_testing/firestoreStub";
import {
  runRecordLocationPing,
  type RecordLocationPingBody,
  type RecordLocationPingDeps,
} from "./recordLocationPing";

const TENANT: GameTenant = { instanceId: "g1", eventSlug: "crucible" };
const BASE = gameEventBase(TENANT);
const UID = "player-alpha";

const VALID_LOCATION = {
  latitude: 51.5074,
  longitude: -0.1278,
  accuracy: 12.5,
};

const PING_TIME = new Date("2026-06-27T12:00:00.000Z");

function ts(d: Date): admin.firestore.Timestamp {
  return { toDate: () => d } as admin.firestore.Timestamp;
}

function memberPath(uid: string): string {
  return `${BASE}/members/${uid}`;
}

function rulesPath(): string {
  return `${BASE}/rules/locationTracking`;
}

function sessionPath(): string {
  return `${BASE}/eventSession/config`;
}

function pingCollectionPrefix(): string {
  return `${BASE}/locationPings`;
}

function callableRequest(
  body: RecordLocationPingBody,
  uid?: string
): CallableRequest<RecordLocationPingBody> {
  return {
    data: body,
    auth: uid ? { uid, token: {} as never } : undefined,
  } as CallableRequest<RecordLocationPingBody>;
}

function depsForStub(
  stub: ReturnType<typeof makeFirestoreStub>,
  now?: admin.firestore.Timestamp
): RecordLocationPingDeps {
  return {
    db: stub.db as unknown as admin.firestore.Firestore,
    now: now ? () => now : () => ts(PING_TIME),
  };
}

function seedHappyPath(
  stub: ReturnType<typeof makeFirestoreStub>,
  opts: {
    locationOptIn?: boolean;
    presenceState?: string;
    trackingEnabled?: boolean;
    isLive?: boolean;
  } = {}
) {
  const {
    locationOptIn = true,
    presenceState = "in_game",
    trackingEnabled = true,
    isLive = true,
  } = opts;
  stub.store.set(memberPath(UID), {
    role: "player",
    locationOptIn,
    presenceState,
  });
  stub.store.set(rulesPath(), { enabled: trackingEnabled, pingIntervalSeconds: 60 });
  stub.store.set(sessionPath(), { isLive });
}

test("happy path batch-writes ping and member lastLocation snapshot", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);

  const result = await runRecordLocationPing(
    depsForStub(stub),
    callableRequest(
      {
        gameId: "g1::crucible",
        location: VALID_LOCATION,
        characterId: "char000000001",
      },
      UID
    )
  );

  assert.ok(result.pingId);
  const pingWrite = stub.writes.find((w) =>
    w.path.startsWith(`${pingCollectionPrefix()}/`)
  );
  assert.ok(pingWrite, "expected a locationPings write");
  assert.equal(pingWrite!.data.playerId, UID);
  assert.equal(pingWrite!.data.presenceState, "in_game");
  assert.equal(pingWrite!.data.inGame, true);
  assert.equal(pingWrite!.data.characterId, "char000000001");
  assert.equal("gameId" in pingWrite!.data, false);
  assert.equal("tenantKey" in pingWrite!.data, false);
  assert.equal("instanceId" in pingWrite!.data, false);
  assert.equal("eventSlug" in pingWrite!.data, false);
  const loc = pingWrite!.data.location as Record<string, unknown>;
  assert.equal(loc.latitude, VALID_LOCATION.latitude);
  assert.equal(loc.longitude, VALID_LOCATION.longitude);
  assert.equal(loc.source, "gps");
  assert.ok(pingWrite!.data.timestamp);

  const memberWrite = stub.writes.find((w) => w.path === memberPath(UID));
  assert.ok(memberWrite, "expected a members/{uid} lastLocation write");
  const lastLocation = memberWrite!.data.lastLocation as Record<string, unknown>;
  assert.equal(lastLocation.latitude, VALID_LOCATION.latitude);
  assert.equal(lastLocation.longitude, VALID_LOCATION.longitude);
  assert.equal(lastLocation.accuracy, VALID_LOCATION.accuracy);
  assert.equal(lastLocation.source, "gps");
  assert.equal(lastLocation.presenceState, "in_game");
  assert.equal(lastLocation.inGame, true);
  assert.ok(lastLocation.timestamp);
});

test("accepts out_of_game opted-in player and sets inGame false", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub, { presenceState: "out_of_game" });

  await runRecordLocationPing(
    depsForStub(stub),
    callableRequest({ gameId: "g1::crucible", location: VALID_LOCATION }, UID)
  );

  const pingWrite = stub.writes.find((w) =>
    w.path.startsWith(`${pingCollectionPrefix()}/`)
  );
  assert.ok(pingWrite);
  assert.equal(pingWrite!.data.presenceState, "out_of_game");
  assert.equal(pingWrite!.data.inGame, false);

  const member = stub.store.get(memberPath(UID));
  const lastLocation = member?.lastLocation as Record<string, unknown>;
  assert.equal(lastLocation.presenceState, "out_of_game");
  assert.equal(lastLocation.inGame, false);
});

test("lastLocation includes altitude when provided in location payload", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);

  await runRecordLocationPing(
    depsForStub(stub),
    callableRequest(
      {
        gameId: "g1::crucible",
        location: { ...VALID_LOCATION, altitude: 42.5 },
      },
      UID
    )
  );

  const member = stub.store.get(memberPath(UID));
  const lastLocation = member?.lastLocation as Record<string, unknown>;
  assert.equal(lastLocation.altitude, 42.5);
});

test("does not overwrite lastLocation when existing timestamp is newer", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);
  const newerTime = new Date("2026-06-27T13:00:00.000Z");
  stub.store.set(memberPath(UID), {
    role: "player",
    locationOptIn: true,
    presenceState: "in_game",
    lastLocation: {
      latitude: 40.0,
      longitude: -70.0,
      source: "gps",
      timestamp: ts(newerTime),
      presenceState: "in_game",
      inGame: true,
    },
  });

  await runRecordLocationPing(
    depsForStub(stub, ts(PING_TIME)),
    callableRequest({ gameId: "g1::crucible", location: VALID_LOCATION }, UID)
  );

  assert.ok(
    stub.writes.some((w) => w.path.startsWith(`${pingCollectionPrefix()}/`)),
    "ping should still be appended to cold trail"
  );

  const lastLocationMemberWrites = stub.writes.filter(
    (w) => w.path === memberPath(UID) && w.data.lastLocation !== undefined
  );
  assert.equal(
    lastLocationMemberWrites.length,
    0,
    "lastLocation must not be overwritten when existing timestamp is newer"
  );

  const member = stub.store.get(memberPath(UID));
  const lastLocation = member?.lastLocation as Record<string, unknown>;
  assert.equal(lastLocation.latitude, 40.0);
  assert.equal(lastLocation.longitude, -70.0);
  assert.equal(
    (lastLocation.timestamp as admin.firestore.Timestamp).toDate().getTime(),
    newerTime.getTime()
  );
});

test("rejects unauthenticated callers", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);

  await assert.rejects(
    () =>
      runRecordLocationPing(
        depsForStub(stub),
        callableRequest({ gameId: "g1::crucible", location: VALID_LOCATION })
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );
  assert.equal(stub.writes.length, 0);
});

test("rejects non-members", async () => {
  const stub = makeFirestoreStub();
  stub.store.set(rulesPath(), { enabled: true });
  stub.store.set(sessionPath(), { isLive: true });

  await assert.rejects(
    () =>
      runRecordLocationPing(
        depsForStub(stub),
        callableRequest({ gameId: "g1::crucible", location: VALID_LOCATION }, UID)
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
  assert.equal(stub.writes.length, 0);
});

test("rejects when location tracking is disabled", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub, { trackingEnabled: false });

  await assert.rejects(
    () =>
      runRecordLocationPing(
        depsForStub(stub),
        callableRequest({ gameId: "g1::crucible", location: VALID_LOCATION }, UID)
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );
  assert.equal(stub.writes.length, 0);
});

test("rejects when event is not live", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub, { isLive: false });

  await assert.rejects(
    () =>
      runRecordLocationPing(
        depsForStub(stub),
        callableRequest({ gameId: "g1::crucible", location: VALID_LOCATION }, UID)
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );
  assert.equal(stub.writes.length, 0);
});

test("rejects when player has not opted in", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub, { locationOptIn: false });

  await assert.rejects(
    () =>
      runRecordLocationPing(
        depsForStub(stub),
        callableRequest({ gameId: "g1::crucible", location: VALID_LOCATION }, UID)
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );
  assert.equal(stub.writes.length, 0);
});

test("rejects invalid or missing location", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);

  await assert.rejects(
    () =>
      runRecordLocationPing(
        depsForStub(stub),
        callableRequest({ gameId: "g1::crucible", location: { latitude: 1 } }, UID)
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );
  assert.equal(stub.writes.length, 0);
});
