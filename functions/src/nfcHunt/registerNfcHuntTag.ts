import * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, resolveGameTenantFromBody } from "../gameTenant";
import { sanitizeLocation } from "../location/locationPayload";
import { nfcHuntDoc, nfcHuntTagDoc } from "./paths";

const ORGANIZER_ROLES = new Set(["owner", "superAdmin"]);

export interface RegisterNfcHuntTagBody {
  gameId?: string;
  instanceId?: string;
  eventSlug?: string;
  huntId?: string;
  tagUid?: string;
  placement?: string;
  label?: string;
  location?: unknown;
}

export interface RegisterNfcHuntTagDeps {
  db: admin.firestore.Firestore;
  now?: () => admin.firestore.Timestamp;
}

export async function runRegisterNfcHuntTag(
  deps: RegisterNfcHuntTagDeps,
  request: CallableRequest<RegisterNfcHuntTagBody>
): Promise<{ tagUid: string }> {
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
  if (!huntId) {
    throw new HttpsError("invalid-argument", "huntId is required");
  }

  const tagUid = typeof body.tagUid === "string" ? body.tagUid.trim() : "";
  if (!tagUid) {
    throw new HttpsError("invalid-argument", "tagUid must be non-empty");
  }

  const placement = body.placement;
  if (placement !== "fixed" && placement !== "floating") {
    throw new HttpsError(
      "invalid-argument",
      "placement must be 'fixed' or 'floating'"
    );
  }

  const base = gameEventBase(tenant);
  const db = deps.db;

  const memberSnap = await db.doc(`${base}/members/${uid}`).get();
  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "Not a member of this game");
  }

  const huntSnap = await db.doc(nfcHuntDoc(base, huntId)).get();
  if (!huntSnap.exists) {
    throw new HttpsError("not-found", "Hunt not found");
  }
  const hunt = huntSnap.data() ?? {};
  const role = memberSnap.data()?.role;
  const isOrganizer = typeof role === "string" && ORGANIZER_ROLES.has(role);
  const placerUids = Array.isArray(hunt.placerUids) ? hunt.placerUids : [];
  const isPlacer = placerUids.includes(uid);
  if (!isOrganizer && !isPlacer) {
    throw new HttpsError(
      "permission-denied",
      "Only organizers or hunt placers can register tags"
    );
  }

  const payload: Record<string, unknown> = {
    placement,
    registeredByUid: uid,
    registeredAt: deps.now?.() ?? admin.firestore.Timestamp.now(),
  };
  if (typeof body.label === "string" && body.label.length > 0) {
    payload.label = body.label;
  }
  if (placement === "fixed") {
    const loc = sanitizeLocation(body.location);
    if (loc) payload.location = loc;
  }

  await db.doc(nfcHuntTagDoc(base, huntId, tagUid)).set(payload);
  return { tagUid };
}
