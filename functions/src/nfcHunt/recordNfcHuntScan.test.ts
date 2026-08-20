/**
 * Unit tests for Task 002 `recordNfcHuntScan` callable body.
 *
 * Pins requirements from `docs/tasks/ready/002-coder.md` and ADR 007:
 *   - Auth required; tenant + huntId + characterId + tagUid
 *   - Hunt exists and enabled == true (independent of eventSession.isLive)
 *   - Character exists and ownerId == caller uid
 *   - Registered tag → credit scan + character mirror, or already_scanned
 *   - Unknown tag → reviewScans + unknown_tag
 *   - Optional location, clientScannedAt, queuedOffline
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, tenantKey, type GameTenant } from "../gameTenant";
import { makeFirestoreStub } from "../_testing/firestoreStub";
import {
  runRecordNfcHuntScan,
  type RecordNfcHuntScanBody,
  type RecordNfcHuntScanDeps,
} from "./recordNfcHuntScan";

const TENANT: GameTenant = { instanceId: "g1", eventSlug: "crucible" };
const BASE = gameEventBase(TENANT);
const TKEY = tenantKey(TENANT);
const HUNT_ID = "hunt-forest";
const UID = "player-alpha";
const OTHER_UID = "player-beta";
const CHARACTER_ID = "char-alpha-01";
const TAG_UID = "tag-oak-01";
const UNKNOWN_TAG_UID = "tag-unknown-99";

const VALID_LOCATION = {
  latitude: 51.5074,
  longitude: -0.1278,
  accuracy: 8,
};

const SCAN_TIME = new Date("2026-08-19T19:00:00.000Z");
const CLIENT_SCAN_TIME = new Date("2026-08-19T18:59:00.000Z");

function ts(d: Date): admin.firestore.Timestamp {
  return { toDate: () => d } as admin.firestore.Timestamp;
}

function memberPath(uid: string): string {
  return `${BASE}/members/${uid}`;
}

function huntPath(huntId = HUNT_ID): string {
  return `${BASE}/nfcHunts/${huntId}`;
}

function tagPath(tagUid: string): string {
  return `${huntPath()}/tags/${tagUid}`;
}

function characterPath(characterId = CHARACTER_ID): string {
  return `${BASE}/characters/${characterId}`;
}

function scansPrefix(): string {
  return `${huntPath()}/scans`;
}

function reviewScansPrefix(): string {
  return `${huntPath()}/reviewScans`;
}

function mirrorPrefix(characterId = CHARACTER_ID): string {
  return `${characterPath(characterId)}/nfcHuntScans`;
}

function callableRequest(
  body: RecordNfcHuntScanBody,
  uid?: string
): CallableRequest<RecordNfcHuntScanBody> {
  return {
    data: body,
    auth: uid ? { uid, token: {} as never } : undefined,
  } as CallableRequest<RecordNfcHuntScanBody>;
}

function depsForStub(
  stub: ReturnType<typeof makeFirestoreStub>,
  now?: admin.firestore.Timestamp
): RecordNfcHuntScanDeps {
  return {
    db: stub.db as unknown as admin.firestore.Firestore,
    now: now ? () => now : () => ts(SCAN_TIME),
  };
}

function seedHappyPath(
  stub: ReturnType<typeof makeFirestoreStub>,
  opts: { huntEnabled?: boolean } = {}
): void {
  stub.store.set(memberPath(UID), { role: "player" });
  stub.store.set(huntPath(), {
    enabled: opts.huntEnabled ?? true,
    name: "Forest Hunt",
    expectedTagCount: 12,
    placerUids: [],
  });
  stub.store.set(tagPath(TAG_UID), {
    placement: "floating",
    registeredByUid: "owner-alice",
    registeredAt: ts(SCAN_TIME),
  });
  stub.store.set(characterPath(), {
    ownerId: UID,
    name: "Alder",
  });
}

function happyBody(
  extra: Partial<RecordNfcHuntScanBody> = {}
): RecordNfcHuntScanBody {
  return {
    gameId: "g1::crucible",
    huntId: HUNT_ID,
    characterId: CHARACTER_ID,
    tagUid: TAG_UID,
    ...extra,
  };
}

function creditedScans(
  stub: ReturnType<typeof makeFirestoreStub>,
  characterId = CHARACTER_ID,
  tagUid = TAG_UID
): Array<{ path: string; data: Record<string, unknown> }> {
  const prefix = `${scansPrefix()}/`;
  const out: Array<{ path: string; data: Record<string, unknown> }> = [];
  for (const [path, data] of stub.store.entries()) {
    if (!path.startsWith(prefix)) continue;
    if (path.slice(prefix.length).includes("/")) continue;
    if (data.characterId === characterId && data.tagUid === tagUid) {
      out.push({ path, data });
    }
  }
  return out;
}

test("credits a registered tag and mirrors onto the character", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);

  const result = await runRecordNfcHuntScan(
    depsForStub(stub),
    callableRequest(
      happyBody({
        location: VALID_LOCATION,
        clientScannedAt: ts(CLIENT_SCAN_TIME),
        queuedOffline: true,
      }),
      UID
    )
  );

  assert.equal(result.outcome, "credited");
  assert.ok(result.scanId);
  const scanId = result.scanId!;

  const scan = stub.store.get(`${scansPrefix()}/${scanId}`);
  assert.ok(scan, "expected a credit scan write");
  assert.equal(scan!.characterId, CHARACTER_ID);
  assert.equal(scan!.ownerUid, UID);
  assert.equal(scan!.tagUid, TAG_UID);
  assert.equal(scan!.huntId, HUNT_ID);
  assert.equal(scan!.tenantKey, TKEY);
  assert.equal(scan!.queuedOffline, true);
  assert.ok(scan!.scannedAt);
  const loc = scan!.location as Record<string, unknown>;
  assert.equal(loc.latitude, VALID_LOCATION.latitude);
  assert.equal(loc.longitude, VALID_LOCATION.longitude);

  const mirror = stub.store.get(`${mirrorPrefix()}/${scanId}`);
  assert.ok(mirror, "expected character nfcHuntScans mirror");
  assert.equal(mirror!.tagUid, TAG_UID);
  assert.equal(mirror!.characterId, CHARACTER_ID);
});

test("duplicate credit for the same character and tag returns already_scanned", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);

  const first = await runRecordNfcHuntScan(
    depsForStub(stub),
    callableRequest(happyBody(), UID)
  );
  assert.equal(first.outcome, "credited");
  const writesAfterFirst = stub.writes.length;

  const second = await runRecordNfcHuntScan(
    depsForStub(stub),
    callableRequest(happyBody(), UID)
  );

  assert.equal(second.outcome, "already_scanned");
  assert.equal(creditedScans(stub).length, 1);
  assert.equal(
    stub.writes.length,
    writesAfterFirst,
    "duplicate must not write another credit or mirror"
  );
});

test("unknown tag writes reviewScans and returns unknown_tag", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);

  const result = await runRecordNfcHuntScan(
    depsForStub(stub),
    callableRequest(happyBody({ tagUid: UNKNOWN_TAG_UID }), UID)
  );

  assert.equal(result.outcome, "unknown_tag");
  assert.equal(creditedScans(stub, CHARACTER_ID, UNKNOWN_TAG_UID).length, 0);

  const reviewWrites = stub.writes.filter((w) =>
    w.path.startsWith(`${reviewScansPrefix()}/`)
  );
  assert.equal(reviewWrites.length, 1);
  assert.equal(reviewWrites[0]!.data.tagUid, UNKNOWN_TAG_UID);
  assert.equal(reviewWrites[0]!.data.reason, "unknown_tag");
  assert.equal(reviewWrites[0]!.data.characterId, CHARACTER_ID);
  assert.equal(reviewWrites[0]!.data.ownerUid, UID);

  const mirrorWrites = stub.writes.filter((w) =>
    w.path.startsWith(`${mirrorPrefix()}/`)
  );
  assert.equal(mirrorWrites.length, 0);
});

test("rejects scans when hunt is disabled", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub, { huntEnabled: false });

  await assert.rejects(
    () =>
      runRecordNfcHuntScan(depsForStub(stub), callableRequest(happyBody(), UID)),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );
  assert.equal(stub.writes.length, 0);
});

test("rejects when character is owned by a different user", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);
  stub.store.set(memberPath(OTHER_UID), { role: "player" });
  stub.store.set(characterPath(), { ownerId: UID, name: "Alder" });

  await assert.rejects(
    () =>
      runRecordNfcHuntScan(
        depsForStub(stub),
        callableRequest(happyBody(), OTHER_UID)
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
  assert.equal(stub.writes.length, 0);
});

test("rejects unauthenticated callers", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);

  await assert.rejects(
    () => runRecordNfcHuntScan(depsForStub(stub), callableRequest(happyBody())),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );
  assert.equal(stub.writes.length, 0);
});

test("credits even when eventSession is not live", async () => {
  const stub = makeFirestoreStub();
  seedHappyPath(stub);
  stub.store.set(`${BASE}/eventSession/config`, { isLive: false });

  const result = await runRecordNfcHuntScan(
    depsForStub(stub),
    callableRequest(happyBody(), UID)
  );

  assert.equal(result.outcome, "credited");
});
