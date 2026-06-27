import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import type * as admin from "firebase-admin";

import {
  CHARACTERS_BY_EMAIL_COLLECTION,
  CHARACTERS_BY_EMAIL_META_DOC,
  ingestManageRegistrationsHtml,
  parseManageRegistrationsHtml,
  syncLarpManagerCharactersByEmail,
} from "./charactersByEmail";
import { registrationDocIdForEmail } from "./registrations";
import { gameEventBase } from "../gameTenant";
import {
  makeFirestoreStub,
  withCapturedLogs,
} from "../_testing/firestoreStub";

const TENANT = { instanceId: "g1", eventSlug: "evt1" };
const BASE = gameEventBase(TENANT);
const FINAL_URL = "https://lm.example/evt1/manage/registrations/";

// Compiled tests live under `functions/lib/larpmanager/`; fixtures are at
// `functions/test/fixtures/`. Two `..` hops get us to `functions/`, then
// into `test/fixtures/...`.
const FIXTURE_DIR = path.join(
  __dirname,
  "..",
  "..",
  "test",
  "fixtures",
  "crucible-manage-registrations"
);
const FIXTURE_HTML = fs.readFileSync(
  path.join(FIXTURE_DIR, "manage-registrations.html"),
  "utf8"
);

// --- Parser ---------------------------------------------------------------

test("parseManageRegistrationsHtml: returns [] for empty input", () => {
  assert.deepEqual(parseManageRegistrationsHtml(""), []);
});

test(
  "parseManageRegistrationsHtml: pinned fixture — extracts 3 valid rows " +
    "(skips broken rows missing uuid or email)",
  () => {
    const rows = parseManageRegistrationsHtml(FIXTURE_HTML);
    // r0000004 is missing pop=…  → skipped
    // r0000005 is missing <td class="email">  → skipped
    assert.equal(rows.length, 3, "should drop the two broken rows");

    assert.deepEqual(rows[0], {
      emailLower: "player-one@example.test",
      lmUserUuid: "usr111111111",
      characterUuids: ["charuuid0001"],
    });
    assert.deepEqual(rows[1], {
      emailLower: "staff-two@example.test",
      lmUserUuid: "usr222222222",
      characterUuids: [],
    });
    assert.deepEqual(rows[2], {
      // Lowercased even though the source HTML has mixed case.
      emailLower: "player-three@example.test",
      lmUserUuid: "usr333333333",
      // Two character links survive dedup; the manage/registrations/.../
      // customization/ link sharing a uuid prefix must NOT be counted.
      characterUuids: ["charuuid0003", "charuuid0099"],
    });
  }
);

test(
  "parseManageRegistrationsHtml: customization links sharing a uuid prefix " +
    "are NOT counted as a second character (regression on real LM markup)",
  () => {
    const html = `
      <tr id="r1">
        <td><a class="post_popup_member" pop="usr111111111"></a></td>
        <td class="email">x@y.test</td>
        <td>
          <a href="/evt1/manage/characters/charuuid0001/edit/">#1 Char</a>
          <a href="/evt1/manage/registrations/charuuid0001/customization/"></a>
        </td>
      </tr>`;
    const rows = parseManageRegistrationsHtml(html);
    assert.deepEqual(rows[0]?.characterUuids, ["charuuid0001"]);
  }
);

test(
  "parseManageRegistrationsHtml: <td class='email'> with extra classes still parses",
  () => {
    const html = `
      <tr id="r1">
        <td><a class="post_popup_member" pop="usr111111111"></a></td>
        <td class="email center-text">  Mixed-Case@Example.Test  </td>
        <td></td>
      </tr>`;
    const rows = parseManageRegistrationsHtml(html);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.emailLower, "mixed-case@example.test");
  }
);

test(
  "parseManageRegistrationsHtml: row whose 'email' td value doesn't have @ " +
    "is dropped",
  () => {
    const html = `
      <tr id="r1">
        <td><a class="post_popup_member" pop="usr111111111"></a></td>
        <td class="email">not-an-email</td>
        <td></td>
      </tr>`;
    assert.deepEqual(parseManageRegistrationsHtml(html), []);
  }
);

// --- Ingest (Firestore-stub; bypasses HTTP) ------------------------------

