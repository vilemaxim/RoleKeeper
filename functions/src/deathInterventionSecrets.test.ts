import { test } from "node:test";
import * as assert from "node:assert/strict";

import * as index from "./index";

test("getDeathInterventionSecrets callable is exported for per-event TOTP and QR signing", () => {
  assert.equal(
    "getDeathInterventionSecrets" in index,
    true,
    "getDeathInterventionSecrets must be exported so clients can fetch per-event secrets"
  );
});
