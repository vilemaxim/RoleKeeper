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
