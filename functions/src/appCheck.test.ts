/**
 * Task 007 — Firebase App Check enforcement on Cloud Functions callables.
 *
 * Pins requirements from `docs/tasks/ready/007-coder.md` and ADR 005:
 *   - Auth-backed callables enable `enforceAppCheck: true` in onCall options
 *   - Home Assistant API-key callable `getLatestPlayerLocations` stays exempt
 *
 * Source-level guards: implementation phase adds enforceAppCheck to index.ts.
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import * as assert from "node:assert/strict";

const INDEX_SOURCE = readFileSync(join(__dirname, "..", "src", "index.ts"), "utf8");

/** Callable exports that must enforce App Check (Firebase Auth clients). */
const APP_CHECK_ENFORCED_CALLABLES = [
  "createActiveGameEvent",
  "saveLarpManagerIntegrationConfig",
  "runLarpManagerSyncCallable",
  "syncMyLarpManagerCharacterCallable",
  "checkLarpManagerRegistrationCallable",
  "recordLocationPing",
  "configureHomeAssistantIntegration",
  "getDeathInterventionSecrets",
] as const;

/** HA integration uses per-event API keys — out of scope for App Check (ADR 004/005). */
const APP_CHECK_EXEMPT_CALLABLES = ["getLatestPlayerLocations"] as const;

function onCallOptionsBlock(exportName: string): string {
  const marker = `export const ${exportName} = onCall(`;
  const start = INDEX_SOURCE.indexOf(marker);
  assert.notEqual(
    start,
    -1,
    `index.ts must export callable ${exportName}`
  );
  const afterMarker = INDEX_SOURCE.slice(start + marker.length).trimStart();
  if (afterMarker.startsWith("APP_CHECK_CALLABLE")) {
    return "APP_CHECK_CALLABLE";
  }
  const afterOnCall = INDEX_SOURCE.indexOf("{", start + marker.length);
  assert.notEqual(afterOnCall, -1, `${exportName} onCall options object missing`);
  const closeBrace = INDEX_SOURCE.indexOf("}", afterOnCall);
  assert.notEqual(closeBrace, -1, `${exportName} onCall options object unclosed`);
  return INDEX_SOURCE.slice(afterOnCall, closeBrace + 1);
}

function optionsEnforceAppCheck(options: string): boolean {
  return (
    options.includes("APP_CHECK_CALLABLE") ||
    /enforceAppCheck:\s*true/.test(options)
  );
}

for (const name of APP_CHECK_ENFORCED_CALLABLES) {
  test(`${name} enables enforceAppCheck in onCall options`, () => {
    const options = onCallOptionsBlock(name);
    assert.equal(
      optionsEnforceAppCheck(options),
      true,
      `${name} must pass { enforceAppCheck: true } to onCall per ADR 005`
    );
  });
}

for (const name of APP_CHECK_EXEMPT_CALLABLES) {
  test(`${name} does not enforce App Check (API-key auth)`, () => {
    const options = onCallOptionsBlock(name);
    assert.doesNotMatch(
      options,
      /enforceAppCheck:\s*true/,
      `${name} uses Home Assistant API keys — App Check must stay disabled`
    );
  });
}
