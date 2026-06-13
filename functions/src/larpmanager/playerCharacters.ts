/**
 * Sync a player's LarpManager characters into Firestore `characters` collection.
 */

import * as crypto from "crypto";

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import type { GameTenant } from "../gameTenant";
import { gameEventBase } from "../gameTenant";
import { CHARACTERS_BY_EMAIL_COLLECTION } from "./charactersByEmail";
import {
  establishLarpManagerSession,
  fetchCharacterExportJson,
} from "./client";
import { registrationDocIdForEmail } from "./registrations";
import type { LarpManagerCharacterExport, LarpManagerSyncConfig } from "./types";

export function buildCharacterCreatePageUrl(
  config: LarpManagerSyncConfig
): string {
  const base = config.baseUrl.replace(/\/+$/, "");
  const slug = config.eventSlug.replace(/^\/+|\/+$/g, "");
  return `${base}/${slug}/character/create/`;
}

export interface ResolvedLmCharacter {
  uuid: string;
  name: string;
  number?: number;
}

/** Match registration CSV character names against bulk character export. */
export function resolveCharactersByNames(
  exportMap: Record<string, LarpManagerCharacterExport>,
  names: string[]
): ResolvedLmCharacter[] {
  const byNameLower = new Map<string, LarpManagerCharacterExport>();
  for (const ch of Object.values(exportMap)) {
    const n = ch.name?.trim();
    if (n) {
      byNameLower.set(n.toLowerCase(), ch);
    }
  }

  const out: ResolvedLmCharacter[] = [];
  const seenUuids = new Set<string>();
  for (const raw of names) {
    const trimmed = raw.trim();
    if (!trimmed) continue;
    const ch = byNameLower.get(trimmed.toLowerCase());
    const uuid = typeof ch?.uuid === "string" ? ch.uuid : null;
    if (!uuid || seenUuids.has(uuid)) continue;
    seenUuids.add(uuid);
    out.push({
      uuid,
      name: (ch?.name ?? trimmed).trim(),
      number: ch?.number,
    });
  }
  return out;
}

/**
 * Linear-scan the export map for a character whose `uuid` (top-level
 * projection, NOT a nested key) matches `characterUuidLower`. Used by the
 * Path-0 HTML join — it gets a uuid from
 * `larpManagerCharactersByEmail/{regDocId}.characterUuids` and needs to
 * pull the `name`/`number` from the mirror so the resolved character can
 * be written with a stable shortId.
 *
 * Returns `null` when no character matches (e.g. the bulk mirror hasn't
 * yet synced this character). The caller falls back to the legacy paths
 * rather than guessing.
 */
export function findCharacterInExportMap(
  exportMap: Record<string, LarpManagerCharacterExport>,
  characterUuidLower: string
): ResolvedLmCharacter | null {
  for (const ch of Object.values(exportMap)) {
    const u = typeof ch.uuid === "string" ? ch.uuid.toLowerCase() : null;
    if (u === characterUuidLower) {
      return {
        uuid: ch.uuid as string,
        name: (ch.name ?? (ch.uuid as string)).trim(),
        number: typeof ch.number === "number" ? ch.number : undefined,
      };
    }
  }
  return null;
}

/**
 * Find every character whose export contains the given (lower-cased) email as
 * the exact value of any string-valued field.
 *
 * Used by the organizer fallback in `syncPlayerCharactersForUser`: an
 * organizer is typically NOT in the registration CSV (registrations are for
 * players), so the registration-name join can't see their character. LM does
 * however put the assigned player's email on each character export — under
 * one of several possible keys depending on LM version (`player_email`,
 * `player`, `user_email`, `email`, ...). Rather than guess the key, we walk
 * every string-valued field and require an *exact* lower-cased match against
 * `emailLower`. The exact-match rule (not substring) prevents false positives
 * from free-text fields such as relationships or quest notes that might
 * mention an email in passing.
 *
 * Returns one entry per matched character (deduped by `uuid`). The caller
 * decides how to handle multi-match: the production code writes only when
 * exactly one character matches.
 */
export function findCharactersByEmailInExportMap(
  exportMap: Record<string, LarpManagerCharacterExport>,
  emailLower: string
): ResolvedLmCharacter[] {
  if (!emailLower) return [];
  const out: ResolvedLmCharacter[] = [];
  const seenUuids = new Set<string>();
  for (const ch of Object.values(exportMap)) {
    if (!characterExportContainsEmail(ch, emailLower)) continue;
    const uuid = typeof ch.uuid === "string" ? ch.uuid : null;
    if (!uuid || seenUuids.has(uuid)) continue;
    seenUuids.add(uuid);
    out.push({
      uuid,
      name: (ch.name ?? uuid).trim(),
      number: typeof ch.number === "number" ? ch.number : undefined,
    });
  }
  return out;
}

