import { test } from "node:test";
import * as assert from "node:assert/strict";

import {
  secretManagerSetupErrorMessage,
  toHttpsErrorForLarpManagerCredentialSave,
} from "./gcpErrors";

test("toHttpsErrorForLarpManagerCredentialSave maps permission denied", () => {
  const err = toHttpsErrorForLarpManagerCredentialSave(
    Object.assign(new Error("7 PERMISSION_DENIED: secretmanager.secrets.create"), {
      code: 7,
    }),
    "rolekeeper-test"
  );
  assert.equal(err.code, "permission-denied");
  assert.match(err.message, /Secret Manager/);
  assert.match(err.message, /rolekeeper-test/);
});

test("secretManagerSetupErrorMessage mentions FIREBASE_SETUP", () => {
  assert.match(
    secretManagerSetupErrorMessage("my-project"),
    /FIREBASE_SETUP/
  );
});
