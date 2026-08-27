import { test } from "node:test";
import * as assert from "node:assert/strict";

import * as index from "./index";

test("syncOfflineChanges is not exported from index", () => {
  assert.equal(
    "syncOfflineChanges" in index,
    false,
    "syncOfflineChanges must not be exported — it allowed arbitrary Admin SDK writes"
  );
});

test("registerNfcHuntTag and recordNfcHuntScan are exported (Task 002)", () => {
  assert.equal(
    "registerNfcHuntTag" in index,
    true,
    "registerNfcHuntTag must be exported from functions/src/index.ts"
  );
  assert.equal(
    "recordNfcHuntScan" in index,
    true,
    "recordNfcHuntScan must be exported from functions/src/index.ts"
  );
});
