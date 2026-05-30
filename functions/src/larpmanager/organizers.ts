/**
 * Sync LarpManager event organizer emails (EventRole #1) into Firestore.
 */

import * as crypto from "crypto";

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import type { GameTenant } from "../gameTenant";
import { gameEventBase } from "../gameTenant";
import { establishLarpManagerSession } from "./client";
import {
  cookieMapToHeader,
  looksLikeLoginPage,
  looksLikeLoginUrl,
  mergeCookieMaps,
  normalizeBaseUrl,
  parseSetCookieHeaders,
} from "./http";
import { registrationDocIdForEmail, REGISTRATIONS_CACHE_MS } from "./registrations";
import type { LarpManagerSyncConfig } from "./types";

export const ORGANIZERS_COLLECTION = "larpManagerOrganizers";
export const ORGANIZERS_META_DOC = "larpManagerOrganizersMeta/summary";

export const MEMBERSHIP_ROLE_FIELD = "role";
export const MEMBERSHIP_ORGANIZER_EMAIL_FIELD = "larpManagerOrganizerEmail";

export interface LarpManagerOrganizerSyncResult {
  organizerCount: number;
  syncRunId: string;
  skippedCache: boolean;
}

/**
 * EventRole number 1 row has no delete link in the roles table.
 *
 * LarpManager's UuidMixin stores `uuid` as a 12-char lowercase alphanumeric
 * `[a-z0-9]{12}` value (see larpmanager/models/base.py + utils.my_uuid_short).
 * Debug mode uses `u<int>`. We accept anything id-safe between 4 and 40 chars
 * so a future format bump still parses; the trash-icon heuristic / single-row
 * fallback below picks the actual Organizer row.
 */
