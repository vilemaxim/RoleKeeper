/**
 * Unit tests for the reusable in-app notification writer (Task 001).
 *
 * Pins:
 *   - Writes `users/{uid}/inAppNotifications/{id}` with required fields
 *   - `readAt` starts null; `createdAt` is a server timestamp
 *   - Optional `tenantKey` and `payload`
 *   - Exports `nfc_hunt_scan_result` for Task 005
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";

import { makeFirestoreStub } from "../_testing/firestoreStub";
import {
  NFC_HUNT_SCAN_RESULT,
  createInAppNotification,
} from "./createInAppNotification";

const UID = "player-alpha";

test("NFC_HUNT_SCAN_RESULT is nfc_hunt_scan_result", () => {
  assert.equal(NFC_HUNT_SCAN_RESULT, "nfc_hunt_scan_result");
});

test("createInAppNotification writes an unread inbox document", async () => {
  const stub = makeFirestoreStub();

  const id = await createInAppNotification(
    stub.db as unknown as admin.firestore.Firestore,
    {
      uid: UID,
      type: NFC_HUNT_SCAN_RESULT,
      title: "Tag scanned",
      body: "You credited the forest shrine.",
      tenantKey: "g1::crucible",
      payload: { huntId: "hunt-1", tagUid: "tag-aa" },
    }
  );

  assert.equal(typeof id, "string");
  assert.ok(id.length > 0);

  const path = `users/${UID}/inAppNotifications/${id}`;
  const stored = stub.store.get(path);
  assert.ok(stored, `expected write at ${path}`);
  assert.equal(stored.type, NFC_HUNT_SCAN_RESULT);
  assert.equal(stored.title, "Tag scanned");
  assert.equal(stored.body, "You credited the forest shrine.");
  assert.equal(stored.readAt, null);
  assert.equal(stored.tenantKey, "g1::crucible");
  assert.deepEqual(stored.payload, { huntId: "hunt-1", tagUid: "tag-aa" });
  assert.ok(stored.createdAt, "createdAt must be set (server timestamp)");
});

test("createInAppNotification omits tenantKey and payload when not provided", async () => {
  const stub = makeFirestoreStub();

  const id = await createInAppNotification(
    stub.db as unknown as admin.firestore.Firestore,
    {
      uid: UID,
      type: "generic",
      title: "Hello",
      body: "World",
    }
  );

  const stored = stub.store.get(`users/${UID}/inAppNotifications/${id}`);
  assert.ok(stored);
  assert.equal(stored.type, "generic");
  assert.equal("tenantKey" in stored, false);
  assert.deepEqual(stored.payload, {});
  assert.equal(stored.readAt, null);
});