test(
  "ingestManageRegistrationsHtml: writes one doc per email keyed by " +
    "sha256(emailLower), with lmUserUuid + characterUuids",
  async () => {
    const { db, store } = makeFirestoreStub();

    await withCapturedLogs(async () => {
      const result = await ingestManageRegistrationsHtml(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        FIXTURE_HTML,
        FINAL_URL
      );
      assert.equal(result.rowCount, 3);
      assert.equal(result.skippedCache, false);

      const docPlayer1 = store.get(
        `${BASE}/${CHARACTERS_BY_EMAIL_COLLECTION}/${registrationDocIdForEmail("player-one@example.test")}`
      );
      assert.ok(docPlayer1);
      assert.equal(docPlayer1.emailLower, "player-one@example.test");
      assert.equal(docPlayer1.lmUserUuid, "usr111111111");
      assert.deepEqual(docPlayer1.characterUuids, ["charuuid0001"]);

      const docStaff2 = store.get(
        `${BASE}/${CHARACTERS_BY_EMAIL_COLLECTION}/${registrationDocIdForEmail("staff-two@example.test")}`
      );
      assert.ok(docStaff2);
      assert.deepEqual(
        docStaff2.characterUuids,
        [],
        "staff row writes an empty characterUuids array (still useful for email→uuid cache)"
      );

      const docPlayer3 = store.get(
        `${BASE}/${CHARACTERS_BY_EMAIL_COLLECTION}/${registrationDocIdForEmail("player-three@example.test")}`
      );
      assert.ok(docPlayer3);
      assert.deepEqual(docPlayer3.characterUuids, [
        "charuuid0003",
        "charuuid0099",
      ]);

      const meta = store.get(`${BASE}/${CHARACTERS_BY_EMAIL_META_DOC}`);
      assert.ok(meta);
      assert.equal(meta.rowCount, 3);
      assert.equal(meta.lastOk, true);
      assert.equal(meta.lastError, null);
    });
  }
);

test(
  "ingestManageRegistrationsHtml: stale docs from a prior sync are pruned " +
    "(syncRunId rotates and orphans are deleted)",
  async () => {
    const stalePath = `${BASE}/${CHARACTERS_BY_EMAIL_COLLECTION}/${registrationDocIdForEmail("ghost@example.test")}`;
    const { db, store } = makeFirestoreStub([
      {
        path: stalePath,
        data: {
          emailLower: "ghost@example.test",
          lmUserUuid: "usr999999999",
          characterUuids: [],
          syncRunId: "old-run-id",
        },
      },
    ]);

    await withCapturedLogs(async () => {
      await ingestManageRegistrationsHtml(
        db as unknown as admin.firestore.Firestore,
        TENANT,
        FIXTURE_HTML,
        FINAL_URL
      );
      assert.equal(
        store.get(stalePath),
        undefined,
        "ghost doc must be deleted after a fresh sync"
      );
    });
  }
);

test(
  "ingestManageRegistrationsHtml: access-denied page throws an actionable " +
    "error naming the orga_registrations permission",
  async () => {
    const { db } = makeFirestoreStub();
    const accessDeniedHtml =
      '<html><head><title>Access denied - Foo</title></head><body></body></html>';

    await withCapturedLogs(async (logs) => {
      await assert.rejects(
        () =>
          ingestManageRegistrationsHtml(
            db as unknown as admin.firestore.Firestore,
            TENANT,
            accessDeniedHtml,
            FINAL_URL
          ),
        /accessDenied|orga_registrations/i
      );
      assert.ok(
        logs.some(
          (l) =>
            l.level === "error" && /management page unusable/i.test(l.msg)
        ),
        "should log the management-page-unusable error"
      );
    });
  }
);

test(
  "ingestManageRegistrationsHtml: empty page (no <tr id=…>) throws " +
    "'unknownNoRows' rather than silently writing nothing",
  async () => {
    const { db } = makeFirestoreStub();
    await withCapturedLogs(async () => {
      await assert.rejects(
        () =>
          ingestManageRegistrationsHtml(
            db as unknown as admin.firestore.Firestore,
            TENANT,
            "<html><body>nothing here</body></html>",
            FINAL_URL
          ),
        /unknownNoRows/i
      );
    });
  }
);

// --- syncLarpManagerCharactersByEmail wrapper: cache short-circuit only ---
//
// The HTTP-touching path of the wrapper is exercised end-to-end against
// the live LM emulator by capture-lm-fixture / integration runs. The
// unit test below only pins the cache-skip contract; the actual fetch +
// ingest path is covered by the ingest tests above and would otherwise
// require a full Django login mock.

test(
  "syncLarpManagerCharactersByEmail: returns skippedCache when meta is fresh",
  async () => {
    const freshTs = {
      toMillis: () => Date.now() - 1000,
      toDate: () => new Date(),
    };
    const { db } = makeFirestoreStub([
      {
        path: `${BASE}/${CHARACTERS_BY_EMAIL_META_DOC}`,
        data: { lastSyncedAt: freshTs, rowCount: 7, syncRunId: "prior" },
      },
    ]);

    const result = await syncLarpManagerCharactersByEmail(
      db as unknown as admin.firestore.Firestore,
      TENANT,
      {
        baseUrl: "https://lm.example",
        eventSlug: "evt1",
        username: "svc",
        password: "x",
      }
    );
    assert.equal(result.skippedCache, true);
    assert.equal(result.rowCount, 7);
    assert.equal(result.syncRunId, "prior");
  }
);
