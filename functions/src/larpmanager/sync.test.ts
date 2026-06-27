/**
 * Unit tests for `runLarpManagerSync` — Task 009 wiring of the
 * per-character LM HTML sheet scrape into the existing export +
 * abilities + inventory pipeline.
 *
 * Strategy:
 *   - Stub Firestore via `makeFirestoreStub` (writes captured in an
 *     in-memory `store` Map).
 *   - Mock `globalThis.fetch` with a URL router that dispatches
 *     /export/char/, /character/{uuid}/inventory/json/,
 *     /character/{uuid}/abilities/json/, and /character/{uuid}/ HTML
 *     sheet endpoints independently per character.
 *   - Use `sessionId` in `LarpManagerSyncConfig` so
 *     `establishLarpManagerSession` short-circuits (no Django
 *     login dance required in the mock).
 *
 * These tests pin Task 009's acceptance criteria:
 *   1. Happy path — `sheet` lands on the mirror doc, `sheetsFetched`
 *      increments, `errors` stays empty.
 *   2. Per-character isolation — a sheet HTTP failure for char A
 *      records an `errors[]` entry tagged with the docId, does NOT
 *      bump `sheetsFetched` for A, and STILL lets char B's sheet
 *      land + count.
 *   3. Parse-error isolation — when `parseCharacterSheetHtml` throws
 *      `CharacterSheetParseError`, the docId-prefixed message surfaces
 *      in `errors[]` AND the row's export/abilities/inventory are
 *      still committed (`detailsFetched` still increments for that
 *      character).
 *   4. `LarpManagerSyncResult` exposes `sheetsFetched` typed as
 *      `number` (compile-pinned via a literal object construction —
 *      no `any` casts).
 *
 * (Task 012 / ADR 0001 removed the `fetchDetails: false short-circuits
 * the sheet fetch` test that used to live here — admin sync is now
 * always full and the toggle no longer exists.)
 *
 * No network. No real Firestore. No firebase-admin app init required
 * — `admin.firestore.FieldValue.serverTimestamp()` is a pure sentinel
 * factory on the namespace and the stub stores it as-is.
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";

import { runLarpManagerSync } from "./sync";
import type { LarpManagerSyncConfig, LarpManagerSyncResult } from "./types";
import { gameEventBase } from "../gameTenant";
import {
  makeFirestoreStub,
  withCapturedLogs,
} from "../_testing/firestoreStub";

const TENANT = { instanceId: "g1", eventSlug: "crucible" };
const BASE = gameEventBase(TENANT);
const MIRROR_COLL = `${BASE}/larpManagerMirrorChars`;
const SUMMARY_DOC = `${BASE}/larpManagerMirrorMeta/summary`;

const CONFIG: LarpManagerSyncConfig = {
  baseUrl: "https://lm.example",
  eventSlug: "crucible",
  sessionId: "stub-session-id",
};

/**
 * Synthetic LM character-sheet HTML that `parseCharacterSheetHtml`
 * accepts: has <body>, a `.character` container, and two
 * `<b>Label:</b>Value` rows.
 */
const SHEET_HTML_OK = [
  "<!DOCTYPE html>",
  "<html><body>",
  '  <div class="character">',
  '    <div class="presentation">',
  '      <div class="first">',
  '        <div class="go-inline"><b>Player:&nbsp;</b>Player 1</div>',
  '        <div class="go-inline"><b>Race:&nbsp;</b>Human (Fire Affinity)</div>',
  "      </div>",
  "    </div>",
  "  </div>",
  "</body></html>",
].join("\n");

/**
 * HTML that has <body> but NO `.character` container — drives
 * `parseCharacterSheetHtml` to throw `CharacterSheetParseError`.
 */
const SHEET_HTML_UNPARSEABLE =
  "<!DOCTYPE html><html><body>" +
  '<form action="/login/">login</form>' +
  "</body></html>";

// --- fetch mocking helpers ------------------------------------------------

interface MockResponseInit {
  status?: number;
  body?: string;
  url?: string;
  contentType?: string;
}

function mockResponse(init: MockResponseInit = {}): Response {
  const headers = new Headers();
  const setCookies: string[] = [];
  (headers as unknown as { getSetCookie: () => string[] }).getSetCookie =
    () => setCookies;
  if (init.contentType) headers.set("content-type", init.contentType);
  const status = init.status ?? 200;
  const body = init.body ?? "";
  const res = new Response(body, { status, headers });
  if (init.url !== undefined) {
    Object.defineProperty(res, "url", {
      value: init.url,
      writable: false,
      configurable: true,
    });
  }
  return res;
}

