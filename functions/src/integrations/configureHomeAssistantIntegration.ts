import * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { gameEventBase, resolveGameTenantFromBody } from "../gameTenant";
import { generateApiKey, hashApiKey } from "./apiKey";

const STAFF_ROLES = new Set(["owner", "superAdmin", "staff"]);

export interface ConfigureHomeAssistantBody {
  gameId?: string;
  instanceId?: string;
  eventSlug?: string;
  enabled?: boolean;
  regenerateKey?: boolean;
}

export interface ConfigureHomeAssistantDeps {
  db: admin.firestore.Firestore;
  now?: () => admin.firestore.Timestamp;
}

export async function runConfigureHomeAssistantIntegration(
  deps: ConfigureHomeAssistantDeps,
  request: CallableRequest<ConfigureHomeAssistantBody>
): Promise<{ apiKey?: string }> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const body = request.data ?? {};
  const tenant = resolveGameTenantFromBody(body);
  if (!tenant) {
    throw new HttpsError(
      "invalid-argument",
      "gameId (tenantKey) or instanceId+eventSlug is required"
    );
  }

  const base = gameEventBase(tenant);
  const memberSnap = await deps.db.doc(`${base}/members/${uid}`).get();
  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "Not a member of this game");
  }
  const role = memberSnap.data()?.role;
  if (typeof role !== "string" || !STAFF_ROLES.has(role)) {
    throw new HttpsError(
      "permission-denied",
      "Only staff or above can configure Home Assistant integration"
    );
  }

  const configRef = deps.db.doc(`${base}/integrations/homeAssistant`);
  const existing = (await configRef.get()).data() ?? {};
  const enabled = body.enabled === true;
  const regenerateKey = body.regenerateKey === true;

  const payload: Record<string, unknown> = {
    enabled,
    updatedAt: deps.now?.() ?? admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: uid,
  };

  let apiKeyPlaintext: string | undefined;
  const needsKey =
    regenerateKey ||
    (enabled && typeof existing.apiKeyHash !== "string");
  if (needsKey) {
    apiKeyPlaintext = generateApiKey();
    payload.apiKeyHash = hashApiKey(apiKeyPlaintext);
    if (typeof existing.createdAt === "undefined") {
      payload.createdAt = deps.now?.() ?? admin.firestore.FieldValue.serverTimestamp();
      payload.createdBy = uid;
    }
  }

  await configRef.set(payload, { merge: true });

  return apiKeyPlaintext ? { apiKey: apiKeyPlaintext } : {};
}
