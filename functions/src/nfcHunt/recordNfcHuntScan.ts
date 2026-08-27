import * as crypto from "crypto";

import * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, resolveGameTenantFromBody, tenantKey } from "../gameTenant";
import { sanitizeLocation } from "../location/locationPayload";
import {
  NFC_HUNT_SCAN_RESULT,
  createInAppNotification,
} from "../notifications/createInAppNotification";
import {
  characterNfcHuntScanDoc,
  nfcHuntDoc,
  nfcHuntReviewScanDoc,
  nfcHuntScanDoc,
  nfcHuntScansCollection,
  nfcHuntTagDoc,
} from "./paths";

export interface RecordNfcHuntScanBody {
  gameId?: string;
  instanceId?: string;
  eventSlug?: string;
  huntId?: string;
  characterId?: string;
  tagUid?: string;
  location?: unknown;
  clientScannedAt?: unknown;
  queuedOffline?: boolean;
}

export interface RecordNfcHuntScanDeps {
  db: admin.firestore.Firestore;
  now?: () => admin.firestore.Timestamp;
}

export type RecordNfcHuntScanResult =
  | { outcome: "credited"; scanId: string }
  | { outcome: "already_scanned" }
  | { outcome: "unknown_tag" };

function mintScanId(now: admin.firestore.Timestamp): string {
  const t = now.toDate().getTime();
  const tie = crypto.randomBytes(3).toString("hex");
  return `${t}_${tie}`;
}

function asTimestamp(raw: unknown): admin.firestore.Timestamp | undefined {
  if (
    raw &&
    typeof raw === "object" &&
    "toDate" in raw &&
    typeof (raw as { toDate: unknown }).toDate === "function"
  ) {
    return raw as admin.firestore.Timestamp;
  }
  if (typeof raw === "string" && raw.trim()) {
    const d = new Date(raw);
    if (!Number.isNaN(d.getTime())) {
      return admin.firestore.Timestamp.fromDate(d);
    }
  }
  return undefined;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

async function notifyScanOutcome(
  db: admin.firestore.Firestore,
  args: {
    uid: string;
    tenantKey: string;
    huntId: string;
    huntName?: string;
    tagUid: string;
    tagLabel?: string;
    outcome: "credited" | "already_scanned" | "unknown_tag";
  }
): Promise<void> {
  const { uid, tenantKey: tKey, huntId, huntName, tagUid, tagLabel, outcome } =
    args;
  const copy =
    outcome === "credited"
      ? {
          title: "Tag found!",
          body: `Tag found! Credit recorded for ${tagLabel?.trim() || tagUid}.`,
        }
      : outcome === "already_scanned"
        ? {
            title: "Already scanned",
            body: "You already scanned this tag.",
          }
        : {
            title: "Unknown tag",
            body:
              "Unknown tag logged for staff review. Take a photo if the tag looks damaged.",
          };
  await createInAppNotification(db, {
    uid,
    type: NFC_HUNT_SCAN_RESULT,
    title: copy.title,
    body: copy.body,
    tenantKey: tKey,
    payload: {
      outcome,
      tagUid,
      huntId,
      ...(huntName ? { huntName } : {}),
    },
  });
}

export async function runRecordNfcHuntScan(
  deps: RecordNfcHuntScanDeps,
  request: CallableRequest<RecordNfcHuntScanBody>
): Promise<RecordNfcHuntScanResult> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const body = request.data ?? {};
  const tenant = resolveGameTenantFromBody({
    gameId: body.gameId,
    instanceId: body.instanceId,
    eventSlug: body.eventSlug,
  });
  if (!tenant) {
    throw new HttpsError(
      "invalid-argument",
      "gameId (tenantKey) or instanceId+eventSlug is required"
    );
  }

  const huntId = typeof body.huntId === "string" ? body.huntId.trim() : "";
  const characterId =
    typeof body.characterId === "string" ? body.characterId.trim() : "";
  const tagUid = typeof body.tagUid === "string" ? body.tagUid.trim() : "";
  if (!huntId || !characterId || !tagUid) {
    throw new HttpsError(
      "invalid-argument",
      "huntId, characterId, and tagUid are required"
    );
  }

  const base = gameEventBase(tenant);
  const tKey = tenantKey(tenant);
  const db = deps.db;
  const now = deps.now?.() ?? admin.firestore.Timestamp.now();

  const memberSnap = await db.doc(`${base}/members/${uid}`).get();
  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "Not a member of this game");
  }

  const huntSnap = await db.doc(nfcHuntDoc(base, huntId)).get();
  if (!huntSnap.exists) {
    throw new HttpsError("not-found", "Hunt not found");
  }
  const huntData = huntSnap.data() ?? {};
  if (huntData.enabled !== true) {
    throw new HttpsError("failed-precondition", "Hunt is not enabled");
  }
  const huntName = optionalString(huntData.name);

  const characterSnap = await db.doc(`${base}/characters/${characterId}`).get();
  if (!characterSnap.exists) {
    throw new HttpsError("not-found", "Character not found");
  }
  if (characterSnap.data()?.ownerId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Character is not owned by the caller"
    );
  }

  const scanId = mintScanId(now);
  const payload: Record<string, unknown> = {
    characterId,
    ownerUid: uid,
    tagUid,
    huntId,
    tenantKey: tKey,
    scannedAt: now,
    queuedOffline: body.queuedOffline === true,
  };
  const loc = sanitizeLocation(body.location);
  if (loc) payload.location = loc;
  const clientScannedAt = asTimestamp(body.clientScannedAt);
  if (clientScannedAt) payload.clientScannedAt = clientScannedAt;

  const tagSnap = await db.doc(nfcHuntTagDoc(base, huntId, tagUid)).get();
  if (!tagSnap.exists) {
    await db.doc(nfcHuntReviewScanDoc(base, huntId, scanId)).set({
      ...payload,
      reason: "unknown_tag",
    });
    await notifyScanOutcome(db, {
      uid,
      tenantKey: tKey,
      huntId,
      huntName,
      tagUid,
      outcome: "unknown_tag",
    });
    return { outcome: "unknown_tag" };
  }

  const tagLabel = optionalString(tagSnap.data()?.label);

  const existing = await db
    .collection(nfcHuntScansCollection(base, huntId))
    .where("characterId", "==", characterId)
    .where("tagUid", "==", tagUid)
    .limit(1)
    .get();
  if (!existing.empty) {
    await notifyScanOutcome(db, {
      uid,
      tenantKey: tKey,
      huntId,
      huntName,
      tagUid,
      tagLabel,
      outcome: "already_scanned",
    });
    return { outcome: "already_scanned" };
  }

  const batch = db.batch();
  batch.set(db.doc(nfcHuntScanDoc(base, huntId, scanId)), payload);
  batch.set(
    db.doc(characterNfcHuntScanDoc(base, characterId, scanId)),
    payload
  );
  await batch.commit();

  await notifyScanOutcome(db, {
    uid,
    tenantKey: tKey,
    huntId,
    huntName,
    tagUid,
    tagLabel,
    outcome: "credited",
  });

  return { outcome: "credited", scanId };
}