type FetchFn = typeof fetch;

type RouteHandler = (url: string, init: RequestInit | undefined) => Response;

interface RouterOptions {
  exportJson?: Record<string, unknown>;
  /** Map of characterUuid → per-character HTTP responder. Each
   *  responder gets the endpoint kind so a single character can fail
   *  on `sheet` while succeeding on `inventory`/`abilities`. */
  perCharacter?: Record<string, CharacterEndpointHandler>;
  /** Optional fallback for an unknown URL (defaults to throwing). */
  fallback?: RouteHandler;
}

type CharacterEndpointKind = "inventory" | "abilities" | "sheet";

interface CharacterEndpointHandler {
  inventory?: (url: string) => Response;
  abilities?: (url: string) => Response;
  sheet?: (url: string) => Response;
}

interface CallLog {
  url: string;
  method: string;
}

function jsonResponse(payload: unknown, url: string): Response {
  return mockResponse({
    status: 200,
    body: JSON.stringify(payload),
    url,
    contentType: "application/json",
  });
}

function htmlResponse(html: string, url: string, status = 200): Response {
  return mockResponse({
    status,
    body: html,
    url,
    contentType: "text/html",
  });
}

function makeRouter(opts: RouterOptions): {
  fetch: FetchFn;
  calls: CallLog[];
} {
  const calls: CallLog[] = [];
  const perChar = opts.perCharacter ?? {};
  const exportJson = opts.exportJson ?? {};
  const fallback: RouteHandler =
    opts.fallback ??
    ((url) => {
      throw new Error(`Unexpected request: ${url}`);
    });

  const handler: FetchFn = async (input, init) => {
    const url =
      typeof input === "string"
        ? input
        : input instanceof URL
          ? input.toString()
          : (input as Request).url;
    const method = (init?.method ?? "GET").toUpperCase();
    calls.push({ url, method });

    if (/\/export\/char\/?$/.test(url)) {
      return jsonResponse(exportJson, url);
    }

    const perCharMatch = url.match(
      /\/character\/([^/]+)\/(?:(inventory|abilities)\/json\/?$)?$/
    );
    if (perCharMatch) {
      const uuid = perCharMatch[1]!;
      const kindMaybe = perCharMatch[2] as
        | "inventory"
        | "abilities"
        | undefined;
      const kind: CharacterEndpointKind = kindMaybe ?? "sheet";
      const charHandlers = perChar[uuid];
      const fn = charHandlers?.[kind];
      if (fn) return fn(url);
      return fallback(url, init);
    }

    return fallback(url, init);
  };

  return { fetch: handler, calls };
}

async function withMockedFetch(
  handler: FetchFn,
  body: () => Promise<void>
): Promise<void> {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = handler;
  try {
    await body();
  } finally {
    globalThis.fetch = originalFetch;
  }
}

/** Build a minimal valid /export/char/ payload. Each entry is keyed
 *  by the number (as string) and has uuid + name. */
function exportEntry(opts: { number: number; uuid: string; name: string }) {
  return {
    number: opts.number,
    uuid: opts.uuid,
    name: opts.name,
    teaser: `${opts.name} teaser`,
  };
}

// --- Tests ----------------------------------------------------------------

