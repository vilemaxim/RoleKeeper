import { test } from "node:test";
import * as assert from "node:assert/strict";

import { parseLarpManagerAuthSecret } from "./authSecret";

test("parseLarpManagerAuthSecret session trims value", () => {
  const r = parseLarpManagerAuthSecret("session:  abc123 ");
  assert.equal(r.sessionId, "abc123");
  assert.equal(r.username, undefined);
});

test("parseLarpManagerAuthSecret password splits on first colon", () => {
  const r = parseLarpManagerAuthSecret("password:bot@example.com:secretpass");
  assert.equal(r.username, "bot@example.com");
  assert.equal(r.password, "secretpass");
});

test("parseLarpManagerAuthSecret rejects unknown prefix", () => {
  assert.throws(() => parseLarpManagerAuthSecret("bearer:token"), /must start/);
});
