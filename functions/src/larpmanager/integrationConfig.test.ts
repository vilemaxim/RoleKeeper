/**
 * Unit tests for the LarpManager integration config loader — pinned by
 * Task 012 (`docs/adr/0001-remove-fetchdetails-toggle.md`).
 *
 * `parseIntegrationDoc` reads a `larpManagerIntegration/config` Firestore
 * doc and returns the public-shape projection. Historically that
 * projection included `fetchDetails: boolean`. After Task 012 the field
 * is removed from the returned shape entirely.
 *
 * The loader must, however, TOLERATE legacy docs that still carry
 * `fetchDetails: bool` from before the migration — we explicitly chose
 * NOT to write a Firestore migration to delete the field. The loader
 * must read those docs without throwing and must NOT surface the legacy
 * field on the returned object.
 *
 * These tests are intentionally pure: no firebase-admin app, no
 * emulator, no network. `parseIntegrationDoc` is a synchronous helper
 * that takes a plain object.
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";

import { parseIntegrationDoc } from "./integrationConfig";

test(
  "parseIntegrationDoc (Task 012): tolerates a legacy fetchDetails:true " +
    "in the stored doc and the returned object has NO fetchDetails key",
  () => {
    const pub = parseIntegrationDoc({
      baseUrl: "https://lm.example",
      eventSlug: "crucible",
      loginPath: "/login/",
      // Legacy field that some existing Firestore docs still carry.
      // Loader must read past it without throwing or warning.
      fetchDetails: true,
      credentialsConfigured: true,
    });

    assert.ok(pub, "loader must return a non-null result for a valid doc");
    assert.equal(
      "fetchDetails" in (pub as unknown as Record<string, unknown>),
      false,
      "the returned LarpManagerIntegrationPublic must NOT include a " +
        "fetchDetails key after Task 012",
    );
    // Sanity: the rest of the projection is intact.
    assert.equal(pub!.baseUrl, "https://lm.example");
    assert.equal(pub!.eventSlug, "crucible");
    assert.equal(pub!.loginPath, "/login/");
    assert.equal(pub!.credentialsConfigured, true);
  },
);

test(
  "parseIntegrationDoc (Task 012): tolerates a legacy fetchDetails:false " +
    "in the stored doc and the returned object has NO fetchDetails key",
  () => {
    const pub = parseIntegrationDoc({
      baseUrl: "https://lm.example",
      eventSlug: "crucible",
      loginPath: "/login/",
      fetchDetails: false,
      credentialsConfigured: false,
    });

    assert.ok(pub);
    assert.equal(
      "fetchDetails" in (pub as unknown as Record<string, unknown>),
      false,
      "the returned object must NOT include fetchDetails even when the " +
        "stored value was explicitly false",
    );
  },
);

test(
  "parseIntegrationDoc (Task 012): a doc with no fetchDetails field at " +
    "all still parses and the returned object has no fetchDetails key",
  () => {
    const pub = parseIntegrationDoc({
      baseUrl: "https://lm.example",
      eventSlug: "crucible",
      loginPath: "/login/",
      credentialsConfigured: true,
    });

    assert.ok(pub);
    assert.equal(
      "fetchDetails" in (pub as unknown as Record<string, unknown>),
      false,
      "absence of fetchDetails in storage must yield absence on output",
    );
  },
);