test(
  "runLarpManagerSync (Task 009 happy path): writes parsed sheet onto the " +
    "mirror doc, increments sheetsFetched, errors stays empty",
  async () => {
    const uuid = "char00000aaa";
    const exportJson = {
      "1": exportEntry({ number: 1, uuid, name: "Heldrek" }),
    };
    const { fetch: mockFetch } = makeRouter({
      exportJson,
      perCharacter: {
        [uuid]: {
          inventory: (u) => jsonResponse({ items: [] }, u),
          abilities: (u) => jsonResponse({ abilities: [] }, u),
          sheet: (u) => htmlResponse(SHEET_HTML_OK, u),
        },
      },
    });

    const { db, store } = makeFirestoreStub();

    let result: LarpManagerSyncResult | undefined;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        result = await runLarpManagerSync(
          db as unknown as admin.firestore.Firestore,
          TENANT,
          CONFIG
        );
      });
    });

    assert.ok(result, "runLarpManagerSync should resolve");
    assert.deepEqual(result!.errors, [], "no errors on the happy path");
    assert.equal(
      result!.sheetsFetched,
      1,
      "sheetsFetched should increment by 1 for the single successful parse"
    );
    assert.equal(
      result!.detailsFetched,
      1,
      "detailsFetched still counts the inventory+abilities pair (unchanged behaviour)"
    );

    const doc = store.get(`${MIRROR_COLL}/${uuid}`);
    assert.ok(doc, `mirror doc must exist at ${MIRROR_COLL}/${uuid}`);
    const sheet = (doc as { sheet?: unknown }).sheet as
      | {
          sections: Array<{
            label: string;
            rows: Array<{ label: string; value: string }>;
          }>;
        }
      | undefined;
    assert.ok(sheet, "row.sheet must be written from parseCharacterSheetHtml");
    assert.ok(
      Array.isArray(sheet!.sections) && sheet!.sections.length >= 1,
      "sheet.sections must be a non-empty array"
    );
    const firstSection = sheet!.sections[0]!;
    assert.deepEqual(
      firstSection.rows.map((r) => [r.label, r.value]),
      [
        ["Player", "Player 1"],
        ["Race", "Human (Fire Affinity)"],
      ],
      "parsed rows must match the synthetic stat block in source order"
    );

    const summary = store.get(SUMMARY_DOC);
    assert.ok(summary, "summary doc still written");
    assert.equal(
      (summary as { lastOk: boolean }).lastOk,
      true,
      "lastOk true when no errors"
    );
  }
);

test(
  "runLarpManagerSync (Task 009 per-character isolation): a sheet HTTP " +
    "failure for char A records an errors[] entry tagged with A's docId, " +
    "does NOT bump sheetsFetched for A, and char B still gets its sheet " +
    "written and counted",
  async () => {
    const uuidA = "charaaaaa001";
    const uuidB = "charbbbbb002";
    const exportJson = {
      "1": exportEntry({ number: 1, uuid: uuidA, name: "Alpha" }),
      "2": exportEntry({ number: 2, uuid: uuidB, name: "Bravo" }),
    };
    const { fetch: mockFetch, calls } = makeRouter({
      exportJson,
      perCharacter: {
        [uuidA]: {
          inventory: (u) => jsonResponse({ items: [] }, u),
          abilities: (u) => jsonResponse({ abilities: [] }, u),
          sheet: (u) => htmlResponse("Not Found", u, 404),
        },
        [uuidB]: {
          inventory: (u) => jsonResponse({ items: [] }, u),
          abilities: (u) => jsonResponse({ abilities: [] }, u),
          sheet: (u) => htmlResponse(SHEET_HTML_OK, u),
        },
      },
    });

    const { db, store } = makeFirestoreStub();

    let result: LarpManagerSyncResult | undefined;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        result = await runLarpManagerSync(
          db as unknown as admin.firestore.Firestore,
          TENANT,
          CONFIG
        );
      });
    });

    assert.ok(result, "runLarpManagerSync should resolve");
    assert.equal(
      result!.sheetsFetched,
      1,
      "exactly one sheet (char B) should be counted; A's sheet failed"
    );
    assert.equal(
      result!.detailsFetched,
      2,
      "detailsFetched (inventory+abilities) still counts both characters"
    );
    assert.equal(
      result!.errors.length,
      1,
      "exactly one errors[] entry — the sheet failure for char A"
    );
    const errA = result!.errors[0]!;
    assert.ok(
      errA.startsWith(`${uuidA}:`),
      `errors[0] must start with "${uuidA}:", got: ${errA}`
    );

    const docA = store.get(`${MIRROR_COLL}/${uuidA}`) as Record<string, unknown>;
    assert.ok(docA, "char A mirror doc still written");
    assert.ok(
      docA["inventory"] !== undefined && docA["abilities"] !== undefined,
      "char A's inventory + abilities still commit despite sheet failure"
    );
    assert.equal(
      (docA as { sheet?: unknown }).sheet,
      undefined,
      "char A's sheet must NOT be written when the sheet HTTP fetch failed"
    );

    const docB = store.get(`${MIRROR_COLL}/${uuidB}`) as Record<string, unknown>;
    assert.ok(docB, "char B mirror doc written");
    assert.ok(
      (docB as { sheet?: { sections?: unknown[] } }).sheet?.sections !==
        undefined,
      "char B's sheet must be written from parseCharacterSheetHtml"
    );

    const sheetUrlsHit = calls
      .filter((c) => c.method === "GET")
      .map((c) => c.url)
      .filter((u) => /\/character\/[^/]+\/$/.test(u));
    assert.ok(
      sheetUrlsHit.some((u) => u.includes(uuidA)),
      "char A's sheet URL should have been attempted"
    );
    assert.ok(
      sheetUrlsHit.some((u) => u.includes(uuidB)),
      "char B's sheet URL should have been attempted"
    );
  }
);

