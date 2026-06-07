/**
 * Sync a player's LarpManager characters into Firestore `characters` collection.
 */

import * as crypto from "crypto";

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import type { GameTenant } from "../gameTenant";
import { gameEventBase } from "../gameTenant";
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
      map[key] = {
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
}

export async function syncPlayerCharactersForUser(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  config: LarpManagerSyncConfig,
  uid: string,
  email: string,
  options?: {
    jar?: Awaited<ReturnType<typeof establishLarpManagerSession>>;
  }
): Promise<PlayerCharacterSyncResult> {
  const emailLower = email.trim().toLowerCase();
  const base = gameEventBase(tenant);
  const charsCol = db.collection(`${base}/characters`);
  const lookupCol = db.collection(`${base}/characterShortIdLookup`);

  // Diagnostic logging is PII-free: only `uid` and the (non-secret) event
  // base path are recorded. Never log raw email addresses or character names.
  const regSnap = await db
    .doc(
      `${base}/larpManagerRegistrations/${registrationDocIdForEmail(emailLower)}`
    )
    .get();

  const characterNames =
    (regSnap.data()?.characterNames as string[] | undefined) ?? [];

  logger.info("syncPlayerCharactersForUser: registration read", {
    uid,
    eventBase: base,
    regExists: regSnap.exists,
    namesCount: characterNames.length,
  });

  if (characterNames.length === 0) {
    const existing = await charsCol
      .where("ownerId", "==", uid)
      .where("isArchived", "==", false)
      .limit(1)
      .get();
    logger.info(
      "syncPlayerCharactersForUser: registration has empty characterNames",
      {
        uid,
        eventBase: base,
        regExists: regSnap.exists,
        existingChars: existing.size,
      }
    );
    return {
      hasCharacter: !existing.empty,
      characterCount: existing.size,
    };
  }

  const exportMap = await loadCharacterExportMap(
    db,
    tenant,
    config,
    options?.jar
  );
  const mirrorSize = Object.keys(exportMap).length;
  const resolved = resolveCharactersByNames(exportMap, characterNames);

  logger.info("syncPlayerCharactersForUser: resolved", {
    uid,
    eventBase: base,
    namesCount: characterNames.length,
    mirrorSize,
    matchedCount: resolved.length,
  });

  if (resolved.length === 0) {
    const existing = await charsCol
      .where("ownerId", "==", uid)
      .where("isArchived", "==", false)
      .limit(1)
      .get();
    logger.info(
      `syncPlayerCharactersForUser: 0/${characterNames.length} names matched mirror export`,
      {
        uid,
        eventBase: base,
        mirrorSize,
        existingChars: existing.size,
      }
    );
    return {
      hasCharacter: !existing.empty,
      characterCount: existing.size,
    };
  }

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

  logger.info("syncPlayerCharactersForUser: wrote characters", {
    uid,
    eventBase: base,
    written: resolved.length,
  });

  return {
    hasCharacter: true,
    characterCount: resolved.length,
  };
}
