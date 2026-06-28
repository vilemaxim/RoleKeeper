import * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, resolveGameTenantFromBody } from "../gameTenant";
import { sanitizeLocation, withGpsSource } from "./locationPayload";
import { mintLocationPingDocId } from "./mintPingDocId";

export interface RecordLocationPingBody {
  gameId?: string;
  instanceId?: string;
  eventSlug?: string;
  location?: unknown;
  characterId?: string;
}

export interface RecordLocationPingDeps {
  db: admin.firestore.Firestore;
  now?: () => admin.firestore.Timestamp;
}

function existingLastLocationTimestamp(
  member: Record<string, unknown>
): number | null {
  const existing = member.lastLocation as Record<string, unknown> | undefined;
  const ts = existing?.timestamp as admin.firestore.Timestamp | undefined;
  if (!ts?.toDate) return null;
  return ts.toDate().getTime();
}

export async function runRecordLocationPing(
  deps: RecordLocationPingDeps,
  request: CallableRequest<RecordLocationPingBody>
): Promise<{ pingId: string }> {
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

  const loc = sanitizeLocation(body.location);
  if (!loc) {
    throw new HttpsError(
      "invalid-argument",
      "Valid location (latitude, longitude) is required"
    );
  }

  const base = gameEventBase(tenant);
  const db = deps.db;

  const memberSnap = await db.doc(`${base}/members/${uid}`).get();
  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "Not a member of this game");
  }
  const member = memberSnap.data() ?? {};

  const rulesSnap = await db.doc(`${base}/rules/locationTracking`).get();
  if (rulesSnap.data()?.enabled !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Location tracking is disabled for this event"
    );
  }

  const sessionSnap = await db.doc(`${base}/eventSession/config`).get();
  if (sessionSnap.data()?.isLive !== true) {
    throw new HttpsError("failed-precondition", "Event is not live");
  }

  if (member.locationOptIn !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Location opt-in is required to record pings"
    );
  }

  const presenceState =
    typeof member.presenceState === "string"
      ? member.presenceState
      : "in_game";
  const inGame = presenceState === "in_game";

  const now = deps.now?.() ?? admin.firestore.Timestamp.now();
  const pingId = mintLocationPingDocId(now);
  const location = withGpsSource(loc);

  const payload: Record<string, unknown> = {
    id: pingId,
    playerId: uid,
    presenceState,
    inGame,
    location,
    timestamp: now,
  };

  const characterId = body.characterId;
  if (typeof characterId === "string" && characterId.length > 0) {
    payload.characterId = characterId;
  }

  const lastLocation: Record<string, unknown> = {
    latitude: location.latitude,
    longitude: location.longitude,
    source: location.source ?? "gps",
    timestamp: now,
    presenceState,
    inGame,
  };
  if (typeof location.accuracy === "number") {
    lastLocation.accuracy = location.accuracy;
  }
  if (typeof location.altitude === "number") {
    lastLocation.altitude = location.altitude;
  }

  const batch = db.batch();
  batch.set(db.collection(`${base}/locationPings`).doc(pingId), payload);

  const existingTs = existingLastLocationTimestamp(member);
  const shouldUpdateLastLocation =
    existingTs === null || now.toDate().getTime() >= existingTs;
  if (shouldUpdateLastLocation) {
    batch.set(
      db.doc(`${base}/members/${uid}`),
      { lastLocation },
      { merge: true }
    );
  }

  await batch.commit();

  return { pingId };
}