export function findOrganizerRoleUuidFromRolesHtml(html: string): string | null {
  // Limit to the <tbody> when present so we never match thead/footer rows.
  const tbodyMatch = /<tbody[^>]*>([\s\S]*?)<\/tbody>/i.exec(html);
  const haystack = tbodyMatch ? tbodyMatch[1]! : html;

  const rowRegex =
    /<tr\b[^>]*\bid=["']([A-Za-z0-9_-]{4,40})["'][^>]*>([\s\S]*?)<\/tr>/gi;
  const rows: Array<{ uuid: string; rowHtml: string }> = [];
  let match: RegExpExecArray | null;
  while ((match = rowRegex.exec(haystack)) !== null) {
    rows.push({ uuid: match[1]!, rowHtml: match[2]! });
  }
  for (const { uuid, rowHtml } of rows) {
    if (
      !rowHtml.includes("orga_roles_delete") &&
      !rowHtml.includes("fa-trash")
    ) {
      return uuid;
    }
  }
  // Fallback: only one role row total → it must be the auto-created Organizer.
  if (rows.length === 1) {
    return rows[0]!.uuid;
  }
  return null;
}

/** Parse `Name - email@host` patterns from the role edit form. */
export function parseEmailsFromRoleEditHtml(html: string): string[] {
  const emails = new Set<string>();
  const re =
    /\s-\s([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    emails.add(m[1]!.trim().toLowerCase());
  }
  return [...emails];
}

export async function fetchOrganizerEmailsFromLarpManager(
  config: LarpManagerSyncConfig,
  jar: Map<string, string>
): Promise<string[]> {
  const base = normalizeBaseUrl(config.baseUrl);
  const slug = config.eventSlug.replace(/^\/+|\/+$/g, "");
  const rolesUrl = `${base}/${slug}/manage/roles/`;

  const rolesRes = await fetch(rolesUrl, {
    method: "GET",
    headers: {
      Cookie: cookieMapToHeader(jar),
      "User-Agent": "RoleKeeper-LarpManagerSync/1.0",
    },
    redirect: "follow",
  });
  if (!rolesRes.ok) {
    throw new Error(
      `LarpManager roles page HTTP ${rolesRes.status} at ${rolesUrl} — ` +
        "the service account needs the orga_roles permission on the Organizer role for this event."
    );
  }
  const rolesHtml = await rolesRes.text();
  jar = mergeCookieMaps(jar, parseSetCookieHeaders(rolesRes.headers));

  const finalUrl = rolesRes.url || rolesUrl;
  const redirectedToLogin = looksLikeLoginUrl(finalUrl);
  const hasRolesTable = /<table[^>]*id=["']roles["']/i.test(rolesHtml);
  const isLoginPage = looksLikeLoginPage(rolesHtml);

  if (redirectedToLogin || (isLoginPage && !hasRolesTable)) {
    logger.error(
      "fetchOrganizerEmailsFromLarpManager: roles page redirected to login",
      {
        requested: rolesUrl,
        finalUrl,
        status: rolesRes.status,
        redirectedToLogin,
        looksLikeLoginPage: isLoginPage,
        hasRolesTable,
        bodySnippet: rolesHtml.slice(0, 400),
      }
    );
    throw new Error(
      `LarpManager redirected ${rolesUrl} to a login page (final URL ${finalUrl}). ` +
        "The service account session is not authenticated — verify username, password, and Login path."
    );
  }

  const roleUuid = findOrganizerRoleUuidFromRolesHtml(rolesHtml);
  if (!roleUuid) {
    logger.error(
      "fetchOrganizerEmailsFromLarpManager: could not locate Organizer row",
      {
        requested: rolesUrl,
        finalUrl,
        status: rolesRes.status,
        hasRolesTable,
        looksLikeLoginPage: isLoginPage,
        bodySnippet: rolesHtml.slice(0, 800),
      }
    );
    throw new Error(
      `Could not find the Organizer role on LarpManager ${finalUrl}. ` +
        (hasRolesTable
          ? "Roles table loaded but no row matched — your LarpManager version may use different markup."
          : "Response did not include the roles table — the service account may lack orga_roles permission or " +
            "the event slug may be wrong."
        )
    );
  }

  const editUrl = `${base}/${slug}/manage/roles/${roleUuid}/edit/`;
  const editRes = await fetch(editUrl, {
    method: "GET",
    headers: {
      Cookie: cookieMapToHeader(jar),
      Referer: rolesUrl,
      "User-Agent": "RoleKeeper-LarpManagerSync/1.0",
    },
    redirect: "follow",
  });
  if (!editRes.ok) {
    throw new Error(
      `LarpManager role edit page HTTP ${editRes.status} for organizer role at ${editUrl}`
    );
  }
  const editHtml = await editRes.text();
  const editFinalUrl = editRes.url || editUrl;
  if (looksLikeLoginUrl(editFinalUrl) || looksLikeLoginPage(editHtml)) {
    logger.error(
      "fetchOrganizerEmailsFromLarpManager: role edit redirected to login",
      {
        requested: editUrl,
        finalUrl: editFinalUrl,
        bodySnippet: editHtml.slice(0, 400),
      }
    );
    throw new Error(
      `LarpManager redirected ${editUrl} to login — service account session lost ` +
        "or it lacks permission to view this role's members."
    );
  }
  const emails = parseEmailsFromRoleEditHtml(editHtml);
  if (emails.length === 0) {
    logger.warn(
      "fetchOrganizerEmailsFromLarpManager: no emails parsed from role edit page",
      { finalUrl: editFinalUrl, bodySnippet: editHtml.slice(0, 600) }
    );
    throw new Error(
      `No organizer emails found on LarpManager role edit page at ${editFinalUrl}. ` +
        "The Organizer role may have no assigned members (no 'Name - email@host' entries)."
    );
  }
  return emails;
}

export async function syncLarpManagerOrganizers(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  config: LarpManagerSyncConfig,
  options?: { force?: boolean }
): Promise<LarpManagerOrganizerSyncResult> {
  const base = gameEventBase(tenant);
  const metaRef = db.doc(`${base}/${ORGANIZERS_META_DOC}`);
  const coll = db.collection(`${base}/${ORGANIZERS_COLLECTION}`);

  if (!options?.force) {
    const metaSnap = await metaRef.get();
    const lastSynced = metaSnap.data()?.lastSyncedAt as
      | admin.firestore.Timestamp
      | undefined;
    if (lastSynced) {
      const ageMs = Date.now() - lastSynced.toMillis();
      if (ageMs < REGISTRATIONS_CACHE_MS) {
        return {
          organizerCount: (metaSnap.data()?.organizerCount as number) ?? 0,
          syncRunId: String(metaSnap.data()?.syncRunId ?? ""),
          skippedCache: true,
        };
      }
    }
  }

  const jar = await establishLarpManagerSession(config);
  const emails = await fetchOrganizerEmailsFromLarpManager(config, jar);

  const syncRunId = crypto.randomBytes(8).toString("hex");
  const now = admin.firestore.FieldValue.serverTimestamp();
  const BATCH = 400;

  for (let i = 0; i < emails.length; i += BATCH) {
    const batch = db.batch();
    for (const email of emails.slice(i, i + BATCH)) {
      batch.set(
        coll.doc(registrationDocIdForEmail(email)),
        {
          emailLower: email,
          syncRunId,
          syncedAt: now,
          source: "larpmanager",
          eventRoleNumber: 1,
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
      organizerCount: emails.length,
      syncRunId,
    },
    { merge: true }
  );

  return {
    organizerCount: emails.length,
    syncRunId,
    skippedCache: false,
  };
}

export async function isEmailLarpManagerOrganizer(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  emailLower: string
): Promise<boolean> {
  const base = gameEventBase(tenant);
  const snap = await db
    .doc(
      `${base}/${ORGANIZERS_COLLECTION}/${registrationDocIdForEmail(emailLower)}`
    )
    .get();
  return snap.exists;
}
