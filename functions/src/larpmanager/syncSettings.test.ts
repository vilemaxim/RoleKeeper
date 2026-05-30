import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as admin from "firebase-admin";

import {
  isUtcHourInSyncWindow,
  parseLarpManagerSyncSettings,
  shouldRunScheduledLarpManagerSync,
} from "./syncSettings";

test("parseLarpManagerSyncSettings defaults when missing", () => {
  const s = parseLarpManagerSyncSettings(undefined);
  assert.equal(s.scheduledSyncEnabled, false);
  assert.equal(s.minIntervalMinutes, 15);
});

test("parseLarpManagerSyncSettings reads enabled", () => {
  const s = parseLarpManagerSyncSettings({
    scheduledSyncEnabled: true,
    minIntervalMinutes: 60,
  });
  assert.equal(s.scheduledSyncEnabled, true);
  assert.equal(s.minIntervalMinutes, 60);
});

test("isUtcHourInSyncWindow same start end is single hour", () => {
  assert.equal(isUtcHourInSyncWindow(8, 8, 8), true);
  assert.equal(isUtcHourInSyncWindow(9, 8, 8), false);
});

test("isUtcHourInSyncWindow normal range inclusive", () => {
  assert.equal(isUtcHourInSyncWindow(10, 9, 17), true);
  assert.equal(isUtcHourInSyncWindow(8, 9, 17), false);
  assert.equal(isUtcHourInSyncWindow(18, 9, 17), false);
});

test("isUtcHourInSyncWindow overnight", () => {
  assert.equal(isUtcHourInSyncWindow(23, 22, 6), true);
  assert.equal(isUtcHourInSyncWindow(3, 22, 6), true);
  assert.equal(isUtcHourInSyncWindow(12, 22, 6), false);
});

test("shouldRunScheduledLarpManagerSync disabled", () => {
  const r = shouldRunScheduledLarpManagerSync(
    {
      ...parseLarpManagerSyncSettings(undefined),
      scheduledSyncEnabled: false,
    },
    null,
    new Date()
  );
  assert.equal(r.run, false);
  assert.equal(r.reason, "scheduled_sync_disabled");
});

test("shouldRunScheduledLarpManagerSync interval", () => {
  const last = admin.firestore.Timestamp.fromMillis(Date.now() - 60_000);
  const r = shouldRunScheduledLarpManagerSync(
    {
      scheduledSyncEnabled: true,
      minIntervalMinutes: 15,
      restrictSyncToWindowUtc: false,
      windowStartHourUtc: 0,
      windowEndHourUtc: 23,
    },
    last,
    new Date()
  );
  assert.equal(r.run, false);
  assert.equal(r.reason, "min_interval_not_elapsed");
});
