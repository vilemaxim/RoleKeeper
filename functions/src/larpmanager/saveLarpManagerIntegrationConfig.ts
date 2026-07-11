/**
 * Callable handler logic for saving LarpManager integration config.
 * Extracted from `index.ts` for unit testing (Task 005).
 */

import * as admin from "firebase-admin";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import {
  gameEventBase,
  resolveGameTenantFromBody,
  tenantKey,
  type GameTenant,
} from "../gameTenant";
import { establishLarpManagerSession } from "./client";
import { toHttpsErrorForLarpManagerCredentialSave } from "./gcpErrors";
import {
  fetchOrganizerEmailsFromLarpManager,
  ORGANIZERS_COLLECTION,
} from "./organizers";
import type { LarpManagerSyncConfig } from "./types";

export interface SaveLarpManagerIntegrationConfigBody {
  gameId?: string;
  instanceId?: string;
  eventSlug?: string;
  baseUrl?: string;
  loginPath?: string;
  username?: string;
  password?: string;
}

export interface CallerOrganizerStatus {
  organizerEmails: string[];
  isOrganizer: boolean;
}

export interface SaveLarpManagerIntegrationConfigDeps {
  db: admin.firestore.Firestore;
  getProjectId: () => string;
  upsertSecret: (
    projectId: string,
    tenantKey: string,
    payloadUtf8: string
  ) => Promise<void>;
  resolveCallerOrganizerStatus?: (
    db: admin.firestore.Firestore,
    tenant: GameTenant,
    config: LarpManagerSyncConfig,
    callerEmailLower: string
  ) => Promise<CallerOrganizerStatus>;
}

export function larpRegistryEventPath(tenant: GameTenant): string {
  return `larpRegistry/${tenant.instanceId}/events/${tenant.eventSlug}`;
}

export async function defaultResolveCallerOrganizerStatus(
  _db: admin.firestore.Firestore,
  _tenant: GameTenant,
  config: LarpManagerSyncConfig,
  callerEmailLower: string
): Promise<CallerOrganizerStatus> {
  const jar = await establishLarpManagerSession(config);
  const organizerEmails = await fetchOrganizerEmailsFromLarpManager(config, jar);
  const normalized = organizerEmails.map((e) => e.toLowerCase());
  return {
    organizerEmails: normalized,
    isOrganizer: normalized.includes(callerEmailLower),
  };
}

/** Reads the cached LM organizers mirror (used in unit tests). */
export async function resolveCallerOrganizerStatusFromMirror(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  _config: LarpManagerSyncConfig,
  callerEmailLower: string
): Promise<CallerOrganizerStatus> {
  const base = gameEventBase(tenant);
  const coll = db.collection(`${base}/${ORGANIZERS_COLLECTION}`);
  const snap = await coll.get();
  const organizerEmails = snap.docs
    .map((d) => String(d.data().emailLower ?? "").toLowerCase())
    .filter((e) => e.length > 0);
  return {
    organizerEmails,
    isOrganizer: organizerEmails.includes(callerEmailLower),
  };
}

