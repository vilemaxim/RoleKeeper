import { test } from "node:test";
import * as assert from "node:assert/strict";
import AdmZip from "adm-zip";

import {
  parseCsvLine,
  parseRegistrationEmailsFromCsv,
  parseRegistrationRowsFromCsv,
  registrationDocIdForEmail,
  extractRegistrationCsvFromZip,
  buildRegistrationPageUrl,
} from "./registrations";
import type { LarpManagerSyncConfig } from "./types";

test("parseCsvLine handles quoted commas", () => {
  assert.deepEqual(parseCsvLine('a,"b,c",d'), ["a", "b,c", "d"]);
});

test("parseRegistrationEmailsFromCsv reads Email column", () => {
  const csv = [
    "Name,Email,Ticket",
    "Alice,alice@example.com,Standard",
    'Bob,"bob@test.org",Staff',
  ].join("\n");
  const emails = parseRegistrationEmailsFromCsv(csv);
  assert.deepEqual(emails.sort(), ["alice@example.com", "bob@test.org"]);
});

test("parseRegistrationRowsFromCsv reads Characters column", () => {
  const csv = [
    "Name,Email,Characters",
    "Alice,alice@example.com,Alice Hero",
    "Bob,bob@test.org,\"Hero One, Sidekick\"",
  ].join("\n");
  const rows = parseRegistrationRowsFromCsv(csv);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], {
    emailLower: "alice@example.com",
    characterNames: ["Alice Hero"],
  });
  assert.deepEqual(rows[1]?.characterNames, ["Hero One", "Sidekick"]);
});

// Regression for task 001 root cause: real LarpManager registration exports may
// label the column "Character" (singular) depending on event feature config /
// localization. With the strict `=== "characters"` check, every row got
// `characterNames: []`, which short-circuited `syncPlayerCharactersForUser`
// into the "create a character on LarpManager" branch even when the player
// already had a character assigned in LM.
test("parseRegistrationRowsFromCsv accepts singular 'Character' header", () => {
  const csv = [
    "Name,Email,Character",
    "Alice,alice@example.com,Alice Hero",
  ].join("\n");
  const rows = parseRegistrationRowsFromCsv(csv);
  assert.equal(rows.length, 1);
  assert.deepEqual(rows[0]?.characterNames, ["Alice Hero"]);
});

test("registrationDocIdForEmail is stable", () => {
  const a = registrationDocIdForEmail("User@Example.COM");
  const b = registrationDocIdForEmail("user@example.com");
  assert.equal(a, b);
  assert.equal(a.length, 64);
});

test("extractRegistrationCsvFromZip reads registration.csv", () => {
  const zip = new AdmZip();
  zip.addFile(
    "registration.csv",
    Buffer.from("Name,Email\nX,x@y.com\n", "utf8")
  );
  const csv = extractRegistrationCsvFromZip(zip.toBuffer());
  assert.ok(csv.includes("x@y.com"));
});

test("buildRegistrationPageUrl", () => {
  const cfg: LarpManagerSyncConfig = {
    baseUrl: "https://lm.example/",
    eventSlug: "my-event-1",
    fetchDetails: false,
  };
  assert.equal(
    buildRegistrationPageUrl(cfg),
    "https://lm.example/my-event-1/register/"
  );
});
