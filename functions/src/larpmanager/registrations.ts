/**
 * Sync LarpManager event registrations into Firestore and verify players by email.
 */

import * as crypto from "crypto";

import * as admin from "firebase-admin";
import AdmZip from "adm-zip";

import type { GameTenant } from "../gameTenant";
import { gameEventBase, tenantKey } from "../gameTenant";
import { establishLarpManagerSession, fetchRegistrationsExportZip } from "./client";
import type { LarpManagerSyncConfig } from "./types";

export const REGISTRATIONS_COLLECTION = "larpManagerRegistrations";
export const REGISTRATIONS_META_DOC = "larpManagerRegistrationsMeta/summary";

/** Re-sync from LarpManager if meta is older than this (ms). */
export const REGISTRATIONS_CACHE_MS = 5 * 60 * 1000;

export const MEMBERSHIP_REGISTERED_AT_FIELD = "larpManagerRegisteredAt";
export const MEMBERSHIP_REGISTERED_EMAIL_FIELD = "larpManagerRegistrationEmail";

export interface LarpManagerRegistrationSyncResult {
  registrationCount: number;
  syncRunId: string;
  skippedCache: boolean;
}

export interface LarpManagerRegistrationCheckResult {
  registered: boolean;
  registrationPageUrl: string;
  registrationCount: number;
  syncedAt: string | null;
  message: string | null;
}

export function registrationDocIdForEmail(email: string): string {
  return crypto
    .createHash("sha256")
    .update(email.trim().toLowerCase())
    .digest("hex");
}

/** Parse a single CSV line respecting double-quoted fields. */
export function parseCsvLine(line: string): string[] {
  const out: string[] = [];
  let cur = "";
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') {
          cur += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cur += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ",") {
      out.push(cur);
      cur = "";
    } else {
      cur += ch;
    }
  }
  out.push(cur);
  return out;
}

export interface RegistrationRow {
  emailLower: string;
  characterNames: string[];
}

/** Parse registration export rows (email + optional Characters column). */
export function parseRegistrationRowsFromCsv(csv: string): RegistrationRow[] {
  const lines = csv.split(/\r?\n/).filter((l) => l.trim().length > 0);
  if (lines.length < 2) return [];

  const headers = parseCsvLine(lines[0]!);
  const emailIdx = headers.findIndex((h) => h.trim().toLowerCase() === "email");
  if (emailIdx < 0) {
    throw new Error(
      'Registration export CSV has no "Email" column — check LarpManager export permissions'
    );
  }
  const charIdx = headers.findIndex(
    (h) => h.trim().toLowerCase() === "characters"
  );

  const rows: RegistrationRow[] = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = parseCsvLine(lines[i]!);
    const emailLower = cols[emailIdx]?.trim().toLowerCase() ?? "";
    if (!emailLower.includes("@")) continue;

    let characterNames: string[] = [];
    if (charIdx >= 0) {
      const raw = cols[charIdx]?.trim() ?? "";
      if (raw.length > 0) {
        characterNames = raw
          .split(",")
          .map((s) => s.trim())
          .filter((s) => s.length > 0);
      }
    }
    rows.push({ emailLower, characterNames });
  }
  return rows;
}

/** Extract participant emails from LarpManager registration export CSV. */
export function parseRegistrationEmailsFromCsv(csv: string): string[] {
  return [
    ...new Set(parseRegistrationRowsFromCsv(csv).map((r) => r.emailLower)),
  ];
}

/** Read `registration.csv` from the ZIP returned by manage/registrations download. */
export function extractRegistrationCsvFromZip(zipBuffer: Buffer): string {
  const zip = new AdmZip(zipBuffer);
  const entry =
    zip.getEntry("registration.csv") ??
    zip
      .getEntries()
      .find((e: { entryName: string }) =>
        e.entryName.toLowerCase().endsWith("registration.csv")
      );
  if (!entry) {
    throw new Error("Registration export ZIP missing registration.csv");
  }
  return zip.readAsText(entry, "utf8");
}

