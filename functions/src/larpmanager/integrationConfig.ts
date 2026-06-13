/**
 * Load per-game LarpManager integration from Firestore + Secret Manager.
 */

import type * as admin from "firebase-admin";

import {
  type GameTenant,
  gameEventBase,
  tenantKey,
} from "../gameTenant";
import { parseLarpManagerAuthSecret } from "./authSecret";
import { accessLarpManagerAuthSecret } from "./secretManager";
import type { LarpManagerSyncConfig } from "./types";

export interface LarpManagerIntegrationPublic {
  baseUrl: string;
  eventSlug: string;
  loginPath: string;
  credentialsConfigured: boolean;
}

/**
 * Project a stored `larpManagerIntegration/config` doc into the
 * public-shape used downstream.
 *
 * Task 012 / ADR 0001 removed the `fetchDetails` field from the
 * projection. The loader still TOLERATES a legacy `fetchDetails: bool`
 * field on the stored doc — we did not run a Firestore migration to
 * delete the stale field, so existing docs may still carry it. We
 * silently ignore it here and never surface it on the returned
 * object. See docs/adr/0001-remove-fetchdetails-toggle.md.
 */
export function parseIntegrationDoc(
  data: admin.firestore.DocumentData | undefined
): LarpManagerIntegrationPublic | null {
  if (!data) return null;
  const baseUrl = String(data.baseUrl ?? "").trim();
  const eventSlug = String(data.eventSlug ?? "").trim();
  if (!baseUrl || !eventSlug) return null;
  return {
    baseUrl,
    eventSlug,
    loginPath: String(data.loginPath ?? "/login/").trim() || "/login/",
    credentialsConfigured: data.credentialsConfigured === true,
  };
}

export async function loadLarpManagerSyncConfigForGame(
  db: admin.firestore.Firestore,
  projectId: string,
  tenant: GameTenant
): Promise<LarpManagerSyncConfig | null> {
  const snap = await db
    .doc(`${gameEventBase(tenant)}/larpManagerIntegration/config`)
    .get();
  const pub = parseIntegrationDoc(snap.data());
  if (!pub) return null;

  const raw = await accessLarpManagerAuthSecret(projectId, tenantKey(tenant));
  if (!raw?.trim()) return null;

  const auth = parseLarpManagerAuthSecret(raw);
  return {
    baseUrl: pub.baseUrl,
    eventSlug: pub.eventSlug,
    username: auth.username,
    password: auth.password,
    sessionId: auth.sessionId,
    loginPath: pub.loginPath,
  };
}