export async function runSaveLarpManagerIntegrationConfig(
  deps: SaveLarpManagerIntegrationConfigDeps,
  request: CallableRequest<SaveLarpManagerIntegrationConfigBody>
): Promise<{ ok: boolean; bootstrapOwner: boolean }> {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data ?? {};
  const tenant = resolveGameTenantFromBody(data);
  if (!tenant) {
    throw new HttpsError(
      "invalid-argument",
      "gameId (tenantKey) or instanceId+eventSlug is required"
    );
  }

  const base = gameEventBase(tenant);
  const tKey = tenantKey(tenant);

  const memberSnap = await deps.db.doc(`${base}/members/${request.auth.uid}`).get();
  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "Not a member of this game");
  }
  const role = (memberSnap.data() as { role?: string })?.role;
  const intRef = deps.db.doc(`${base}/larpManagerIntegration/config`);
  const existing = await intRef.get();
  const hadCreds = existing.data()?.credentialsConfigured === true;

  if (role !== "owner" && role !== "superAdmin" && hadCreds) {
    throw new HttpsError(
      "permission-denied",
      "Only owner or superAdmin can configure LarpManager integration"
    );
  }

  const baseUrl = String(data.baseUrl ?? "").trim();
  const eventSlug = String(data.eventSlug ?? "").trim();
  if (!baseUrl || !eventSlug) {
    throw new HttpsError(
      "invalid-argument",
      "baseUrl and eventSlug are required"
    );
  }

  const loginPath = String(data.loginPath ?? "/login/").trim() || "/login/";

  const u = typeof data.username === "string" ? data.username.trim() : "";
  const p = typeof data.password === "string" ? data.password : "";
  const bothProvided = u.length > 0 && p.length > 0;
  const bothEmpty = u.length === 0 && p.length === 0;

  if (!bothProvided && !bothEmpty) {
    throw new HttpsError(
      "invalid-argument",
      "Provide both username and password, or leave both empty to keep existing credentials"
    );
  }

  const db = deps.db;
  const uid = request.auth.uid;

  let secretUpdated = false;
  let projectId: string;
  try {
    projectId = deps.getProjectId();
  } catch (e) {
    throw toHttpsErrorForLarpManagerCredentialSave(e, "unknown");
  }

  if (bothProvided) {
    const payload = `password:${u}:${p}`;
    try {
      await deps.upsertSecret(projectId, tKey, payload);
    } catch (e) {
      throw toHttpsErrorForLarpManagerCredentialSave(e, projectId);
    }
    secretUpdated = true;
  }

  if (!hadCreds && !secretUpdated) {
    throw new HttpsError(
      "failed-precondition",
      "Username and password are required the first time you save LarpManager integration"
    );
  }

  await intRef.set(
    {
      baseUrl,
      eventSlug,
      loginPath,
      credentialsConfigured: hadCreds || secretUpdated,
      tenantKey: tKey,
      instanceId: tenant.instanceId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedByUid: uid,
    },
    { merge: true }
  );

  const isFirstCredentialSave = secretUpdated && !hadCreds;
  let bootstrapOwner = false;

  if (
    isFirstCredentialSave &&
    role !== "owner" &&
    role !== "superAdmin"
  ) {
    const callerEmail = request.auth.token.email;
    if (!callerEmail || typeof callerEmail !== "string") {
      throw new HttpsError(
        "failed-precondition",
        "Your sign-in must include an email address to verify LarpManager organizer status"
      );
    }

    const syncConfig: LarpManagerSyncConfig = {
      baseUrl,
      eventSlug,
      username: u,
      password: p,
      loginPath,
    };
    const resolveOrganizer =
      deps.resolveCallerOrganizerStatus ?? defaultResolveCallerOrganizerStatus;
    const { organizerEmails, isOrganizer } = await resolveOrganizer(
      db,
      tenant,
      syncConfig,
      callerEmail.trim().toLowerCase()
    );

    if (organizerEmails.length > 0 && !isOrganizer) {
      throw new HttpsError(
        "permission-denied",
        "Only a LarpManager event organizer can perform the first LarpManager integration setup"
      );
    }

    if (isOrganizer) {
      const ownerPatch = { role: "owner" };
      await db.doc(`${base}/members/${uid}`).set(ownerPatch, { merge: true });
      await db.doc(`users/${uid}/gameMemberships/${tKey}`).set(ownerPatch, {
        merge: true,
      });
      bootstrapOwner = true;

      const registryRef = db.doc(larpRegistryEventPath(tenant));
      const registryNow = admin.firestore.FieldValue.serverTimestamp();
      const registryCore = {
        tenantKey: tKey,
        instanceId: tenant.instanceId,
        eventSlug: tenant.eventSlug,
        larpManagerBaseUrl: baseUrl,
        larpManagerEventSlug: eventSlug,
        organizerAccessConfigured: true,
        updatedAt: registryNow,
      };
      const registrySnap = await registryRef.get();
      await registryRef.set(
        registrySnap.exists
          ? registryCore
          : {
              ...registryCore,
              displayName: eventSlug,
              createdByUid: uid,
              createdAt: registryNow,
            },
        { merge: true }
      );
    }
  }

  return { ok: true, bootstrapOwner };
}