/**
 * True iff any string value in `ch` (at any depth) lowercases to
 * `emailLower`. Recurses into nested objects/arrays so a future LM version
 * that nests the player record (e.g. `export.player.email`) still resolves.
 * Non-string scalars and unset values are ignored.
 */
function characterExportContainsEmail(
  ch: LarpManagerCharacterExport,
  emailLower: string
): boolean {
  return valueContainsEmail(ch as unknown, emailLower);
}

function valueContainsEmail(value: unknown, emailLower: string): boolean {
  if (typeof value === "string") {
    return value.trim().toLowerCase() === emailLower;
  }
  if (Array.isArray(value)) {
    for (const v of value) {
      if (valueContainsEmail(v, emailLower)) return true;
    }
    return false;
  }
  if (value !== null && typeof value === "object") {
    for (const v of Object.values(value as Record<string, unknown>)) {
      if (valueContainsEmail(v, emailLower)) return true;
    }
    return false;
  }
  return false;
}

/** Deterministic 3-char short ID for LM-synced characters. */
export function shortIdForLmCharacter(ch: ResolvedLmCharacter): string {
  if (ch.number !== null && ch.number !== undefined && Number.isFinite(ch.number)) {
    const n = Math.abs(Math.trunc(ch.number));
    if (n >= 1000) return String(n % 1000).padStart(3, "0");
    return String(n).padStart(3, "0").slice(-3);
  }
  return crypto
    .createHash("sha256")
    .update(ch.uuid)
    .digest("hex")
    .slice(0, 3)
    .toUpperCase();
}

export async function loadCharacterExportMap(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  config: LarpManagerSyncConfig,
  jar?: Awaited<ReturnType<typeof establishLarpManagerSession>>
): Promise<Record<string, LarpManagerCharacterExport>> {
  const base = gameEventBase(tenant);
  const mirrorSnap = await db.collection(`${base}/larpManagerMirrorChars`).get();
  if (!mirrorSnap.empty) {
    const map: Record<string, LarpManagerCharacterExport> = {};
    for (const doc of mirrorSnap.docs) {
      const d = doc.data();
      const num = d.number as number | undefined;
      const key = num !== null ? String(num) : doc.id;
      // Mirror docs store the full LM export under `d.export` (see
      // `runLarpManagerSync` in sync.ts). Spread it first so consumers like
      // `findCharactersByEmailInExportMap` see fields such as `player_email`,
      // then overlay the four typed projections so the well-known shape
      // (`number` / `name` / `uuid` / `teaser`) always wins over any drift
      // between the projected fields and the embedded export blob.
      const exportData =
        (d.export as Record<string, unknown> | undefined) ?? {};
      map[key] = {
        ...exportData,
        number: num,
        name: d.name as string | undefined,
        uuid: (d.uuid as string | undefined) ?? undefined,
        teaser: d.teaser as string | undefined,
      };
    }
    return map;
  }

  const sessionJar = jar ?? (await establishLarpManagerSession(config));
  return fetchCharacterExportJson(config, sessionJar);
}

export interface PlayerCharacterSyncResult {
  hasCharacter: boolean;
  characterCount: number;
  /**
   * True iff we ran the organizer email-mirror fallback path (Task 006
   * Hypothesis A). False for plain players, and false for organizers whose
   * registration row already produced a character via the name-join path.
   */
  organizerLookupAttempted: boolean;
  /**
   * Count of characters whose `export` contained the organizer's email when
   * the fallback ran. `0` → confirmed absent (write "confirm your LM email"
   * copy); `1` → resolved and written; `> 1` → ambiguous, no write.
   * Always `0` when `organizerLookupAttempted` is false.
   */
  organizerLookupMatches: number;
  /**
   * True iff we consulted the `larpManagerCharactersByEmail` join table
   * (populated from LM's manage/registrations HTML page) for this user.
   * The lookup runs whenever such a doc exists for the user's email,
   * regardless of organizer status — the HTML join is exact (uses LM's
   * own user_uuid ↔ character_uuid mapping) so it's safe to trust for
   * any role. Task 006, second iteration.
   */
  htmlLookupAttempted: boolean;
  /**
   * Number of `characterUuids` that the user owns according to the
   * `larpManagerCharactersByEmail/{regDocId}` doc. May be > the count
   * of actually-written characters when the bulk mirror sync hasn't
   * caught up with those uuids yet (in which case we resolve only what
   * the mirror has).
   */
  htmlLookupMatches: number;
}

