/**
 * Unit tests for the Task 013 player-driven per-character refresh
 * callable. The implementation lives in `syncMyCharacter.ts` and is
 * exposed to the client as `syncMyLarpManagerCharacterCallable` (wired
 * up in `functions/src/index.ts`).
 *
 * Test strategy mirrors `sync.test.ts`:
 *   - Firestore is stubbed via `makeFirestoreStub` (in-memory `store`
 *     map; writes are captured per path).
 *   - `globalThis.fetch` is mocked with a URL router so each per-
 *     character endpoint can succeed or fail independently.
 *   - `LarpManagerSyncConfig.sessionId` short-circuits
 *     `establishLarpManagerSession` so no Django login dance is needed.
 *   - The integration config loader is injected so we don't touch the
 *     real Secret Manager (which is reachable only in deployed
 *     functions, not in `node --test`).
 *
 * These tests pin every requirement listed in `docs/tasks/ready/
 * 013-coder.md`:
 *   1. Happy path — owner refreshes their own character; all three
 *      per-character endpoints called serially; mirror doc gains
 *      `sheet`, `inventory`, `abilities`, `lastSyncedAt`, and
 *      `lastUserSyncByUid.{uid}`; callable returns `{ ok: true }`.
 *   2. `request.auth?.uid` missing → `HttpsError("unauthenticated")`;
 *      no HTTP fetches issued, no mirror writes.
 *   3. `characterUuid` invalid (missing / wrong shape) →
 *      `HttpsError("invalid-argument")`; no HTTP fetches issued.
 *   4. `${base}/characters/{uuid}` doc missing →
 *      `HttpsError("not-found")`; no HTTP fetches issued.
 *   5. Owner mismatch → `HttpsError("permission-denied")`; per-
 *      character endpoints NOT called; mirror doc NOT updated.
 *   6. Integration config missing → `HttpsError("failed-precondition")`.
 *   7. ONE of the three per-character fetches throws → callable
 *      returns `{ ok: false, error: "Could not refresh: <message>" }`
 *      (NOT throws), and the mirror doc STILL gets
 *      `lastUserSyncByUid.{uid}` so a future rate-limit can see the
 *      attempt was made.
 *   8. Merge semantics — pre-existing `export` / `name` / `number` /
 *      `teaser` fields on the mirror doc are PRESERVED across a
 *      successful refresh; refresh does NOT clobber them to undefined.
 *
 * No real Firestore. No real HTTP. No real Secret Manager.
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";
import type * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import {
  runSyncMyLarpManagerCharacter,
  type SyncMyCharacterBody,
  type SyncMyCharacterDeps,
} from "./syncMyCharacter";
import type { LarpManagerSyncConfig } from "./types";
import { gameEventBase, type GameTenant } from "../gameTenant";
import {
  makeFirestoreStub,
  withCapturedLogs,
} from "../_testing/firestoreStub";

const TENANT: GameTenant = { instanceId: "g1", eventSlug: "crucible" };
const BASE = gameEventBase(TENANT);
const MIRROR_COLL = `${BASE}/larpManagerMirrorChars`;
const CHARS_COLL = `${BASE}/characters`;

const UID = "user-alpha";
const OTHER_UID = "user-mallory";
const VALID_UUID = "char00013aaa";

const CONFIG: LarpManagerSyncConfig = {
  baseUrl: "https://lm.example",
  eventSlug: "crucible",
  sessionId: "stub-session-id",
  fetchDetails: true,
};

// --- fetch mocking helpers (mirrors sync.test.ts) -------------------------

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

function makeRouter(opts: {
  perCharacter?: Record<string, CharacterEndpointHandler>;
  fallback?: RouteHandler;
}): { fetch: FetchFn; calls: CallLog[] } {
  const calls: CallLog[] = [];
  const perChar = opts.perCharacter ?? {};
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

    const perCharMatch = url.match(
      /\/character\/([^/]+)\/(?:(inventory|abilities)\/json\/?$)?$/
    );
    if (perCharMatch) {
      const uuid = perCharMatch[1]!;
      const kindMaybe = perCharMatch[2] as
        | "inventory"
        | "abilities"
        | undefined;
      const kind = kindMaybe ?? "sheet";
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

// --- request / deps builders ----------------------------------------------

function makeRequest(opts: {
  uid?: string | null;
  data: SyncMyCharacterBody;
}): CallableRequest<SyncMyCharacterBody> {
  const auth =
    opts.uid && opts.uid.length > 0
      ? ({ uid: opts.uid, token: {} } as unknown as CallableRequest<SyncMyCharacterBody>["auth"])
      : undefined;
  return {
    data: opts.data,
    auth,
    acceptsStreaming: false,
    rawRequest: {} as unknown as CallableRequest<SyncMyCharacterBody>["rawRequest"],
  } as CallableRequest<SyncMyCharacterBody>;
}

function makeDeps(opts: {
  db: ReturnType<typeof makeFirestoreStub>["db"];
  config?: LarpManagerSyncConfig | null;
}): SyncMyCharacterDeps {
  return {
    db: opts.db as unknown as admin.firestore.Firestore,
    projectId: "test-project",
    loadConfig: async () =>
      opts.config === undefined ? CONFIG : opts.config,
  };
}

function seedOwnedCharacter(
  store: Map<string, Record<string, unknown>>,
  opts: { uuid: string; ownerId: string }
): void {
  store.set(`${CHARS_COLL}/${opts.uuid}`, {
    ownerId: opts.ownerId,
    larpManagerUuid: opts.uuid,
    source: "larpmanager",
  });
}

// --- Tests ----------------------------------------------------------------

test(
  "Task 013 happy path: owner of an LM character can refresh just their " +
    "character — all three per-character endpoints are called serially, " +
    "the mirror doc gains sheet/inventory/abilities/lastSyncedAt and a " +
    "per-uid timestamp under lastUserSyncByUid, and the callable returns " +
    "{ok: true}",
  async () => {
    const { db, store, writes } = makeFirestoreStub();
    seedOwnedCharacter(store, { uuid: VALID_UUID, ownerId: UID });

    const { fetch: mockFetch, calls } = makeRouter({
      perCharacter: {
        [VALID_UUID]: {
          inventory: (u) => jsonResponse({ items: ["sword"] }, u),
          abilities: (u) => jsonResponse({ abilities: ["block"] }, u),
          sheet: (u) => htmlResponse(SHEET_HTML_OK, u),
        },
      },
    });

    let result: { ok: boolean; error?: string } | undefined;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        result = await runSyncMyLarpManagerCharacter(
          makeDeps({ db }),
          makeRequest({
            uid: UID,
            data: {
              gameId: `${TENANT.instanceId}::${TENANT.eventSlug}`,
              characterUuid: VALID_UUID,
            },
          })
        );
      });
    });

    assert.deepEqual(
      result,
      { ok: true },
      "callable resolves to {ok: true} on happy path"
    );

    // Per-character fetch posture: SERIAL, one inventory, one abilities,
    // one sheet, all targeting the requested character only.
    const perCharGets = calls.filter(
      (c) =>
        c.method === "GET" && /\/character\/[^/]+\//.test(c.url)
    );
    const inventoryHits = perCharGets.filter((c) =>
      /\/inventory\/json\/?$/.test(c.url)
    );
    const abilitiesHits = perCharGets.filter((c) =>
      /\/abilities\/json\/?$/.test(c.url)
    );
    const sheetHits = perCharGets.filter((c) =>
      /\/character\/[^/]+\/$/.test(c.url)
    );
    assert.equal(inventoryHits.length, 1, "inventory endpoint hit once");
    assert.equal(abilitiesHits.length, 1, "abilities endpoint hit once");
    assert.equal(sheetHits.length, 1, "sheet HTML endpoint hit once");
    for (const c of perCharGets) {
      assert.ok(
        c.url.includes(VALID_UUID),
        `per-character endpoint must target ${VALID_UUID}, got ${c.url}`
      );
    }
    // Bulk /export/char/ MUST NOT be called — player refresh re-pulls
    // only the per-character endpoints. This is the whole point of the
    // task: do less work than the admin sync.
    assert.equal(
      calls.filter((c) => /\/export\/char\//.test(c.url)).length,
      0,
      "bulk /export/char/ must NOT be called by the player-scoped sync"
    );

    const doc = store.get(`${MIRROR_COLL}/${VALID_UUID}`) as Record<
      string,
      unknown
    >;
    assert.ok(doc, `mirror doc must exist at ${MIRROR_COLL}/${VALID_UUID}`);
    assert.ok(doc["inventory"], "inventory must be on the mirror doc");
    assert.ok(doc["abilities"], "abilities must be on the mirror doc");
    assert.ok(doc["sheet"], "parsed sheet must be on the mirror doc");
    assert.ok(
      doc["lastSyncedAt"],
      "lastSyncedAt sentinel must be written on the mirror doc"
    );
    const lastUserSync = doc["lastUserSyncByUid"] as
      | Record<string, unknown>
      | undefined;
    assert.ok(
      lastUserSync && typeof lastUserSync === "object",
      "lastUserSyncByUid map must be on the mirror doc"
    );
    assert.ok(
      lastUserSync![UID] !== undefined,
      `lastUserSyncByUid.${UID} must be set for this refresh`
    );

    // The set MUST use merge:true so a future write of `lastSyncedAt`
    // alone doesn't blow away the export-sourced fields (task spec).
    const mirrorWrites = writes.filter(
      (w) => w.path === `${MIRROR_COLL}/${VALID_UUID}`
    );
    assert.ok(
      mirrorWrites.length >= 1,
      "at least one write to the mirror doc"
    );
    assert.ok(
      mirrorWrites.every((w) => w.merge === true),
      "every mirror-doc write must use {merge: true}"
    );
  }
);

test(
  "Task 013: no request.auth.uid → throws HttpsError('unauthenticated'); " +
    "no HTTP fetches issued; no mirror writes",
  async () => {
    const { db, store, writes } = makeFirestoreStub();
    seedOwnedCharacter(store, { uuid: VALID_UUID, ownerId: UID });

    const { fetch: mockFetch, calls } = makeRouter({});

    let thrown: unknown;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        try {
          await runSyncMyLarpManagerCharacter(
            makeDeps({ db }),
            makeRequest({
              uid: null,
              data: {
                gameId: `${TENANT.instanceId}::${TENANT.eventSlug}`,
                characterUuid: VALID_UUID,
              },
            })
          );
        } catch (e) {
          thrown = e;
        }
      });
    });

    assert.ok(thrown instanceof HttpsError, "must throw HttpsError");
    assert.equal((thrown as HttpsError).code, "unauthenticated");
    assert.equal(calls.length, 0, "no HTTP fetches when auth missing");
    assert.equal(
      writes.filter((w) => w.path.startsWith(MIRROR_COLL)).length,
      0,
      "no mirror writes when auth missing"
    );
  }
);

test(
  "Task 013: characterUuid missing → HttpsError('invalid-argument'); " +
    "no HTTP fetches issued",
  async () => {
    const { db, store, writes } = makeFirestoreStub();
    seedOwnedCharacter(store, { uuid: VALID_UUID, ownerId: UID });
    const { fetch: mockFetch, calls } = makeRouter({});

    let thrown: unknown;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        try {
          await runSyncMyLarpManagerCharacter(
            makeDeps({ db }),
            makeRequest({
              uid: UID,
              data: {
                gameId: `${TENANT.instanceId}::${TENANT.eventSlug}`,
                // characterUuid intentionally omitted.
              },
            })
          );
        } catch (e) {
          thrown = e;
        }
      });
    });

    assert.ok(
      thrown instanceof HttpsError,
      "must throw HttpsError for missing characterUuid"
    );
    assert.equal((thrown as HttpsError).code, "invalid-argument");
    assert.equal(
      calls.length,
      0,
      "validation must fail before any HTTP fetch"
    );
    assert.equal(
      writes.filter((w) => w.path.startsWith(MIRROR_COLL)).length,
      0,
      "validation must fail before any mirror write"
    );
  }
);

test(
  "Task 013: characterUuid wrong shape (uppercase / too short / non-alnum) " +
    "→ HttpsError('invalid-argument'); no HTTP fetches issued",
  async () => {
    const { db, store } = makeFirestoreStub();
    seedOwnedCharacter(store, { uuid: VALID_UUID, ownerId: UID });
    const { fetch: mockFetch, calls } = makeRouter({});

    const badShapes = [
      "TOO_SHORT", // uppercase + underscore
      "char00013AAA", // uppercase
      "char13aa", // too short
      "char00013aaaa", // too long
      "char-0013aaa", // hyphen
      "../etc/passwd", // path traversal attempt
    ];

    for (const bad of badShapes) {
      let thrown: unknown;
      await withCapturedLogs(async () => {
        await withMockedFetch(mockFetch, async () => {
          try {
            await runSyncMyLarpManagerCharacter(
              makeDeps({ db }),
              makeRequest({
                uid: UID,
                data: {
                  gameId: `${TENANT.instanceId}::${TENANT.eventSlug}`,
                  characterUuid: bad,
                },
              })
            );
          } catch (e) {
            thrown = e;
          }
        });
      });

      assert.ok(
        thrown instanceof HttpsError,
        `characterUuid=${JSON.stringify(bad)} must throw HttpsError`
      );
      assert.equal(
        (thrown as HttpsError).code,
        "invalid-argument",
        `characterUuid=${JSON.stringify(bad)} must yield invalid-argument`
      );
    }

    assert.equal(
      calls.length,
      0,
      "no HTTP fetch should escape the validation gate, even across all " +
        "bad shapes"
    );
  }
);

test(
  "Task 013: characters/{characterUuid} doc missing → " +
    "HttpsError('not-found'); no per-character HTTP fetches",
  async () => {
    // Intentionally do NOT seed the characters doc.
    const { db } = makeFirestoreStub();
    const { fetch: mockFetch, calls } = makeRouter({});

    let thrown: unknown;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        try {
          await runSyncMyLarpManagerCharacter(
            makeDeps({ db }),
            makeRequest({
              uid: UID,
              data: {
                gameId: `${TENANT.instanceId}::${TENANT.eventSlug}`,
                characterUuid: VALID_UUID,
              },
            })
          );
        } catch (e) {
          thrown = e;
        }
      });
    });

    assert.ok(thrown instanceof HttpsError, "must throw HttpsError");
    assert.equal((thrown as HttpsError).code, "not-found");
    assert.equal(
      calls.length,
      0,
      "no per-character fetches should escape the ownership-lookup gate"
    );
  }
);

test(
  "Task 013: ownerId !== request.auth.uid → " +
    "HttpsError('permission-denied'); per-character endpoints NOT called; " +
    "mirror doc NOT updated",
  async () => {
    const { db, store, writes } = makeFirestoreStub();
    seedOwnedCharacter(store, { uuid: VALID_UUID, ownerId: OTHER_UID });
    const { fetch: mockFetch, calls } = makeRouter({});

    let thrown: unknown;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        try {
          await runSyncMyLarpManagerCharacter(
            makeDeps({ db }),
            makeRequest({
              uid: UID, // != OTHER_UID seeded above
              data: {
                gameId: `${TENANT.instanceId}::${TENANT.eventSlug}`,
                characterUuid: VALID_UUID,
              },
            })
          );
        } catch (e) {
          thrown = e;
        }
      });
    });

    assert.ok(thrown instanceof HttpsError, "must throw HttpsError");
    assert.equal((thrown as HttpsError).code, "permission-denied");
    assert.equal(
      calls.length,
      0,
      "permission-denied must be raised BEFORE any LM HTTP fetch"
    );
    assert.equal(
      writes.filter((w) => w.path.startsWith(MIRROR_COLL)).length,
      0,
      "mirror doc must NOT be written for an attempt by a non-owner"
    );
  }
);

test(
  "Task 013: loadConfig returns null (integration not configured) → " +
    "HttpsError('failed-precondition')",
  async () => {
    const { db, store, writes } = makeFirestoreStub();
    seedOwnedCharacter(store, { uuid: VALID_UUID, ownerId: UID });
    const { fetch: mockFetch, calls } = makeRouter({});

    let thrown: unknown;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        try {
          await runSyncMyLarpManagerCharacter(
            makeDeps({ db, config: null }),
            makeRequest({
              uid: UID,
              data: {
                gameId: `${TENANT.instanceId}::${TENANT.eventSlug}`,
                characterUuid: VALID_UUID,
              },
            })
          );
        } catch (e) {
          thrown = e;
        }
      });
    });

    assert.ok(thrown instanceof HttpsError, "must throw HttpsError");
    assert.equal((thrown as HttpsError).code, "failed-precondition");
    assert.equal(
      calls.length,
      0,
      "no LM HTTP fetches when integration is not configured"
    );
    assert.equal(
      writes.filter((w) => w.path.startsWith(MIRROR_COLL)).length,
      0,
      "no mirror writes when integration is not configured"
    );
  }
);

test(
  "Task 013: ONE of the three per-character fetches throws → callable " +
    "returns {ok: false, error: 'Could not refresh: ...'} (NOT throws), " +
    "AND the mirror doc still receives lastUserSyncByUid.{uid} so a " +
    "future rate-limit can see the attempt was made",
  async () => {
    const { db, store, writes } = makeFirestoreStub();
    seedOwnedCharacter(store, { uuid: VALID_UUID, ownerId: UID });

    // Drive the sheet fetch into a 500. The inventory and abilities
    // endpoints either succeed before the failure or never get hit;
    // both are acceptable per the task spec (serial order; partial
    // attempt is fine).
    const { fetch: mockFetch } = makeRouter({
      perCharacter: {
        [VALID_UUID]: {
          inventory: (u) => jsonResponse({ items: [] }, u),
          abilities: (u) => jsonResponse({ abilities: [] }, u),
          sheet: (u) => htmlResponse("oops", u, 500),
        },
      },
    });

    let result: { ok: boolean; error?: string } | undefined;
    let thrown: unknown;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        try {
          result = await runSyncMyLarpManagerCharacter(
            makeDeps({ db }),
            makeRequest({
              uid: UID,
              data: {
                gameId: `${TENANT.instanceId}::${TENANT.eventSlug}`,
                characterUuid: VALID_UUID,
              },
            })
          );
        } catch (e) {
          thrown = e;
        }
      });
    });

    assert.equal(
      thrown,
      undefined,
      "callable must NOT throw on a per-character HTTP failure — the UI " +
        "expects to render the error inline via the {ok:false} branch"
    );
    assert.ok(result, "callable should resolve to a result");
    assert.equal(result!.ok, false, "result.ok must be false");
    assert.ok(
      typeof result!.error === "string" && result!.error.length > 0,
      "result.error must be a non-empty string"
    );
    assert.ok(
      result!.error!.startsWith("Could not refresh:"),
      `error must be prefixed with "Could not refresh:" so the client can ` +
        `snackbar it verbatim, got: ${result!.error}`
    );

    // Even though we failed, the mirror MUST still capture the per-uid
    // timestamp so a future server-side rate-limit can see this user
    // attempted a refresh and decline a too-fast retry.
    const mirrorWrites = writes.filter(
      (w) => w.path === `${MIRROR_COLL}/${VALID_UUID}`
    );
    assert.ok(
      mirrorWrites.length >= 1,
      "the mirror doc must still receive at least one write so " +
        "lastUserSyncByUid.{uid} is recorded for rate-limiting"
    );
    const doc = store.get(`${MIRROR_COLL}/${VALID_UUID}`) as Record<
      string,
      unknown
    >;
    const lastUserSync = doc?.["lastUserSyncByUid"] as
      | Record<string, unknown>
      | undefined;
    assert.ok(
      lastUserSync && typeof lastUserSync === "object",
      "lastUserSyncByUid map must be written on a failed attempt"
    );
    assert.ok(
      lastUserSync![UID] !== undefined,
      `lastUserSyncByUid.${UID} must be set even on a failed attempt`
    );
  }
);

test(
  "Task 013 merge semantics: a successful refresh PRESERVES the mirror " +
    "doc's pre-existing admin-sync-only export / name / number / teaser " +
    "fields (set via runLarpManagerSync) — refresh must not clobber them " +
    "to undefined",
  async () => {
    const { db, store } = makeFirestoreStub();
    seedOwnedCharacter(store, { uuid: VALID_UUID, ownerId: UID });

    // Seed an existing mirror doc as if a recent admin sync had run:
    // it carries export-sourced fields that the per-character refresh
    // does NOT re-fetch.
    store.set(`${MIRROR_COLL}/${VALID_UUID}`, {
      export: { number: 42, name: "Heldrek", uuid: VALID_UUID, teaser: "<p>Fire Mage</p>" },
      number: 42,
      name: "Heldrek",
      uuid: VALID_UUID,
      teaser: "Fire Mage",
      source: "larpmanager",
    });

    const { fetch: mockFetch } = makeRouter({
      perCharacter: {
        [VALID_UUID]: {
          inventory: (u) => jsonResponse({ items: ["sword"] }, u),
          abilities: (u) => jsonResponse({ abilities: ["block"] }, u),
          sheet: (u) => htmlResponse(SHEET_HTML_OK, u),
        },
      },
    });

    let result: { ok: boolean } | undefined;
    await withCapturedLogs(async () => {
      await withMockedFetch(mockFetch, async () => {
        result = await runSyncMyLarpManagerCharacter(
          makeDeps({ db }),
          makeRequest({
            uid: UID,
            data: {
              gameId: `${TENANT.instanceId}::${TENANT.eventSlug}`,
              characterUuid: VALID_UUID,
            },
          })
        );
      });
    });

    assert.deepEqual(result, { ok: true });

    const doc = store.get(`${MIRROR_COLL}/${VALID_UUID}`) as Record<
      string,
      unknown
    >;
    assert.ok(doc, "mirror doc still exists");
    // Pre-existing fields preserved (the whole point of {merge: true}).
    assert.deepEqual(
      doc["export"],
      {
        number: 42,
        name: "Heldrek",
        uuid: VALID_UUID,
        teaser: "<p>Fire Mage</p>",
      },
      "export field must be preserved across a per-character refresh"
    );
    assert.equal(doc["number"], 42, "number preserved");
    assert.equal(doc["name"], "Heldrek", "name preserved");
    assert.equal(doc["teaser"], "Fire Mage", "teaser preserved");
    assert.equal(doc["uuid"], VALID_UUID, "uuid preserved");
    assert.equal(doc["source"], "larpmanager", "source preserved");

    // New per-character fields added.
    assert.ok(doc["inventory"], "inventory now present");
    assert.ok(doc["abilities"], "abilities now present");
    assert.ok(doc["sheet"], "sheet now present");
    assert.ok(doc["lastSyncedAt"], "lastSyncedAt updated");
    const lastUserSync = doc["lastUserSyncByUid"] as
      | Record<string, unknown>
      | undefined;
    assert.ok(
      lastUserSync && lastUserSync[UID] !== undefined,
      `lastUserSyncByUid.${UID} set after a successful refresh`
    );
  }
);