test(
  "runLarpManagerSync (Task 009 parse-error isolation): when " +
    "parseCharacterSheetHtml throws CharacterSheetParseError, the docId-" +
    "prefixed message surfaces in errors[], the rest of the row " +
    "(export/abilities/inventory) STILL commits, and detailsFetched still " +
    "counts that character",
  async () => {
    const uuid = "char00000ccc";
    const exportJson = {
      "1": exportEntry({ number: 1, uuid, name: "Drifter" }),
    };
    const { fetch: mockFetch } = makeRouter({
      exportJson,
      perCharacter: {
        [uuid]: {
          inventory: (u) => jsonResponse({ items: [] }, u),
          abilities: (u) => jsonResponse({ abilities: [] }, u),
          sheet: (u) => htmlResponse(SHEET_HTML_UNPARSEABLE, u),
        },
      },
    });

    const { db, store } = makeFirestoreStub();

    let result: LarpManagerSyncResult | undefined;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        result = await runLarpManagerSync(
          db as unknown as admin.firestore.Firestore,
          TENANT,
          CONFIG
        );
      });
    });

    assert.ok(result, "runLarpManagerSync should resolve");
    assert.equal(
      result!.sheetsFetched,
      0,
      "sheetsFetched must NOT increment when the parser throws"
    );
    assert.equal(
      result!.detailsFetched,
      1,
      "inventory+abilities still landed, so detailsFetched still counts"
    );
    assert.equal(result!.errors.length, 1);
    const err = result!.errors[0]!;
    assert.ok(
      err.startsWith(`${uuid}:`),
      `errors[0] must be prefixed with the docId, got: ${err}`
    );
    assert.ok(
      /character-sheet|scaffolding|character container/i.test(err),
      `errors[0] should surface the CharacterSheetParseError message, got: ${err}`
    );

    const doc = store.get(`${MIRROR_COLL}/${uuid}`) as Record<string, unknown>;
    assert.ok(doc, "mirror doc still written even though sheet parse failed");
    assert.ok(doc["export"], "export still committed");
    assert.ok(doc["abilities"], "abilities still committed");
    assert.ok(doc["inventory"], "inventory still committed");
    assert.equal(
      (doc as { sheet?: unknown }).sheet,
      undefined,
      "sheet must NOT be written when parser threw"
    );
  }
);

// Task 012 / ADR 0001: the `runLarpManagerSync (Task 009):
// fetchDetails:false skips the sheet fetch entirely and sheetsFetched
// stays 0` test that previously lived here has been removed because the
// scenario it tested no longer exists — admin sync is always full.

test(
  "LarpManagerSyncResult (Task 009): the type exposes sheetsFetched as a " +
    "number — compile-pinned via a literal construction without any casts",
  () => {
    const r: LarpManagerSyncResult = {
      characterCount: 0,
      detailsFetched: 0,
      sheetsFetched: 0,
      exportSha256: "",
      errors: [],
    };
    assert.equal(typeof r.sheetsFetched, "number");
    assert.equal(r.sheetsFetched, 0);
  }
);

// --- Task 011: teaser HTML→plain-text on write ----------------------------
//
// `runLarpManagerSync` should pipe `ch.teaser` through `htmlToPlainText`
// before writing it as the mirror doc's TOP-LEVEL `teaser` field, and
// omit that field entirely when the strip returns `undefined`. The raw
// LM HTML is preserved verbatim inside the row's `export.teaser` so
// future consumers of the bulk-export dump still see what LM emitted.

// Task 012 / ADR 0001 note: the export entries below intentionally
// have NO `uuid` field. The teaser-projection logic is independent of
// uuid, and Task 012 removed the `fetchDetails` gate so any
// uuid-bearing entry now triggers a per-character HTTP round-trip
// that these focused teaser tests don't want to mock. Without a uuid
// the per-character fetch is skipped and the row's docId falls back
// to `n{numKey}` per sync.ts.

