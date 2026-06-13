/**
 * Sync LarpManager `/manage/registrations/` HTML into a join table keyed
 * by sha256(emailLower), so RoleKeeper can resolve any user (organizer or
 * player) to the LM characters they own — even for events whose bulk
 * character export omits emails.
 *
 * Why this exists (Task 006, second iteration): the first fix assumed the
 * bulk `/export/char/` JSON would carry a `player_email` field. The
 * production capture from `sovereignscrolls.larpmanager.com/crucible`
 * showed the export carries only `owner` (display name) and `owner_uuid`
 * (opaque LM id) — no email. The `/manage/registrations/` HTML page is
 * the canonical join table on LM's side: each row exposes
 * `(email, lm_user_uuid, character_uuid…)` as an exact tuple, and it
 * includes organizers (who are absent from the CSV export).
 *
 * Pure parser + Firestore-only sync. No HTTP except the single GET in
 * `syncLarpManagerCharactersByEmail`, which is sized to the registrations
 * page (~100 KB per event for crucible-scale events).
 */

import * as crypto from "crypto";

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import type { GameTenant } from "../gameTenant";
import { gameEventBase } from "../gameTenant";
import {
  establishLarpManagerSession,
  fetchRegistrationsManagementHtml,
} from "./client";
import {
  looksLikeLoginPage,
  looksLikeLoginUrl,
} from "./http";
import { looksLikeLarpManagerAccessDeniedPage } from "./organizers";
import {
  REGISTRATIONS_CACHE_MS,
  registrationDocIdForEmail,
} from "./registrations";
import type { LarpManagerSyncConfig } from "./types";

export const CHARACTERS_BY_EMAIL_COLLECTION = "larpManagerCharactersByEmail";
export const CHARACTERS_BY_EMAIL_META_DOC =
  "larpManagerCharactersByEmailMeta/summary";

/**
 * One parsed row from `/{slug}/manage/registrations/`. `characterUuids`
 * may be empty (organizers / staff with no character assigned yet); the
 * sync still writes the doc so we have a cached `(email → lmUserUuid)`
 * mapping for that user.
 */
export interface ManageRegistrationRow {
  emailLower: string;
  lmUserUuid: string;
  characterUuids: string[];
}

export interface LarpManagerCharactersByEmailSyncResult {
  rowCount: number;
  syncRunId: string;
  skippedCache: boolean;
}

/**
 * Parse the rows out of LarpManager's manage/registrations HTML.
 *
 * The page structure (per row), pinned to a fixture at
 * `functions/test/fixtures/crucible-manage-registrations/`:
 *
 *   <tr id="<registration_id>">
 *     <td><a class="post_popup_member" pop="<lm_user_uuid>" …></a></td>
 *     <td class="email"><email></td>
 *     <td>
 *       <a href="/<slug>/manage/characters/<character_uuid>/edit/">…</a>
 *       <a href="/<slug>/manage/characters/<character_uuid>/edit/">…</a>?
 *     </td>
 *     …other tds (payment / custom-field columns, ignored)…
 *   </tr>
 *
 * The parser is anchored on the discriminating attributes (`pop="…"`,
 * `class="email"`, `href="…/manage/characters/<uuid>/edit/"`) rather than
 * `<td>` positions so it survives LM custom-field reorderings. The
 * outer `<tr id="…">` id is accepted at 2..40 chars (production uses LM's
 * 12-char UuidMixin; tests use shorter convenience ids).
 *
 * Defensive rules:
 *   - rows missing `pop="…"` → skipped
 *   - rows missing `<td class="email">…</td>` → skipped
 *   - rows whose email doesn't contain "@" → skipped
 *   - duplicate character_uuid links in the same row → deduped
 *   - `manage/registrations/<uuid>/customization/` links use the same
 *     12-char ids as character uuids but on a different URL prefix; we
 *     pattern-match strictly on `manage/characters/<uuid>/edit/` so the
 *     customization links are not counted as second characters.
 */
