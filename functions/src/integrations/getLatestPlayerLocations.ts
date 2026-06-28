import * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, resolveGameTenantFromBody } from "../gameTenant";
import { verifyApiKey } from "./apiKey";

export const RECENT_PING_WINDOW_MS = 15 * 60 * 1000;
export const MAX_PLAYER_LOCATIONS = 500;

const INVALID_CREDENTIALS = "Invalid credentials";

export interface GetLatestPlayerLocationsBody {
  gameId?: string;
  instanceId?: string;
  eventSlug?: string;
  apiKey?: string;
}

export interface PlayerLocationRow {
  playerId: string;
  latitude: number;
  longitude: number;
  accuracy?: number;
  timestamp: admin.firestore.Timestamp;
  presenceState: string;
  inGame: boolean;
}

export interface GetLatestPlayerLocationsDeps {
  db: admin.firestore.Firestore;
  now?: () => admin.firestore.Timestamp;
}

export async function runGetLatestPlayerLocations(
  deps: GetLatestPlayerLocationsDeps,
  request: CallableRequest<GetLatestPlayerLocationsBody>
): Promise<{ players: PlayerLocationRow[] }> {
  const body = request.data ?? {};
  const apiKey = typeof body.apiKey === "string" ? body.apiKey.trim() : "";
  if (!apiKey) {
    throw new HttpsError("permission-denied", INVALID_CREDENTIALS);
  }

  const tenant = resolveGameTenantFromBody(body);
  if (!tenant) {
    throw new HttpsError("permission-denied", INVALID_CREDENTIALS);
  }

  const base = gameEventBase(tenant);
  const configSnap = await deps.db
    .doc(`${base}/integrations/homeAssistant`)
    .get();
  const config = configSnap.data();
  if (!configSnap.exists || config?.enabled !== true) {
    throw new HttpsError("permission-denied", INVALID_CREDENTIALS);
  }

  const storedHash = config?.apiKeyHash;
  if (typeof storedHash !== "string" || !verifyApiKey(apiKey, storedHash)) {
    throw new HttpsError("permission-denied", INVALID_CREDENTIALS);
  }

  const now = deps.now?.() ?? admin.firestore.Timestamp.now();
  const cutoffMs = now.toDate().getTime() - RECENT_PING_WINDOW_MS;

  const membersSnap = await deps.db
    .collection(`${base}/members`)
    .where("locationOptIn", "==", true)
    .get();

  const players: PlayerLocationRow[] = [];
  for (const doc of membersSnap.docs) {
    if (players.length >= MAX_PLAYER_LOCATIONS) break;

    const data = doc.data();
    const lastLocation = data.lastLocation as Record<string, unknown> | undefined;
    if (!lastLocation) continue;

    const ts = lastLocation.timestamp as admin.firestore.Timestamp | undefined;
    if (!ts?.toDate || ts.toDate().getTime() < cutoffMs) continue;

    const lat = lastLocation.latitude;
    const lng = lastLocation.longitude;
    if (typeof lat !== "number" || typeof lng !== "number") continue;

    const presenceState =
      typeof lastLocation.presenceState === "string"
        ? lastLocation.presenceState
        : "in_game";
    const inGame =
      typeof lastLocation.inGame === "boolean"
        ? lastLocation.inGame
        : presenceState === "in_game";

    const row: PlayerLocationRow = {
      playerId: doc.id,
      latitude: lat,
      longitude: lng,
      timestamp: ts,
      presenceState,
      inGame,
    };
    const accuracy = lastLocation.accuracy;
    if (typeof accuracy === "number") row.accuracy = accuracy;
    players.push(row);
  }

  return { players };
}
