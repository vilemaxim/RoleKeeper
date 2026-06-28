/**
 * Unit tests for Task 006 `getLatestPlayerLocations` callable body.
 *
 * Pins requirements from `docs/tasks/ready/006-coder.md`:
 *   - Valid API key returns latest positions for opted-in players with recent pings
 *   - OOG players included when they have recent pings
 *   - Invalid key, disabled integration, and missing tenant all return permission-denied
 *   - Empty result when no recent pings
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, type GameTenant } from "../gameTenant";
import { makeFirestoreStub } from "../_testing/firestoreStub";
import { hashApiKey } from "./apiKey";
import {
  runGetLatestPlayerLocations,
  type GetLatestPlayerLocationsBody,
  type GetLatestPlayerLocationsDeps,
} from "./getLatestPlayerLocations";

const TENANT: GameTenant = { instanceId: "g1", eventSlug: "crucible" };
const BASE = gameEventBase(TENANT);
const API_KEY = "ha-test-key-001";
const API_KEY_HASH = hashApiKey(API_KEY);

const NOW = new Date("2026-06-27T14:00:00.000Z");
const RECENT = new Date("2026-06-27T13:50:00.000Z");
const STALE = new Date("2026-06-27T13:30:00.000Z");

function ts(d: Date): admin.firestore.Timestamp {
  return { toDate: () => d } as admin.firestore.Timestamp;
}

function integrationPath(): string {
  return `${BASE}/integrations/homeAssistant`;
}

function memberPath(uid: string): string {
  return `${BASE}/members/${uid}`;
}

function pingPath(id: string): string {
  return `${BASE}/locationPings/${id}`;
}

function callableRequest(
  body: GetLatestPlayerLocationsBody
): CallableRequest<GetLatestPlayerLocationsBody> {
  return { data: body } as CallableRequest<GetLatestPlayerLocationsBody>;
}

function depsForStub(
  stub: ReturnType<typeof makeFirestoreStub>
): GetLatestPlayerLocationsDeps {
  return {
    db: stub.db as unknown as admin.firestore.Firestore,
    now: () => ts(NOW),
  };
}

function seedIntegration(
  stub: ReturnType<typeof makeFirestoreStub>,
  opts: { enabled?: boolean; apiKeyHash?: string } = {}
) {
  const { enabled = true, apiKeyHash = API_KEY_HASH } = opts;
  stub.store.set(integrationPath(), {
    enabled,
    apiKeyHash,
    createdAt: ts(NOW),
    createdBy: "owner-uid",
  });
}

function seedMember(
  stub: ReturnType<typeof makeFirestoreStub>,
  uid: string,
  opts: { locationOptIn?: boolean; presenceState?: string } = {}
) {
  const { locationOptIn = true, presenceState = "in_game" } = opts;
  stub.store.set(memberPath(uid), {
    role: "player",
    locationOptIn,
    presenceState,
  });
}

function seedPing(
  stub: ReturnType<typeof makeFirestoreStub>,
  id: string,
  playerId: string,
  opts: {
    at?: Date;
    presenceState?: string;
    latitude?: number;
    longitude?: number;
    accuracy?: number;
  } = {}
) {
  const {
    at = RECENT,
    presenceState = "in_game",
    latitude = 51.5,
    longitude = -0.12,
    accuracy = 10,
  } = opts;
  const inGame = presenceState === "in_game";
  stub.store.set(pingPath(id), {
    playerId,
    presenceState,
    inGame,
    timestamp: ts(at),
    location: { latitude, longitude, accuracy, source: "gps" },
  });
}

test("returns latest positions for opted-in players with recent pings", async () => {
  const stub = makeFirestoreStub();
  seedIntegration(stub);
  seedMember(stub, "player-a");
  seedMember(stub, "player-b", { locationOptIn: false });
  seedPing(stub, "ping-a-old", "player-a", {
    at: new Date("2026-06-27T13:45:00.000Z"),
    latitude: 51.1,
    longitude: -0.11,
  });
  seedPing(stub, "ping-a-new", "player-a", {
    at: RECENT,
    latitude: 51.5074,
    longitude: -0.1278,
    accuracy: 8,
  });
  seedPing(stub, "ping-b", "player-b", { at: RECENT });

  const result = await runGetLatestPlayerLocations(
    depsForStub(stub),
    callableRequest({ gameId: "g1::crucible", apiKey: API_KEY })
  );

  assert.equal(result.players.length, 1);
  const row = result.players[0];
  assert.equal(row.playerId, "player-a");
  assert.equal(row.latitude, 51.5074);
  assert.equal(row.longitude, -0.1278);
  assert.equal(row.accuracy, 8);
  assert.equal(row.presenceState, "in_game");
  assert.equal(row.inGame, true);
  assert.ok(row.timestamp);
});

test("includes out_of_game players with recent pings", async () => {
  const stub = makeFirestoreStub();
  seedIntegration(stub);
  seedMember(stub, "player-oog", { presenceState: "out_of_game" });
  seedPing(stub, "ping-oog", "player-oog", {
    at: RECENT,
    presenceState: "out_of_game",
  });

  const result = await runGetLatestPlayerLocations(
    depsForStub(stub),
    callableRequest({ gameId: "g1::crucible", apiKey: API_KEY })
  );

  assert.equal(result.players.length, 1);
  assert.equal(result.players[0].presenceState, "out_of_game");
  assert.equal(result.players[0].inGame, false);
});

test("returns empty array when no opted-in players have recent pings", async () => {
  const stub = makeFirestoreStub();
  seedIntegration(stub);
  seedMember(stub, "player-a");
  seedPing(stub, "ping-stale", "player-a", { at: STALE });

  const result = await runGetLatestPlayerLocations(
    depsForStub(stub),
    callableRequest({ gameId: "g1::crucible", apiKey: API_KEY })
  );

  assert.deepEqual(result.players, []);
});

test("rejects invalid API key without leaking tenant existence", async () => {
  const stub = makeFirestoreStub();
  seedIntegration(stub);

  await assert.rejects(
    () =>
      runGetLatestPlayerLocations(
        depsForStub(stub),
        callableRequest({ gameId: "g1::crucible", apiKey: "wrong-key" })
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("rejects when integration is disabled", async () => {
  const stub = makeFirestoreStub();
  seedIntegration(stub, { enabled: false });
  seedMember(stub, "player-a");
  seedPing(stub, "ping-a", "player-a", { at: RECENT });

  await assert.rejects(
    () =>
      runGetLatestPlayerLocations(
        depsForStub(stub),
        callableRequest({ gameId: "g1::crucible", apiKey: API_KEY })
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("rejects unknown tenant with same error as invalid key", async () => {
  const stub = makeFirestoreStub();

  await assert.rejects(
    () =>
      runGetLatestPlayerLocations(
        depsForStub(stub),
        callableRequest({ gameId: "missing::event", apiKey: API_KEY })
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("rejects missing apiKey", async () => {
  const stub = makeFirestoreStub();
  seedIntegration(stub);

  await assert.rejects(
    () =>
      runGetLatestPlayerLocations(
        depsForStub(stub),
        callableRequest({ gameId: "g1::crucible" })
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});