export async function syncPlayerCharactersForUser(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  config: LarpManagerSyncConfig,
  uid: string,
  email: string,
  options?: {
    jar?: Awaited<ReturnType<typeof establishLarpManagerSession>>;
    /**
     * When true, after the registration-name path fails (or there's no
     * registration row at all) the function will load the bulk character
     * mirror and try to associate a character by exact email match. This is
     * the Task-006 fix for organizers, who are typically not listed as
     * players in the registrations CSV. Plain players intentionally do NOT
     * trigger this path: a player not in the CSV legitimately has no
     * character on the event yet.
     */
    isOrganizer?: boolean;
  }
): Promise<PlayerCharacterSyncResult> {
  const emailLower = email.trim().toLowerCase();
  const isOrganizer = options?.isOrganizer === true;
  const base = gameEventBase(tenant);
  const charsCol = db.collection(`${base}/characters`);
  const lookupCol = db.collection(`${base}/characterShortIdLookup`);
  const emailRegDocId = registrationDocIdForEmail(emailLower);

  // Diagnostic logging is PII-free: only `uid` and the (non-secret) event
  // base path are recorded. Never log raw email addresses or character names.
  const regSnap = await db
    .doc(
      `${base}/larpManagerRegistrations/${emailRegDocId}`
    )
    .get();

  const characterNames =
    (regSnap.data()?.characterNames as string[] | undefined) ?? [];

  logger.info("syncPlayerCharactersForUser: registration read", {
    uid,
    eventBase: base,
    regExists: regSnap.exists,
    namesCount: characterNames.length,
    isOrganizer,
  });

  // Memoize the export map: both the registration-name path and the
  // organizer-fallback path consume it, but the registration path is the
  // common case and a no-op for organizers (whose `characterNames` is
  // empty), so we lazy-load on first use and reuse on the fallback.
  let cachedExportMap: Record<string, LarpManagerCharacterExport> | null = null;
  const loadMap = async (): Promise<
    Record<string, LarpManagerCharacterExport>
  > => {
    if (cachedExportMap === null) {
      cachedExportMap = await loadCharacterExportMap(
        db,
        tenant,
        config,
        options?.jar
      );
    }
    return cachedExportMap;
  };

  // --- Path 0: characters-by-email HTML join (Task 006, second iteration). -
  //
  // This is the most authoritative join we have: LM's manage/registrations
  // HTML page exposes an exact `(email → character_uuid)` table populated
  // for every user on the event, including organizers (who are absent from
  // the CSV export). It runs FIRST because when the data is present it
  // resolves exactly and we don't need the fragile name-matching paths
  // below. When the doc is missing or has no uuids we fall through to the
  // legacy paths so events that never set up the orga_registrations
  // permission keep working off the CSV path.
  let htmlLookupAttempted = false;
  let htmlLookupMatches = 0;
  const htmlSnap = await db
    .doc(`${base}/${CHARACTERS_BY_EMAIL_COLLECTION}/${emailRegDocId}`)
    .get();
  const htmlCharacterUuids =
    (htmlSnap.data()?.characterUuids as string[] | undefined) ?? [];
  if (htmlCharacterUuids.length > 0) {
    htmlLookupAttempted = true;
    htmlLookupMatches = htmlCharacterUuids.length;
    const exportMap = await loadMap();
    const resolvedFromHtml: ResolvedLmCharacter[] = [];
    const seenUuids = new Set<string>();
    for (const charUuid of htmlCharacterUuids) {
      const key = charUuid.toLowerCase();
      if (seenUuids.has(key)) continue;
      seenUuids.add(key);
      // The mirror is keyed by character `number` if available, else by
      // doc id; either way `findCharacterInExportMap` linear-scans for
      // the matching uuid because the mirror size is bounded by the LM
      // event (hundreds at most).
      const found = findCharacterInExportMap(exportMap, key);
      if (found) resolvedFromHtml.push(found);
    }

    logger.info(
      "syncPlayerCharactersForUser: characters-by-email HTML lookup",
      {
        uid,
        eventBase: base,
        htmlUuidsCount: htmlCharacterUuids.length,
        resolvedFromMirror: resolvedFromHtml.length,
      }
    );

    if (resolvedFromHtml.length > 0) {
      await writeResolvedCharacters(
        db,
        charsCol,
        lookupCol,
        uid,
        resolvedFromHtml
      );
      logger.info(
        "syncPlayerCharactersForUser: wrote characters (HTML fallback)",
        {
          uid,
          eventBase: base,
          written: resolvedFromHtml.length,
        }
      );
      return {
        hasCharacter: true,
        characterCount: resolvedFromHtml.length,
        organizerLookupAttempted: false,
        organizerLookupMatches: 0,
        htmlLookupAttempted: true,
        htmlLookupMatches,
      };
    }
    // We had uuids from the HTML join table but the mirror doesn't yet
    // have those characters — fall through to the legacy paths so the
    // user isn't told "no character" while waiting for the bulk sync.
  }

  // --- Path A: registration-name join (the original flow). -----------------
  if (characterNames.length > 0) {
    const exportMap = await loadMap();
    const mirrorSize = Object.keys(exportMap).length;
    const resolved = resolveCharactersByNames(exportMap, characterNames);

    logger.info("syncPlayerCharactersForUser: resolved", {
      uid,
      eventBase: base,
      namesCount: characterNames.length,
      mirrorSize,
      matchedCount: resolved.length,
    });

    if (resolved.length > 0) {
      await writeResolvedCharacters(db, charsCol, lookupCol, uid, resolved);
      logger.info("syncPlayerCharactersForUser: wrote characters", {
        uid,
        eventBase: base,
        written: resolved.length,
      });
      return {
        hasCharacter: true,
        characterCount: resolved.length,
        organizerLookupAttempted: false,
        organizerLookupMatches: 0,
        htmlLookupAttempted,
        htmlLookupMatches,
      };
    }

    // Names present but none matched the mirror — fall through to the
    // organizer-fallback / legacy-/characters tail. Preserve the existing
    // "0/N matched" diagnostic shape so the production log greps still hit.
    logger.info(
      `syncPlayerCharactersForUser: 0/${characterNames.length} names matched mirror export`,
      {
        uid,
        eventBase: base,
        mirrorSize,
      }
    );
  } else {
    logger.info(
      "syncPlayerCharactersForUser: registration has empty characterNames",
      {
        uid,
        eventBase: base,
        regExists: regSnap.exists,
      }
    );
  }

  // --- Path B: organizer email-mirror fallback (Task 006 fix). -------------
  let organizerLookupAttempted = false;
  let organizerLookupMatches = 0;
  if (isOrganizer) {
    const exportMap = await loadMap();
    const mirrorSize = Object.keys(exportMap).length;
    const matched = findCharactersByEmailInExportMap(exportMap, emailLower);
    organizerLookupAttempted = true;
    organizerLookupMatches = matched.length;

    logger.info("syncPlayerCharactersForUser: organizer email-mirror lookup", {
      uid,
      eventBase: base,
      mirrorSize,
      matchedCount: matched.length,
    });

    if (matched.length === 1) {
      await writeResolvedCharacters(db, charsCol, lookupCol, uid, matched);
      logger.info(
        "syncPlayerCharactersForUser: wrote characters (organizer fallback)",
        {
          uid,
          eventBase: base,
          written: matched.length,
        }
      );
      return {
        hasCharacter: true,
        characterCount: matched.length,
        organizerLookupAttempted,
        organizerLookupMatches,
        htmlLookupAttempted,
        htmlLookupMatches,
      };
    }
    // 0 matches → fall through to legacy /characters probe; the caller
    // (resolveLarpManagerPlayerAccess) turns this into actionable copy.
    // > 1 matches → ambiguous; do NOT auto-pick, fall through.
  }

  // --- Path C: legacy /characters probe (always-on tail). ------------------
  const existing = await charsCol
    .where("ownerId", "==", uid)
    .where("isArchived", "==", false)
    .limit(1)
    .get();

  logger.info("syncPlayerCharactersForUser: legacy /characters probe", {
    uid,
    eventBase: base,
    existingChars: existing.size,
  });

  return {
    hasCharacter: !existing.empty,
    characterCount: existing.size,
    organizerLookupAttempted,
    organizerLookupMatches,
    htmlLookupAttempted,
    htmlLookupMatches,
  };
}

async function writeResolvedCharacters(
  db: admin.firestore.Firestore,
  charsCol: admin.firestore.CollectionReference,
  lookupCol: admin.firestore.CollectionReference,
  uid: string,
  resolved: ResolvedLmCharacter[]
): Promise<void> {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const BATCH = 400;
  for (let i = 0; i < resolved.length; i += BATCH) {
    const batch = db.batch();
    for (const ch of resolved.slice(i, i + BATCH)) {
      const shortId = shortIdForLmCharacter(ch);
      const charRef = charsCol.doc(ch.uuid);
      batch.set(
        charRef,
        {
          ownerId: uid,
          name: ch.name,
          shortId,
          larpManagerUuid: ch.uuid,
          source: "larpmanager",
          isArchived: false,
          updatedAt: now,
          createdAt: now,
        },
        { merge: true }
      );
      batch.set(
        lookupCol.doc(shortId),
        { ownerId: uid, characterId: ch.uuid },
        { merge: true }
      );
    }
    await batch.commit();
  }
}