export function parseManageRegistrationsHtml(
  html: string
): ManageRegistrationRow[] {
  if (!html) return [];
  const rows: ManageRegistrationRow[] = [];
  const rowRe =
    /<tr\b[^>]*\bid=["']([A-Za-z0-9_-]{2,40})["'][^>]*>([\s\S]*?)<\/tr>/gi;
  let match: RegExpExecArray | null;
  while ((match = rowRe.exec(html)) !== null) {
    const rowHtml = match[2]!;
    const popMatch = /\bpop=["']([a-z0-9]{4,40})["']/i.exec(rowHtml);
    if (!popMatch) continue;
    const lmUserUuid = popMatch[1]!.toLowerCase();

    const emailMatch = /<td\b[^>]*\bclass=["'][^"']*\bemail\b[^"']*["'][^>]*>\s*([^<]+?)\s*<\/td>/i.exec(
      rowHtml
    );
    if (!emailMatch) continue;
    const emailLower = emailMatch[1]!.trim().toLowerCase();
    if (!emailLower.includes("@")) continue;

    const characterUuids: string[] = [];
    const seenChars = new Set<string>();
    const charRe =
      /href=["'][^"']*\/manage\/characters\/([a-z0-9]{4,40})\/edit\/?["']/gi;
    let charMatch: RegExpExecArray | null;
    while ((charMatch = charRe.exec(rowHtml)) !== null) {
      const uuid = charMatch[1]!.toLowerCase();
      if (seenChars.has(uuid)) continue;
      seenChars.add(uuid);
      characterUuids.push(uuid);
    }

    rows.push({ emailLower, lmUserUuid, characterUuids });
  }
  return rows;
}

/**
 * Detect the LM "not authenticated" + "access denied" responses for the
 * registrations management page. Mirrors the discriminators
 * `fetchOrganizerEmailsFromLarpManager` already uses for the roles page:
 * a real registrations page never contains an `<Access denied>` title and
 * always carries at least one `<tr id="…">` row (or an explicit "No
 * registrations" empty-state marker that production LM doesn't trigger
 * for an active event).
 *
 * `parseManageRegistrationsHtml` already returns `[]` for a degraded
 * response, so the caller uses this only to upgrade silence into a
 * structured error.
 */
function classifyManagementResponse(
  html: string,
  finalUrl: string
): "ok" | "loginRedirect" | "accessDenied" | "unknownNoRows" {
  if (looksLikeLoginUrl(finalUrl) || looksLikeLoginPage(html)) {
    return "loginRedirect";
  }
  if (looksLikeLarpManagerAccessDeniedPage(html)) {
    return "accessDenied";
  }
  if (!/<tr\b[^>]*\bid=["'][A-Za-z0-9_-]{4,40}["']/i.test(html)) {
    return "unknownNoRows";
  }
  return "ok";
}

/**
 * Pure Firestore ingest step (no HTTP). Parses `html`, validates the
 * page-level verdict, then upserts one doc per parsed email under
 * `${base}/larpManagerCharactersByEmail/{regDocId}` and prunes any stale
 * docs left behind by previous syncs.
 *
 * Exported so unit tests can drive it directly from a captured HTML
 * fixture without mocking the HTTP layer.
 */
export async function ingestManageRegistrationsHtml(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  html: string,
  finalUrl: string
): Promise<LarpManagerCharactersByEmailSyncResult> {
  const base = gameEventBase(tenant);
  const metaRef = db.doc(`${base}/${CHARACTERS_BY_EMAIL_META_DOC}`);
  const coll = db.collection(`${base}/${CHARACTERS_BY_EMAIL_COLLECTION}`);

  const verdict = classifyManagementResponse(html, finalUrl);
  if (verdict !== "ok") {
    logger.error(
      "syncLarpManagerCharactersByEmail: management page unusable",
      {
        eventBase: base,
        verdict,
        finalUrl,
        bodySnippet: html.slice(0, 400),
      }
    );
    throw new Error(
      `LarpManager manage/registrations response was ${verdict} ` +
        `(final URL ${finalUrl}). The service account needs the ` +
        "orga_registrations permission on the Organizer role for this event."
    );
  }

  const rows = parseManageRegistrationsHtml(html);
  // Coalesce duplicate emails (LM occasionally re-renders the same email
  // across two registration rows if a player has multiple registration
  // entries; merge their characterUuids).
  const byEmail = new Map<string, ManageRegistrationRow>();
  for (const r of rows) {
    const existing = byEmail.get(r.emailLower);
    if (!existing) {
      byEmail.set(r.emailLower, { ...r, characterUuids: [...r.characterUuids] });
      continue;
    }
    if (existing.lmUserUuid !== r.lmUserUuid) {
      logger.warn(
        "syncLarpManagerCharactersByEmail: same email maps to multiple LM user uuids",
        { eventBase: base }
      );
    }
    for (const c of r.characterUuids) {
      if (!existing.characterUuids.includes(c)) existing.characterUuids.push(c);
    }
  }
  const dedupedRows = [...byEmail.values()];

  const syncRunId = crypto.randomBytes(8).toString("hex");
  const now = admin.firestore.FieldValue.serverTimestamp();
  const BATCH = 400;

  for (let i = 0; i < dedupedRows.length; i += BATCH) {
    const batch = db.batch();
    for (const row of dedupedRows.slice(i, i + BATCH)) {
      batch.set(
        coll.doc(registrationDocIdForEmail(row.emailLower)),
        {
          emailLower: row.emailLower,
          lmUserUuid: row.lmUserUuid,
          characterUuids: row.characterUuids,
          syncRunId,
          syncedAt: now,
          source: "larpmanager",
        },
        { merge: true }
      );
    }
    await batch.commit();
  }

  const existingSnap = await coll.get();
  const staleDocs = existingSnap.docs.filter(
    (d) => (d.data().syncRunId as string | undefined) !== syncRunId
  );
  for (let i = 0; i < staleDocs.length; i += BATCH) {
    const batch = db.batch();
    for (const doc of staleDocs.slice(i, i + BATCH)) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }

  await metaRef.set(
    {
      lastSyncedAt: now,
      lastOk: true,
      lastError: null,
      rowCount: dedupedRows.length,
      syncRunId,
    },
    { merge: true }
  );

  logger.info("syncLarpManagerCharactersByEmail: sync complete", {
    eventBase: base,
    rowCount: dedupedRows.length,
    rowsWithCharacters: dedupedRows.filter(
      (r) => r.characterUuids.length > 0
    ).length,
  });

  return {
    rowCount: dedupedRows.length,
    syncRunId,
    skippedCache: false,
  };
}

/**
 * Reuses the 5-minute caching contract already used by the organizers
 * and registrations syncs; safe to call on every callable invocation.
 * Thin wrapper around `ingestManageRegistrationsHtml` that handles the
 * HTTP fetch + session establishment.
 */
export async function syncLarpManagerCharactersByEmail(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  config: LarpManagerSyncConfig,
  options?: { force?: boolean }
): Promise<LarpManagerCharactersByEmailSyncResult> {
  const base = gameEventBase(tenant);
  const metaRef = db.doc(`${base}/${CHARACTERS_BY_EMAIL_META_DOC}`);

  if (!options?.force) {
    const metaSnap = await metaRef.get();
    const lastSynced = metaSnap.data()?.lastSyncedAt as
      | admin.firestore.Timestamp
      | undefined;
    if (lastSynced) {
      const ageMs = Date.now() - lastSynced.toMillis();
      if (ageMs < REGISTRATIONS_CACHE_MS) {
        return {
          rowCount: (metaSnap.data()?.rowCount as number) ?? 0,
          syncRunId: String(metaSnap.data()?.syncRunId ?? ""),
          skippedCache: true,
        };
      }
    }
  }

  const jar = await establishLarpManagerSession(config);
  const { html, finalUrl } = await fetchRegistrationsManagementHtml(
    config,
    jar
  );

  return ingestManageRegistrationsHtml(db, tenant, html, finalUrl);
}
