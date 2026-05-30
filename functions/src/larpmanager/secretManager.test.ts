import { test } from "node:test";
import * as assert from "node:assert/strict";

import { larpManagerSecretIdForGame } from "./secretManager";

test("larpManagerSecretIdForGame sanitizes special chars", () => {
  assert.equal(
    larpManagerSecretIdForGame("my/game"),
    "lm-auth-my-game"
  );
});

test("larpManagerSecretIdForGame empty-ish uses game", () => {
  assert.ok(larpManagerSecretIdForGame("///").startsWith("lm-auth-"));
});
