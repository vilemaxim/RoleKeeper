import { test } from "node:test";
import * as assert from "node:assert/strict";

import { generateApiKey, hashApiKey, verifyApiKey } from "./apiKey";

test("hashApiKey is deterministic SHA-256 hex", () => {
  const h1 = hashApiKey("secret");
  const h2 = hashApiKey("secret");
  assert.equal(h1, h2);
  assert.match(h1, /^[0-9a-f]{64}$/);
});

test("verifyApiKey accepts matching plaintext", () => {
  const key = generateApiKey();
  const hash = hashApiKey(key);
  assert.equal(verifyApiKey(key, hash), true);
});

test("verifyApiKey rejects wrong plaintext", () => {
  const hash = hashApiKey("correct");
  assert.equal(verifyApiKey("wrong", hash), false);
});

test("generateApiKey returns distinct values", () => {
  assert.notEqual(generateApiKey(), generateApiKey());
});
