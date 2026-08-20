/**
 * Unit tests for Task 002 `registerNfcHuntTag` callable body.
 *
 * Pins requirements from `docs/tasks/ready/002-coder.md` and ADR 007:
 *   - Auth required; tenant from body (gameId or instanceId+eventSlug)
 *   - Caller is organizer (owner/superAdmin) OR uid in hunt.placerUids
 *   - Upsert tags/{tagUid}; tagUid non-empty after trim
 *   - fixed placement accepts optional sanitized location
 *   - floating placement omits/clears fixed location
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, type GameTenant } from "../gameTenant";
import { makeFirestoreStub } from "../_testing/firestoreStub";
import {
  runRegisterNfcHuntTag,
  type RegisterNfcHuntTagBody,
  type RegisterNfcHuntTagDeps,
} from "./registerNfcHuntTag";

const TENANT: GameTenant = { instanceId: "g1", eventSlug: "crucible" };
const BASE = gameEventBase(TENANT);
const HUNT_ID = "hunt-forest";
const ORGANIZER_UID = "owner-alice";
const SUPER_ADMIN_UID = "super-admin-bob";
const PLACER_UID = "placer-gina";
const PLAYER_UID = "player-dan";
const TAG_UID = "tag-oak-01";

const VALID_LOCATION = {
  latitude: 51.5074,
  longitude: -0.1278,
  accuracy: 12.5,
};

const REGISTERED_AT = new Date("2026-08-19T18:00:00.000Z");

function ts(d: Date): admin.firestore.Timestamp {
  return { toDate: () => d } as admin.firestore.Timestamp;
}

function memberPath(uid: string): string {
  return `${BASE}/members/${uid}`;
}

function huntPath(huntId = HUNT_ID): string {
  return `${BASE}/nfcHunts/${huntId}`;
}

function tagPath(tagUid: string, huntId = HUNT_ID): string {
  return `${huntPath(huntId)}/tags/${tagUid}`;
}

function callableRequest(
  body: RegisterNfcHuntTagBody,
  uid?: string
): CallableRequest<RegisterNfcHuntTagBody> {
  return {
    data: body,
    auth: uid ? { uid, token: {} as never } : undefined,
  } as CallableRequest<RegisterNfcHuntTagBody>;
}

function depsForStub(
  stub: ReturnType<typeof makeFirestoreStub>,
  now?: admin.firestore.Timestamp
): RegisterNfcHuntTagDeps {
  return {
    db: stub.db as unknown as admin.firestore.Firestore,
    now: now ? () => now : () => ts(REGISTERED_AT),
  };
}

function seedHunt(
  stub: ReturnType<typeof makeFirestoreStub>,
  opts: {
    placerUids?: string[];
    enabled?: boolean;
  } = {}
): void {
  stub.store.set(huntPath(), {
    enabled: opts.enabled ?? true,
    name: "Forest Hunt",
    expectedTagCount: 12,
    placerUids: opts.placerUids ?? [PLACER_UID],
  });
}

function seedMember(
  stub: ReturnType<typeof makeFirestoreStub>,
  uid: string,
  role: string
): void {
  stub.store.set(memberPath(uid), { role });
}

function happyBody(
  extra: Partial<RegisterNfcHuntTagBody> = {}
): RegisterNfcHuntTagBody {
  return {
    gameId: "g1::crucible",
    huntId: HUNT_ID,
    tagUid: TAG_UID,
    placement: "fixed",
    label: "Oak grove",
    ...extra,
  };
}

test("organizer upserts a fixed tag with optional location", async () => {
  const stub = makeFirestoreStub();
  seedMember(stub, ORGANIZER_UID, "owner");
  seedHunt(stub);

  const result = await runRegisterNfcHuntTag(
    depsForStub(stub),
    callableRequest(
      happyBody({
        location: VALID_LOCATION,
      }),
      ORGANIZER_UID
    )
  );

  assert.equal(result.tagUid, TAG_UID);
  const written = stub.store.get(tagPath(TAG_UID));
  assert.ok(written, "expected tags/{tagUid} upsert");
  assert.equal(written!.label, "Oak grove");
  assert.equal(written!.placement, "fixed");
  assert.equal(written!.registeredByUid, ORGANIZER_UID);
  assert.ok(written!.registeredAt);
  const loc = written!.location as Record<string, unknown>;
  assert.equal(loc.latitude, VALID_LOCATION.latitude);
  assert.equal(loc.longitude, VALID_LOCATION.longitude);
});

test("organizer allowed when role is superAdmin", async () => {
  const stub = makeFirestoreStub();
  seedMember(stub, SUPER_ADMIN_UID, "superAdmin");
  seedHunt(stub, { placerUids: [] });

  await runRegisterNfcHuntTag(
    depsForStub(stub),
    callableRequest(happyBody({ placement: "floating" }), SUPER_ADMIN_UID)
  );

  assert.ok(stub.store.get(tagPath(TAG_UID)));
});

test("placer listed in hunt.placerUids can register a tag", async () => {
  const stub = makeFirestoreStub();
  seedMember(stub, PLACER_UID, "player");
  seedHunt(stub, { placerUids: [PLACER_UID] });

  await runRegisterNfcHuntTag(
    depsForStub(stub),
    callableRequest(
      {
        instanceId: TENANT.instanceId,
        eventSlug: TENANT.eventSlug,
        huntId: HUNT_ID,
        tagUid: TAG_UID,
        placement: "floating",
      },
      PLACER_UID
    )
  );

  const written = stub.store.get(tagPath(TAG_UID));
  assert.ok(written);
  assert.equal(written!.registeredByUid, PLACER_UID);
  assert.equal(written!.placement, "floating");
  assert.equal("location" in written!, false);
});

test("non-placer member is denied", async () => {
  const stub = makeFirestoreStub();
  seedMember(stub, PLAYER_UID, "player");
  seedHunt(stub, { placerUids: [PLACER_UID] });

  await assert.rejects(
    () =>
      runRegisterNfcHuntTag(
        depsForStub(stub),
        callableRequest(happyBody(), PLAYER_UID)
      ),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
  assert.equal(stub.store.get(tagPath(TAG_UID)), undefined);
});

test("rejects invalid tagUid (empty after trim)", async () => {
  const stub = makeFirestoreStub();
  seedMember(stub, ORGANIZER_UID, "owner");
  seedHunt(stub);

  for (const tagUid of ["", "   "]) {
    await assert.rejects(
      () =>
        runRegisterNfcHuntTag(
          depsForStub(stub),
          callableRequest(happyBody({ tagUid }), ORGANIZER_UID)
        ),
      (err: unknown) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, "invalid-argument");
        return true;
      }
    );
  }
  assert.equal(stub.writes.length, 0);
});

test("trims tagUid and uses trimmed value as document id", async () => {
  const stub = makeFirestoreStub();
  seedMember(stub, ORGANIZER_UID, "owner");
  seedHunt(stub);

  const result = await runRegisterNfcHuntTag(
    depsForStub(stub),
    callableRequest(happyBody({ tagUid: `  ${TAG_UID}  ` }), ORGANIZER_UID)
  );

  assert.equal(result.tagUid, TAG_UID);
  assert.ok(stub.store.get(tagPath(TAG_UID)));
  assert.equal(stub.store.get(tagPath(`  ${TAG_UID}  `)), undefined);
});

test("floating placement clears previously stored fixed location", async () => {
  const stub = makeFirestoreStub();
  seedMember(stub, ORGANIZER_UID, "owner");
  seedHunt(stub);
  stub.store.set(tagPath(TAG_UID), {
    label: "Oak grove",
    placement: "fixed",
    location: VALID_LOCATION,
    registeredByUid: ORGANIZER_UID,
    registeredAt: ts(REGISTERED_AT),
  });

  await runRegisterNfcHuntTag(
    depsForStub(stub),
    callableRequest(
      happyBody({ placement: "floating", location: VALID_LOCATION }),
      ORGANIZER_UID
    )
  );

  const written = stub.store.get(tagPath(TAG_UID));
  assert.ok(written);
  assert.equal(written!.placement, "floating");
  assert.equal("location" in written!, false);
});

test("rejects unauthenticated callers", async () => {
  const stub = makeFirestoreStub();
  seedMember(stub, ORGANIZER_UID, "owner");
  seedHunt(stub);

  await assert.rejects(
    () => runRegisterNfcHuntTag(depsForStub(stub), callableRequest(happyBody())),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );
  assert.equal(stub.writes.length, 0);
});