test(
  "runLarpManagerSync (Task 011): teaser HTML in the LM export becomes " +
    "plain text on the mirror doc; row.export.teaser keeps the raw HTML",
  async () => {
    const exportJson = {
      "1": {
        number: 1,
        name: "Heldrek",
        teaser: "<p>Fire Mage</p>",
      },
    };
    const { fetch: mockFetch } = makeRouter({ exportJson });

    const { db, store } = makeFirestoreStub();

    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        await runLarpManagerSync(
          db as unknown as admin.firestore.Firestore,
          TENANT,
          CONFIG
        );
      });
    });

    const doc = store.get(`${MIRROR_COLL}/n1`) as Record<string, unknown>;
    assert.ok(doc, "mirror doc must exist");
    assert.equal(
      doc["teaser"],
      "Fire Mage",
      "top-level teaser must be the plain-text projection",
    );
    const exp = doc["export"] as Record<string, unknown>;
    assert.equal(
      exp["teaser"],
      "<p>Fire Mage</p>",
      "row.export.teaser must keep the verbatim raw HTML from LM",
    );
  }
);

test(
  "runLarpManagerSync (Task 011): a teaser that strips to empty " +
    "(<p>   </p>) results in NO top-level teaser key on the mirror doc",
  async () => {
    const exportJson = {
      "1": {
        number: 1,
        name: "Heldrek",
        teaser: "<p>   </p>",
      },
    };
    const { fetch: mockFetch } = makeRouter({ exportJson });

    const { db, store } = makeFirestoreStub();

    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        await runLarpManagerSync(
          db as unknown as admin.firestore.Firestore,
          TENANT,
          CONFIG
        );
      });
    });

    const doc = store.get(`${MIRROR_COLL}/n1`) as Record<string, unknown>;
    assert.ok(doc, "mirror doc must exist");
    assert.equal(
      "teaser" in doc,
      false,
      "top-level teaser key must be OMITTED (not null, not '') when the " +
        "strip yields no displayable text",
    );
    const exp = doc["export"] as Record<string, unknown>;
    assert.equal(
      exp["teaser"],
      "<p>   </p>",
      "row.export.teaser still keeps the raw HTML verbatim",
    );
  }
);

test(
  "runLarpManagerSync (Task 011): an LM export entry with no teaser " +
    "key at all results in NO top-level teaser key on the mirror doc",
  async () => {
    const exportJson = {
      "1": {
        number: 1,
        name: "Heldrek",
        // teaser intentionally omitted.
      },
    };
    const { fetch: mockFetch } = makeRouter({ exportJson });

    const { db, store } = makeFirestoreStub();

    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        await runLarpManagerSync(
          db as unknown as admin.firestore.Firestore,
          TENANT,
          CONFIG
        );
      });
    });

    const doc = store.get(`${MIRROR_COLL}/n1`) as Record<string, unknown>;
    assert.ok(doc, "mirror doc must exist");
    assert.equal(
      "teaser" in doc,
      false,
      "top-level teaser key must be OMITTED when the LM export entry has " +
        "no teaser at all",
    );
  }
);

// --- Task 012: remove fetchDetails toggle; admin sync is always full ------
//
// After Task 012 there is exactly one sync mode: always full. Every
// uuid-bearing character gets its inventory, abilities, AND parsed HTML
// sheet fetched on every admin/scheduled sync. The `fetchDetails`
// toggle is gone from `LarpManagerSyncConfig`, from
// `runLarpManagerSync`'s gating logic, and from the
// `larpManagerMirrorMeta/summary` doc write.

