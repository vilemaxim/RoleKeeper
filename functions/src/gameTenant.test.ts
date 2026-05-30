import { test } from "node:test";
import * as assert from "node:assert/strict";

import { parseTenantKey, resolveGameTenantFromBody } from "./gameTenant";

test("parseTenantKey splits instanceId and eventSlug", () => {
  const t = parseTenantKey("lm.example.com::spring-run");
  assert.deepEqual(t, {
    instanceId: "lm.example.com",
    eventSlug: "spring-run",
  });
});

test("resolveGameTenantFromBody prefers gameId over instanceId+eventSlug", () => {
  const t = resolveGameTenantFromBody({
    gameId: "lm.example.com::canonical-run",
    instanceId: "lm.example.com",
    eventSlug: "wrong-run",
  });
  assert.deepEqual(t, {
    instanceId: "lm.example.com",
    eventSlug: "canonical-run",
  });
});

test("resolveGameTenantFromBody uses instanceId+eventSlug when gameId missing", () => {
  const t = resolveGameTenantFromBody({
    instanceId: "lm.example.com",
    eventSlug: "spring-run",
  });
  assert.deepEqual(t, {
    instanceId: "lm.example.com",
    eventSlug: "spring-run",
  });
});
