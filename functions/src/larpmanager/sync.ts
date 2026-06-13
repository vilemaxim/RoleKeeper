/**
 * Pull LarpManager export + optional details and write Firestore mirror.
 */

import * as crypto from "crypto";

import * as admin from "firebase-admin";

import { parseCharacterSheetHtml } from "./characterSheet";
import {
  establishLarpManagerSession,
  fetchCharacterAbilitiesJson,
  fetchCharacterExportJson,
  fetchCharacterInventoryJson,
  fetchCharacterSheetHtml,
} from "./client";
import { htmlToPlainText } from "./htmlText";
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
  let sheetsFetched = 0;
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
      export: ch,
      lastSyncedAt: now,
      source: "larpmanager",
    };
    // Task 011: store the display-clean projection of teaser on the
    // mirror doc so Flutter's Text widget doesn't render literal
    // `<p>Fire Mage</p>`. The verbatim raw HTML still rides inside
    // `row.export.teaser` for any future consumer that needs LM's
    // original markup. Omit the top-level `teaser` field entirely
    // when the strip yields no displayable text — writing `null` or
    // `''` would otherwise persist into Firestore.
    const teaserPlain = htmlToPlainText(
      typeof ch.teaser === "string" ? ch.teaser : null
    );
    if (teaserPlain !== undefined) {
      row.teaser = teaserPlain;
    }

    // Task 012 / ADR 0001: admin sync is always full. Every uuid-bearing
    // character gets its inventory, abilities, and parsed HTML sheet
    // fetched on every sync. The `fetchDetails` config toggle is gone;
    // the only remaining gate is the uuid check (characters without a
    // uuid have no per-character endpoint to call).
    if (uuid) {
      try {
        row.inventory = await fetchCharacterInventoryJson(config, jar, uuid);
        row.abilities = await fetchCharacterAbilitiesJson(config, jar, uuid);
        detailsFetched += 1;
      } catch (e) {
        errors.push(`${docId}: ${(e as Error).message}`);
      }
      // Sheet fetch + parse is intentionally isolated in its own try
      // so a sheet HTTP/parse failure for THIS character does NOT
      // poison the inventory+abilities pair above (or vice versa),
      // and so failures for one character don't abort the loop for
      // the others. Counter is independent of detailsFetched per
      // Task 009 spec.
      try {
        const { html } = await fetchCharacterSheetHtml(config, jar, uuid);
        row.sheet = parseCharacterSheetHtml(html);
        sheetsFetched += 1;
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
      // Task 012 / ADR 0001: no `fetchDetails` key. Stale `fetchDetails`
      // fields in pre-Task-012 summary docs are left alone (Firestore
      // tolerates extra fields); merge writes simply stop refreshing
      // them. UI never reads them.
    },
    { merge: true }
  );

  return {
    characterCount: characters.length,
    detailsFetched,
    sheetsFetched,
    exportSha256,
    errors,
  };
}