test(
  "runLarpManagerSync (Task 012): a uuid-bearing character ALWAYS " +
    "triggers all three per-character endpoints (inventory, abilities, " +
    "sheet) — no fetchDetails toggle required — the mirror doc gains " +
    "inventory + abilities + sheet, detailsFetched === 1, sheetsFetched === 1",
  async () => {
    const uuid = "char00012aaa";
    const exportJson = {
      "1": exportEntry({ number: 1, uuid, name: "Vanessa" }),
    };
    const { fetch: mockFetch, calls } = makeRouter({
      exportJson,
      perCharacter: {
        [uuid]: {
          inventory: (u) => jsonResponse({ items: [] }, u),
          abilities: (u) => jsonResponse({ abilities: [] }, u),
          sheet: (u) => htmlResponse(SHEET_HTML_OK, u),
        },
      },
    });

    const { db, store } = makeFirestoreStub();

    let result: LarpManagerSyncResult | undefined;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        result = await runLarpManagerSync(
          db as unknown as admin.firestore.Firestore,
          TENANT,
          CONFIG,
        );
      });
    });

    assert.ok(result, "runLarpManagerSync should resolve");
    assert.equal(
      result!.detailsFetched,
      1,
      "detailsFetched must be 1 (inventory+abilities pair counted) " +
        "with no fetchDetails toggle",
    );
    assert.equal(
      result!.sheetsFetched,
      1,
      "sheetsFetched must be 1 with no fetchDetails toggle",
    );
    assert.deepEqual(result!.errors, [], "no errors expected on happy path");

    const inventoryCalls = calls.filter((c) =>
      /\/character\/[^/]+\/inventory\//.test(c.url),
    );
    const abilitiesCalls = calls.filter((c) =>
      /\/character\/[^/]+\/abilities\//.test(c.url),
    );
    const sheetCalls = calls.filter(
      (c) => /\/character\/[^/]+\/$/.test(c.url) && c.url.includes(uuid),
    );
    assert.equal(
      inventoryCalls.length,
      1,
      "exactly one GET to /character/{uuid}/inventory/",
    );
    assert.equal(
      abilitiesCalls.length,
      1,
      "exactly one GET to /character/{uuid}/abilities/",
    );
    assert.equal(
      sheetCalls.length,
      1,
      "exactly one GET to /character/{uuid}/ (HTML sheet)",
    );

    const doc = store.get(`${MIRROR_COLL}/${uuid}`) as Record<string, unknown>;
    assert.ok(doc, `mirror doc must exist at ${MIRROR_COLL}/${uuid}`);
    assert.ok(doc["inventory"], "row.inventory must be written");
    assert.ok(doc["abilities"], "row.abilities must be written");
    const sheet = (doc as { sheet?: { sections?: unknown[] } }).sheet;
    assert.ok(
      sheet?.sections !== undefined,
      "row.sheet.sections must be written from parseCharacterSheetHtml",
    );
  }
);

test(
  "runLarpManagerSync (Task 012): a character with NO uuid does NOT " +
    "trigger any per-character endpoints, and the mirror doc has no " +
    "sheet / inventory / abilities field (uuid guard still in place)",
  async () => {
    const exportJson = {
      "42": {
        number: 42,
        name: "Nameless",
        teaser: "ghost",
        // uuid intentionally omitted — character has no per-character
        // endpoint to hit.
      },
    };
    const { fetch: mockFetch, calls } = makeRouter({ exportJson });

    const { db, store } = makeFirestoreStub();

    let result: LarpManagerSyncResult | undefined;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        result = await runLarpManagerSync(
          db as unknown as admin.firestore.Firestore,
          TENANT,
          CONFIG,
        );
      });
    });

    assert.ok(result, "runLarpManagerSync should resolve");
    assert.deepEqual(
      result!.errors,
      [],
      "uuid-less character must not produce any errors (no per-character " +
        "fetch attempted)",
    );
    assert.equal(
      result!.detailsFetched,
      0,
      "detailsFetched must be 0 for a uuid-less character",
    );
    assert.equal(
      result!.sheetsFetched,
      0,
      "sheetsFetched must be 0 for a uuid-less character",
    );

    const perCharCalls = calls.filter((c) => /\/character\//.test(c.url));
    assert.equal(
      perCharCalls.length,
      0,
      "no per-character endpoint may be hit for a uuid-less character",
    );

    const doc = store.get(`${MIRROR_COLL}/n42`) as Record<string, unknown>;
    assert.ok(doc, "mirror doc must still be written (export-only row)");
    assert.equal(
      (doc as { sheet?: unknown }).sheet,
      undefined,
      "no sheet field for uuid-less character",
    );
    assert.equal(
      (doc as { inventory?: unknown }).inventory,
      undefined,
      "no inventory field for uuid-less character",
    );
    assert.equal(
      (doc as { abilities?: unknown }).abilities,
      undefined,
      "no abilities field for uuid-less character",
    );
  }
);