export function buildRegistrationPageUrl(config: LarpManagerSyncConfig): string {
  const base = config.baseUrl.replace(/\/+$/, "");
  const slug = config.eventSlug.replace(/^\/+|\/+$/g, "");
  return `${base}/${slug}/register/`;
}

export async function syncLarpManagerRegistrations(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  config: LarpManagerSyncConfig,
  options?: { force?: boolean }
): Promise<LarpManagerRegistrationSyncResult> {
  const base = gameEventBase(tenant);
  const metaRef = db.doc(`${base}/${REGISTRATIONS_META_DOC}`);
  const coll = db.collection(`${base}/${REGISTRATIONS_COLLECTION}`);

  if (!options?.force) {
    const metaSnap = await metaRef.get();
    const lastSynced = metaSnap.data()?.lastSyncedAt as
      | admin.firestore.Timestamp
      | undefined;
    if (lastSynced) {
      const ageMs = Date.now() - lastSynced.toMillis();
      if (ageMs < REGISTRATIONS_CACHE_MS) {
        const count = (metaSnap.data()?.registrationCount as number) ?? 0;
        return {
          registrationCount: count,
          syncRunId: String(metaSnap.data()?.syncRunId ?? ""),
          skippedCache: true,
        };
      }
    }
  }

  const jar = await establishLarpManagerSession(config);
  const zipBuffer = await fetchRegistrationsExportZip(config, jar);
  const csv = extractRegistrationCsvFromZip(zipBuffer);
  const rows = parseRegistrationRowsFromCsv(csv);
  const byEmail = new Map<string, string[]>();
  for (const row of rows) {
    const prev = byEmail.get(row.emailLower) ?? [];
    const merged = [...new Set([...prev, ...row.characterNames])];
    byEmail.set(row.emailLower, merged);
  }
  const emails = [...byEmail.keys()];

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
          characterNames: byEmail.get(email) ?? [],
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
      registrationCount: emails.length,
      syncRunId,
    },
    { merge: true }
  );

  return {
    registrationCount: emails.length,
    syncRunId,
    skippedCache: false,
  };
}

export async function checkUserLarpManagerRegistration(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  config: LarpManagerSyncConfig,
  uid: string,
  email: string,
  options?: { forceSync?: boolean }
): Promise<LarpManagerRegistrationCheckResult> {
  const emailLower = email.trim().toLowerCase();
  const registrationPageUrl = buildRegistrationPageUrl(config);
  const base = gameEventBase(tenant);

  const sync = await syncLarpManagerRegistrations(db, tenant, config, {
    force: options?.forceSync === true,
  });

  const metaSnap = await db.doc(`${base}/${REGISTRATIONS_META_DOC}`).get();
  const syncedAtTs = metaSnap.data()?.lastSyncedAt as
    | admin.firestore.Timestamp
    | undefined;
  const syncedAt = syncedAtTs ? syncedAtTs.toDate().toISOString() : null;

  const regSnap = await db
    .doc(
      `${base}/${REGISTRATIONS_COLLECTION}/${registrationDocIdForEmail(emailLower)}`
    )
    .get();

  const registered = regSnap.exists;

  if (registered) {
    const now = admin.firestore.FieldValue.serverTimestamp();
    const patch = {
      [MEMBERSHIP_REGISTERED_AT_FIELD]: now,
      [MEMBERSHIP_REGISTERED_EMAIL_FIELD]: emailLower,
    };
    const tKey = tenantKey(tenant);
    await db.doc(`${base}/members/${uid}`).set(patch, { merge: true });
    await db.doc(`users/${uid}/gameMemberships/${tKey}`).set(patch, { merge: true });
  }

  return {
    registered,
    registrationPageUrl,
    registrationCount: sync.registrationCount,
    syncedAt,
    message: registered
      ? null
      : "Sign in to LarpManager with the same email you use in RoleKeeper, " +
        "complete event registration, then tap Check registration status.",
  };
}
