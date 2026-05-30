import { test } from "node:test";
import * as assert from "node:assert/strict";

import {
  buildCharacterCreatePageUrl,
  resolveCharactersByNames,
  shortIdForLmCharacter,
} from "./playerCharacters";
import type { LarpManagerSyncConfig } from "./types";

test("buildCharacterCreatePageUrl", () => {
  const cfg: LarpManagerSyncConfig = {
    baseUrl: "https://lm.example/",
    eventSlug: "my-event-1",
    fetchDetails: false,
  };
  assert.equal(
    buildCharacterCreatePageUrl(cfg),
    "https://lm.example/my-event-1/character/create/"
  );
});

test("resolveCharactersByNames matches export by name", () => {
  const exportMap = {
    "1": { number: 1, name: "Alice Hero", uuid: "uuid-a" },
    "2": { number: 42, name: "Bob Scout", uuid: "uuid-b" },
  };
  const resolved = resolveCharactersByNames(exportMap, [
    "alice hero",
    "Bob Scout",
    "Unknown",
  ]);
  assert.equal(resolved.length, 2);
  assert.deepEqual(resolved[0], {
    uuid: "uuid-a",
    name: "Alice Hero",
    number: 1,
  });
});

test("shortIdForLmCharacter uses number when present", () => {
  assert.equal(
    shortIdForLmCharacter({ uuid: "x", name: "A", number: 7 }),
    "007"
  );
});