test(
  "runLarpManagerSync (Task 012): the larpManagerMirrorMeta/summary doc " +
    "written at the end of a sync has NO fetchDetails field",
  async () => {
    const uuid = "char00012ccc";
    const exportJson = {
      "1": exportEntry({ number: 1, uuid, name: "Zoe" }),
    };
    const { fetch: mockFetch } = makeRouter({
      exportJson,
      perCharacter: {
        [uuid]: {
          inventory: (u) => jsonResponse({ items: [] }, u),
          abilities: (u) => jsonResponse({ abilities: [] }, u),
          sheet: (u) => htmlResponse(SHEET_HTML_OK, u),
        },
      },
    });

    const { db, store } = makeFirestoreStub();

    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        await runLarpManagerSync(
          db as unknown as admin.firestore.Firestore,
          TENANT,
          CONFIG,
        );
      });
    });

    const summary = store.get(SUMMARY_DOC) as Record<string, unknown>;
    assert.ok(summary, "summary doc must be written");
    assert.equal(
      "fetchDetails" in summary,
      false,
      "after Task 012 the summary doc must NOT include a fetchDetails key " +
        "(the field is removed from the write entirely)",
    );
    assert.equal(typeof summary["exportSha256"], "string");
    assert.equal(typeof summary["characterCount"], "number");
  }
);

// --- Task 014: sheet.body write-through ----------------------------------
//
// `runLarpManagerSync` already writes `row.sheet = parseCharacterSheetHtml(html)`
// for each character. Task 014 adds an optional `body` field to that
// projection. This test pins that when the per-character HTML carries a
// `<div class="sheet">` block with `<h3>` ability groups, the mirror doc
// the sync writes has `sheet.body.abilityGroups` non-empty — i.e. the
// new field rides through `parseCharacterSheetHtml → row.sheet` to
// Firestore with NO changes to `sync.ts`.

const SHEET_HTML_WITH_BODY = [
  "<!DOCTYPE html>",
  "<html><body>",
  '  <div class="character">',
  '    <div class="presentation">',
  '      <div class="first">',
  '        <div class="go-inline"><b>Player:&nbsp;</b>Player 1</div>',
  "      </div>",
  "    </div>",
  '    <div class="sheet">',
  "      <h2>Abilities</h2>",
  "      <h3>Common Skills</h3>",
  '      <table class="mob abilities">',
  "        <tbody><tr>",
  "          <th><h4>Block (1)</h4></th>",
  "          <td><p>Block one attack.</p></td>",
  "        </tr></tbody>",
  "      </table>",
  "    </div>",
  "  </div>",
  "</body></html>",
].join("\n");

test(
  "runLarpManagerSync (Task 014): when the per-character HTML carries a " +
    "<div class=\"sheet\"> block with <h3> ability groups, the mirror doc " +
    "has sheet.body.abilityGroups non-empty (write-through of the new " +
    "parser field, no sync.ts code change)",
  async () => {
    const uuid = "char00014aaa";
    const exportJson = {
      "1": exportEntry({ number: 1, uuid, name: "Heldrek" }),
    };
    const { fetch: mockFetch } = makeRouter({
      exportJson,
      perCharacter: {
        [uuid]: {
          inventory: (u) => jsonResponse({ items: [] }, u),
          abilities: (u) => jsonResponse({ abilities: [] }, u),
          sheet: (u) => htmlResponse(SHEET_HTML_WITH_BODY, u),
        },
      },
    });

    const { db, store } = makeFirestoreStub();

    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        await runLarpManagerSync(
          db as unknown as admin.firestore.Firestore,
          TENANT,
          CONFIG,
        );
      });
    });

    const doc = store.get(`${MIRROR_COLL}/${uuid}`) as Record<string, unknown>;
    assert.ok(doc, "mirror doc must exist");
    const sheet = doc["sheet"] as
      | {
          body?: {
            abilityGroups?: Array<{ label: string; abilities: unknown[] }>;
          };
        }
      | undefined;
    assert.ok(sheet, "row.sheet must be populated");
    assert.ok(
      sheet!.body,
      "sheet.body must be populated when the HTML carries a body block",
    );
    const groups = sheet!.body!.abilityGroups ?? [];
    assert.ok(
      groups.length >= 1,
      "sheet.body.abilityGroups must be non-empty when the HTML has at " +
        "least one <h3> group",
    );
    assert.equal(
      groups[0]!.label,
      "Common Skills",
      "first group label rides through verbatim",
    );
    assert.equal(
      groups[0]!.abilities.length,
      1,
      "the single <h3>'s row count is preserved end-to-end",
    );
  }
);
