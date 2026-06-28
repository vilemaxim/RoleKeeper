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
  const cutoff = admin.firestore.Timestamp.fromMillis(cutoffMs);

  const membersSnap = await deps.db
    .collection(`${base}/members`)
    .where("locationOptIn", "==", true)
    .get();
  const optedIn = new Set(membersSnap.docs.map((d) => d.id));

  const pingsSnap = await deps.db
    .collection(`${base}/locationPings`)
    .where("timestamp", ">=", cutoff)
    .get();

  const latestByPlayer = new Map<string, Record<string, unknown>>();
  for (const doc of pingsSnap.docs) {
    const data = doc.data();
    const playerId = data.playerId;
    if (typeof playerId !== "string" || !optedIn.has(playerId)) continue;

    const ts = data.timestamp as admin.firestore.Timestamp | undefined;
    if (!ts?.toDate) continue;

    const existing = latestByPlayer.get(playerId);
    if (!existing) {
      latestByPlayer.set(playerId, data);
      continue;
    }
    const existingTs = existing.timestamp as admin.firestore.Timestamp;
    if (ts.toDate().getTime() > existingTs.toDate().getTime()) {
      latestByPlayer.set(playerId, data);
    }
  }

  const players: PlayerLocationRow[] = [];
  for (const [playerId, data] of latestByPlayer) {
    if (players.length >= MAX_PLAYER_LOCATIONS) break;

    const loc = data.location as Record<string, unknown> | undefined;
    const lat = loc?.latitude;
    const lng = loc?.longitude;
    if (typeof lat !== "number" || typeof lng !== "number") continue;

    const presenceState =
      typeof data.presenceState === "string" ? data.presenceState : "in_game";

    const row: PlayerLocationRow = {
      playerId,
      latitude: lat,
      longitude: lng,
      timestamp: data.timestamp as admin.firestore.Timestamp,
      presenceState,
      inGame: presenceState === "in_game",
    };
    const accuracy = loc?.accuracy;
    if (typeof accuracy === "number") row.accuracy = accuracy;
    players.push(row);
  }

  return { players };
}
