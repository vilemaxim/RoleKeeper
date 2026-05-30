/**
 * Pull LarpManager export + optional details and write Firestore mirror.
 */

import * as crypto from "crypto";

import * as admin from "firebase-admin";

import {
  establishLarpManagerSession,
  fetchCharacterAbilitiesJson,
  fetchCharacterExportJson,
  fetchCharacterInventoryJson,
} from "./client";
import { type GameTenant, gameEventBase } from "../gameTenant";
import type { LarpManagerSyncConfig, LarpManagerSyncResult } from "./types";

const BATCH_SIZE = 400;

export async function runLarpManagerSync(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  config: LarpManagerSyncConfig
): Promise<LarpManagerSyncResult> {
  const base = gameEventBase(tenant);
  const jar = await establishLarpManagerSession(config);
  const exportJson = await fetchCharacterExportJson(config, jar);
  const raw = JSON.stringify(exportJson);
  const exportSha256 = crypto.createHash("sha256").update(raw).digest("hex");

  const errors: string[] = [];
  let detailsFetched = 0;
  const summaryRef = db.doc(`${base}/larpManagerMirrorMeta/summary`);
  const now = admin.firestore.FieldValue.serverTimestamp();

  const entries = Object.entries(exportJson);
  const characters: Array<{
    docId: string;
    data: Record<string, unknown>;
  }> = [];

  for (const [numKey, ch] of entries) {
    const uuid = typeof ch.uuid === "string" ? ch.uuid : null;
    const docId = uuid ?? `n${numKey}`;
    const row: Record<string, unknown> = {
      number: ch.number ?? Number(numKey),
      name: ch.name,
      uuid: ch.uuid ?? null,
      teaser: ch.teaser,
      export: ch,
      lastSyncedAt: now,
      source: "larpmanager",
    };

    if (config.fetchDetails && uuid) {
      try {
        row.inventory = await fetchCharacterInventoryJson(config, jar, uuid);
        row.abilities = await fetchCharacterAbilitiesJson(config, jar, uuid);
        detailsFetched += 1;
      } catch (e) {
        errors.push(`${docId}: ${(e as Error).message}`);
      }
    }

    characters.push({ docId, data: row });
  }

  const coll = db.collection(`${base}/larpManagerMirrorChars`);
  for (let i = 0; i < characters.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const slice = characters.slice(i, i + BATCH_SIZE);
    for (const { docId, data } of slice) {
      batch.set(coll.doc(docId), data, { merge: true });
    }
    await batch.commit();
  }

  await summaryRef.set(
    {
      lastSyncedAt: now,
      lastOk: errors.length === 0,
      lastError: errors.length ? errors.slice(0, 10).join(" | ") : null,
      eventSlug: config.eventSlug,
      characterCount: characters.length,
      exportSha256,
      fetchDetails: config.fetchDetails,
    },
    { merge: true }
  );

  return {
    characterCount: characters.length,
    detailsFetched,
    exportSha256,
    errors,
  };
}
