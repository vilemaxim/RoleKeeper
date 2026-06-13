/**
 * Task 013: player-driven per-character refresh.
 *
 * `runSyncMyLarpManagerCharacter` is the body of the
 * `syncMyLarpManagerCharacterCallable` callable (wired from
 * `functions/src/index.ts`). It re-pulls just ONE character's data
 * from LarpManager for the requesting user, when that user owns the
 * character — letting players see fresh stats without waiting for the
 * organizer's next bulk sync.
 *
 * Auth + validation (in order; first failure throws):
 *   1. `request.auth?.uid` required → `unauthenticated`.
 *   2. `request.data.characterUuid` must match LM's UuidMixin shape
 *      `/^[a-z0-9]{12}$/` → otherwise `invalid-argument`. The tenant
 *      is resolved via `resolveGameTenantFromBody` (same helper as
 *      `runLarpManagerSyncCallable`).
 *   3. `${base}/characters/{characterUuid}` must exist → otherwise
 *      `not-found`.
 *   4. `data.ownerId === request.auth.uid` → otherwise
 *      `permission-denied`. The mirror doc itself carries no ownerId
 *      so we read the `characters` doc (written by Task 006's
 *      `writeResolvedCharacters`) before touching the mirror.
 *   5. `loadConfig(...)` must return a config → otherwise
 *      `failed-precondition`.
 *
 * Sync logic (SERIAL — preserves LM rate-limit posture, matches admin
 * sync; do NOT parallelise):
 *   1. `fetchCharacterInventoryJson` → `inventory`
 *   2. `fetchCharacterAbilitiesJson` → `abilities`
 *   3. `fetchCharacterSheetHtml` + `parseCharacterSheetHtml` → `sheet`
 *
 * Mirror write (`{merge: true}` to preserve the admin-sync-only
 * `export` / `name` / `number` / `teaser` / `uuid` / `source` fields):
 * {
 *   inventory,
 *   abilities,
 *   sheet,
 *   lastSyncedAt: serverTimestamp(),
 *   lastUserSyncByUid: { [uid]: serverTimestamp() },
 * }
 *
 * Return:
 *   - Success: `{ ok: true }`. The Flutter UI repaints via the
 *     existing mirror-doc `StreamBuilder`; no ISO timestamp round-trip
 *     needed.
 *   - Per-character HTTP / parse failure: `{ ok: false, error:
 *     "Could not refresh: <message>" }` (HTTP 200 to the client). Each
 *     fetch is caught independently, and `lastUserSyncByUid.{uid}` is
 *     still written so a future server-side rate-limit can see the
 *     attempt was made — letting us add metering without a schema
 *     change.
 *   - Auth / permission / config errors: `HttpsError`. The Flutter
 *     side maps these to user-friendly copy via `reportAppError`.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { parseCharacterSheetHtml } from "./characterSheet";
import {
  establishLarpManagerSession,
  fetchCharacterAbilitiesJson,
  fetchCharacterInventoryJson,
  fetchCharacterSheetHtml,
} from "./client";
import {
  type GameTenant,
  gameEventBase,
  resolveGameTenantFromBody,
} from "../gameTenant";
import type { LarpManagerSyncConfig } from "./types";

/** LarpManager UuidMixin format: 12 chars, lowercase alnum. */
const LM_CHARACTER_UUID_RE = /^[a-z0-9]{12}$/;

export interface SyncMyCharacterBody {
  gameId?: string;
  instanceId?: string;
  eventSlug?: string;
  characterUuid?: string;
}

export type SyncMyCharacterResult =
  | { ok: true }
  | { ok: false; error: string };

/**
 * Loader signature for the per-game integration config. Injectable so
 * unit tests can bypass Google Cloud Secret Manager — which the real
 * `loadLarpManagerSyncConfigForGame` reaches into for the LM
 * credentials and which is not available under `node --test`.
 */
export type LoadIntegrationConfig = (
  db: admin.firestore.Firestore,
  projectId: string,
  tenant: GameTenant
) => Promise<LarpManagerSyncConfig | null>;

export interface SyncMyCharacterDeps {
  db: admin.firestore.Firestore;
  projectId: string;
  loadConfig: LoadIntegrationConfig;
}

export async function runSyncMyLarpManagerCharacter(
  deps: SyncMyCharacterDeps,
  request: CallableRequest<SyncMyCharacterBody>
): Promise<SyncMyCharacterResult> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const body = request.data ?? {};
  const characterUuid = body.characterUuid;
  if (
    typeof characterUuid !== "string" ||
    !LM_CHARACTER_UUID_RE.test(characterUuid)
  ) {
    throw new HttpsError("invalid-argument", "characterUuid required");
  }

  const tenant = resolveGameTenantFromBody(body);
  if (!tenant) {
    throw new HttpsError(
      "invalid-argument",
      "gameId (tenantKey) or instanceId+eventSlug is required"
    );
  }

  const base = gameEventBase(tenant);
  const charSnap = await deps.db.doc(`${base}/characters/${characterUuid}`).get();
  if (!charSnap.exists) {
    throw new HttpsError("not-found", "Character not found");
  }
  const charData = charSnap.data() as { ownerId?: string } | undefined;
  if (charData?.ownerId !== uid) {
    throw new HttpsError("permission-denied", "Not your character");
  }

  const config = await deps.loadConfig(deps.db, deps.projectId, tenant);
  if (!config) {
    throw new HttpsError(
      "failed-precondition",
      "LarpManager integration not configured"
    );
  }

  const jar = await establishLarpManagerSession(config);

  // SERIAL on purpose: matches `runLarpManagerSync`'s posture so we
  // don't accidentally tighten LM's rate-limit headroom under the
  // many-users-at-once load this callable invites.
  const errors: string[] = [];
  const mirrorPatch: Record<string, unknown> = {};

  try {
    mirrorPatch.inventory = await fetchCharacterInventoryJson(
      config,
      jar,
      characterUuid
    );
  } catch (e) {
    errors.push((e as Error).message);
  }

  try {
    mirrorPatch.abilities = await fetchCharacterAbilitiesJson(
      config,
      jar,
      characterUuid
    );
  } catch (e) {
    errors.push((e as Error).message);
  }

  try {
    const { html } = await fetchCharacterSheetHtml(config, jar, characterUuid);
    mirrorPatch.sheet = parseCharacterSheetHtml(html);
  } catch (e) {
    errors.push((e as Error).message);
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  mirrorPatch.lastSyncedAt = now;
  mirrorPatch.lastUserSyncByUid = { [uid]: now };

  await deps.db
    .doc(`${base}/larpManagerMirrorChars/${characterUuid}`)
    .set(mirrorPatch, { merge: true });

  if (errors.length > 0) {
    const message = errors[0]!;
    logger.warn("syncMyLarpManagerCharacter: per-character refresh failed", {
      uid,
      characterUuid,
      errorCount: errors.length,
      firstError: message.slice(0, 200),
    });
    return {
      ok: false,
      error: `Could not refresh: ${message}`,
    };
  }

  return { ok: true };
}
