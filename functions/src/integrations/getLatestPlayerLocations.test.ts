/**
 * Unit tests for Task 006 `getLatestPlayerLocations` callable body.
 *
 * Pins requirements from `docs/tasks/ready/006-coder.md`:
 *   - Valid API key returns latest positions for opted-in players with recent pings
 *   - OOG players included when they have recent pings
 *   - Invalid key, disabled integration, and missing tenant all return permission-denied
 *   - Empty result when no recent pings
 *
 * Task 007 additions (ADR 002 hot path):
 *   - Reads opted-in members only; does not query locationPings
 *   - Uses members/{uid}.lastLocation with RECENT_PING_WINDOW_MS filter
 *   - Omits members without lastLocation or with stale lastLocation
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

function pingCollectionPath(): string {
  return `${BASE}/locationPings`;
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

function seedMemberWithLastLocation(
  stub: ReturnType<typeof makeFirestoreStub>,
  uid: string,
  opts: {
    locationOptIn?: boolean;
    presenceState?: string;
    at?: Date;
    latitude?: number;
    longitude?: number;
    accuracy?: number;
    includeLastLocation?: boolean;
  } = {}
) {
  const {
    locationOptIn = true,
    presenceState = "in_game",
    at = RECENT,
    latitude = 51.5,
    longitude = -0.12,
    accuracy = 10,
    includeLastLocation = true,
  } = opts;
  const inGame = presenceState === "in_game";
  const data: Record<string, unknown> = {
    role: "player",
    locationOptIn,
    presenceState,
  };
  if (includeLastLocation) {
    data.lastLocation = {
      latitude,
      longitude,
      accuracy,
      source: "gps",
      timestamp: ts(at),
      presenceState,
      inGame,
    };
  }
  stub.store.set(memberPath(uid), data);
}

test("returns latest positions for opted-in members with recent lastLocation", async () => {
  const stub = makeFirestoreStub();
  seedIntegration(stub);
  seedMemberWithLastLocation(stub, "player-a", {
    latitude: 51.5074,
    longitude: -0.1278,
    accuracy: 8,
  });
  seedMemberWithLastLocation(stub, "player-b", { locationOptIn: false });

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

test("includes out_of_game members with recent lastLocation", async () => {
  const stub = makeFirestoreStub();
  seedIntegration(stub);
  seedMemberWithLastLocation(stub, "player-oog", {
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

test("returns empty array when opted-in members have stale lastLocation", async () => {
  const stub = makeFirestoreStub();
  seedIntegration(stub);
  seedMemberWithLastLocation(stub, "player-a", { at: STALE });

  const result = await runGetLatestPlayerLocations(
    depsForStub(stub),
    callableRequest({ gameId: "g1::crucible", apiKey: API_KEY })
  );

  assert.deepEqual(result.players, []);
});

test("omits opted-in members without lastLocation", async () => {
  const stub = makeFirestoreStub();
  seedIntegration(stub);
  seedMemberWithLastLocation(stub, "player-a", { includeLastLocation: false });

  const result = await runGetLatestPlayerLocations(
    depsForStub(stub),
    callableRequest({ gameId: "g1::crucible", apiKey: API_KEY })
  );

  assert.deepEqual(result.players, []);
});

test("does not query locationPings collection", async () => {
  const stub = makeFirestoreStub([], {
    failOnGet: (path, kind) => {
      if (kind === "collection" && path === pingCollectionPath()) {
        return new Error("locationPings must not be queried on hot path");
      }
      return null;
    },
  });
  seedIntegration(stub);
  seedMemberWithLastLocation(stub, "player-a");

  const result = await runGetLatestPlayerLocations(
    depsForStub(stub),
    callableRequest({ gameId: "g1::crucible", apiKey: API_KEY })
  );

  assert.equal(result.players.length, 1);
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
  seedMemberWithLastLocation(stub, "player-a");

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
