/**
 * RoleKeeper Cloud Functions
 */

import * as crypto from "crypto";

import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

import {
  gameEventBase,
  resolveGameTenantFromBody,
  tenantFromSyncSettingsPath,
  tenantKey,
} from "./gameTenant";
import { loadLarpManagerSyncConfigForGame } from "./larpmanager/integrationConfig";
import { resolveLarpManagerPlayerAccess } from "./larpmanager/playerAccess";
import { runLarpManagerSync } from "./larpmanager/sync";
import { runSyncMyLarpManagerCharacter } from "./larpmanager/syncMyCharacter";
import { toHttpsErrorForLarpManagerCredentialSave } from "./larpmanager/gcpErrors";
import { upsertLarpManagerAuthSecret } from "./larpmanager/secretManager";
import {
  larpManagerSyncSettingsRef,
  parseLarpManagerSyncSettings,
  shouldRunScheduledLarpManagerSync,
} from "./larpmanager/syncSettings";
import { sanitizeLocation as sanitizeLocationPayload } from "./location/locationPayload";
import {
  runRecordLocationPing,
  type RecordLocationPingBody,
} from "./location/recordLocationPing";
import {
  runGetLatestPlayerLocations,
  type GetLatestPlayerLocationsBody,
} from "./integrations/getLatestPlayerLocations";
import {
  runConfigureHomeAssistantIntegration,
  type ConfigureHomeAssistantBody,
} from "./integrations/configureHomeAssistantIntegration";
import {
  runGetDeathInterventionSecrets,
  type DeathInterventionSecretsBody,
} from "./deathInterventionSecrets";

admin.initializeApp();

const REGION = "us-central1";

const ALLOWED_ACTIVE_EVENT_TYPES = new Set([
  "deathTimerStarted",
  "deathTimerExpired",
  "medicStoppedDeathTimer",
  "medicRevivedCharacter",
  "medicRevivedCharacterOffline",
]);

function mintActiveEventDocId(ts: admin.firestore.Timestamp): string {
  const d = ts.toDate();
  const y = d.getUTCFullYear();
  const mo = String(d.getUTCMonth() + 1).padStart(2, "0");
  const da = String(d.getUTCDate()).padStart(2, "0");
  const h = String(d.getUTCHours()).padStart(2, "0");
  const mi = String(d.getUTCMinutes()).padStart(2, "0");
  const s = String(d.getUTCSeconds()).padStart(2, "0");
  const ms = String(d.getUTCMilliseconds()).padStart(3, "0");
  const tie = crypto.randomBytes(3).toString("hex");
  return `${y}${mo}${da}${h}${mi}${s}${ms}_${tie}`;
}

function sanitizeLocation(
  loc: unknown
): Record<string, unknown> | undefined {
  return sanitizeLocationPayload(loc);
}

/**
 * Creates `games/{instanceId}/events/{eventSlug}/activeEvents/{eventId}`.
 */
export const createActiveGameEvent = onCall(
  { region: REGION },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;
    const body = request.data as Record<string, unknown>;

    const tenant = resolveGameTenantFromBody({
      gameId: body?.gameId as string | undefined,
      instanceId: body?.instanceId as string | undefined,
      eventSlug: body?.eventSlug as string | undefined,
    });
    const type = body?.type as string | undefined;
    const playerId = body?.playerId as string | undefined;
    const relatedPlayerId = body?.relatedPlayerId as string | undefined;
    const characterId = body?.characterId as string | undefined;
    const relatedCharacterId = body?.relatedCharacterId as string | undefined;
    const chainActivityEventId = body?.chainActivityEventId as string | undefined;

    if (!tenant) {
      throw new HttpsError(
        "invalid-argument",
        "gameId (tenantKey) or instanceId+eventSlug is required"
      );
    }
    if (!type || !ALLOWED_ACTIVE_EVENT_TYPES.has(type)) {
      throw new HttpsError("invalid-argument", "Invalid or missing type");
    }
    if (!playerId || typeof playerId !== "string") {
      throw new HttpsError("invalid-argument", "playerId is required");
    }

    const tKey = tenantKey(tenant);
    const base = gameEventBase(tenant);

    const memberSnap = await admin
      .firestore()
      .doc(`${base}/members/${uid}`)
      .get();
    if (!memberSnap.exists) {
      throw new HttpsError("permission-denied", "Not a member of this game");
    }

    const isActor =
      uid === playerId ||
      (typeof relatedPlayerId === "string" && uid === relatedPlayerId);
    if (!isActor) {
      throw new HttpsError(
        "permission-denied",
        "Must be playerId or relatedPlayerId"
      );
    }

    const ts = admin.firestore.Timestamp.now();
    const eventId = mintActiveEventDocId(ts);

    const payload: Record<string, unknown> = {
      id: eventId,
      gameId: tKey,
      tenantKey: tKey,
      instanceId: tenant.instanceId,
      eventSlug: tenant.eventSlug,
      type,
      playerId,
      timestamp: ts,
    };
    if (relatedPlayerId && relatedPlayerId.length > 0) {
      payload.relatedPlayerId = relatedPlayerId;
    }
    if (characterId && characterId.length > 0) {
      payload.characterId = characterId;
    }
    if (relatedCharacterId && relatedCharacterId.length > 0) {
      payload.relatedCharacterId = relatedCharacterId;
    }
    if (chainActivityEventId && chainActivityEventId.length > 0) {
      payload.chainActivityEventId = chainActivityEventId;
    }
    const loc = sanitizeLocation(body?.location);
    if (loc) {
      payload.location = loc;
    }

    await admin
      .firestore()
      .collection(`${base}/activeEvents`)
      .doc(eventId)
      .set(payload);

    return { eventId };
  }
);

export const onPlayerActivityEventCreated = onDocumentCreated(
  {
    document:
      "games/{instanceId}/events/{eventSlug}/playerActivityEvents/{eventId}",
    region: REGION,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    const playerId = data?.playerId as string | undefined;
    if (!playerId) return;
    const instanceId = event.params.instanceId;
    const eventSlug = event.params.eventSlug;
    const tKey =
      (data?.tenantKey as string | undefined) ??
      `${instanceId}::${eventSlug}`;
    await admin.firestore()
      .doc(`users/${playerId}/activityEvents/${snap.id}`)
      .set({ ...data, id: snap.id, gameId: tKey, tenantKey: tKey });
  }
);

export const onActiveGameEventCreated = onDocumentCreated(
  {
    document: "games/{instanceId}/events/{eventSlug}/activeEvents/{eventId}",
    region: REGION,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() as Record<string, unknown>;
    const instanceId = event.params.instanceId;
    const eventSlug = event.params.eventSlug;
    const base = `games/${instanceId}/events/${eventSlug}`;
    const eventId = snap.id;
    const playerId = data?.playerId as string | undefined;
    const relatedPlayerId = data?.relatedPlayerId as string | undefined;
    const characterId = data?.characterId as string | undefined;
    const relatedCharacterId = data?.relatedCharacterId as string | undefined;
    const tKey =
      (data?.tenantKey as string | undefined) ??
      (data?.gameId as string | undefined) ??
      `${instanceId}::${eventSlug}`;

    const basePayload = { ...data, id: eventId, gameId: tKey, tenantKey: tKey };

    const batch = admin.firestore().batch();
    if (playerId) {
      batch.set(
        admin.firestore().doc(`users/${playerId}/activityEvents/${eventId}`),
        basePayload
      );
    }
    if (relatedPlayerId && relatedPlayerId !== playerId) {
      batch.set(
        admin.firestore().doc(`users/${relatedPlayerId}/activityEvents/${eventId}`),
        basePayload
      );
    }
    if (characterId) {
      batch.set(
        admin
          .firestore()
          .doc(`${base}/characters/${characterId}/events/${eventId}`),
        basePayload
      );
    }
    if (relatedCharacterId && relatedCharacterId !== characterId) {
      batch.set(
        admin
          .firestore()
          .doc(
            `${base}/characters/${relatedCharacterId}/events/${eventId}`
          ),
        basePayload
      );
    }
    await batch.commit();
  }
);

function getGoogleCloudProjectId(): string {
  const fromEnv =
    process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  if (fromEnv) return fromEnv;
  const fromApp = admin.app().options.projectId;
  if (fromApp) return fromApp;
  throw new Error(
    "Could not resolve Google Cloud project id (GCLOUD_PROJECT / Firebase app)"
  );
}

export const saveLarpManagerIntegrationConfig = onCall(
  { region: REGION, memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    try {
      if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }
      const data = request.data as {
        gameId?: string;
        instanceId?: string;
        eventSlug?: string;
        baseUrl?: string;
        loginPath?: string;
        username?: string;
        password?: string;
      };
      const tenant = resolveGameTenantFromBody(data);
      if (!tenant) {
        throw new HttpsError(
          "invalid-argument",
          "gameId (tenantKey) or instanceId+eventSlug is required"
        );
      }

      const base = gameEventBase(tenant);
      const tKey = tenantKey(tenant);

      const memberSnap = await admin
        .firestore()
        .doc(`${base}/members/${request.auth.uid}`)
        .get();
      if (!memberSnap.exists) {
        throw new HttpsError("permission-denied", "Not a member of this game");
      }
      const role = (memberSnap.data() as { role?: string })?.role;
      const intRef = admin
        .firestore()
        .doc(`${base}/larpManagerIntegration/config`);
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

      const loginPath =
        String(data.loginPath ?? "/login/").trim() || "/login/";

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

      const db = admin.firestore();
      const uid = request.auth.uid;

      let secretUpdated = false;
      let projectId: string;
      try {
        projectId = getGoogleCloudProjectId();
      } catch (e) {
        logger.error("saveLarpManagerIntegrationConfig: project id", e);
        throw toHttpsErrorForLarpManagerCredentialSave(e, "unknown");
      }

      if (bothProvided) {
        const payload = `password:${u}:${p}`;
        try {
          await upsertLarpManagerAuthSecret(projectId, tKey, payload);
        } catch (e) {
          logger.error("saveLarpManagerIntegrationConfig: Secret Manager", e);
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

      // Task 012 / ADR 0001: no `fetchDetails` key on the saved payload.
      // Legacy `fetchDetails: bool` on existing docs is tolerated by the
      // loader (`parseIntegrationDoc`) and is overwritten on next save
      // here only insofar as merge writes leave untouched fields alone.
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

      // Bootstrap: first person to save credentials becomes owner so they can manage the game.
      if (
        secretUpdated &&
        !hadCreds &&
        role !== "owner" &&
        role !== "superAdmin"
      ) {
        const ownerPatch = { role: "owner" };
        await db.doc(`${base}/members/${uid}`).set(ownerPatch, { merge: true });
        await db.doc(`users/${uid}/gameMemberships/${tKey}`).set(ownerPatch, {
          merge: true,
        });
      }

      return { ok: true, bootstrapOwner: secretUpdated && !hadCreds };
    } catch (e) {
      if (e instanceof HttpsError) {
        throw e;
      }
      logger.error("saveLarpManagerIntegrationConfig failed", e);
      const msg = e instanceof Error ? e.message : String(e);
      throw new HttpsError("internal", msg.slice(0, 500));
    }
  }
);

export const larpManagerSyncScheduled = onSchedule(
  {
    schedule: "every 15 minutes",
    region: REGION,
    timeZone: "Etc/UTC",
    memory: "512MiB",
    timeoutSeconds: 540,
  },
  async () => {
    const db = admin.firestore();
    const settingsSnap = await db
      .collectionGroup("larpManagerSyncSettings")
      .where("scheduledSyncEnabled", "==", true)
      .get();

    if (settingsSnap.empty) {
      logger.info(
        "larpManagerSyncScheduled: no games with scheduled sync enabled"
      );
      return;
    }

    const projectId = getGoogleCloudProjectId();

    for (const doc of settingsSnap.docs) {
      const tenant = tenantFromSyncSettingsPath(doc.ref.path);
      if (!tenant) {
        logger.warn("larpManagerSyncScheduled: could not resolve tenant");
        continue;
      }
      const base = gameEventBase(tenant);
      const tKey = tenantKey(tenant);
      try {
        const cfg = await loadLarpManagerSyncConfigForGame(
          db,
          projectId,
          tenant
        );
        if (!cfg) {
          logger.info(
            `larpManagerSyncScheduled: skip ${tKey} — missing integration or credentials`
          );
          continue;
        }
        const summaryRef = db.doc(`${base}/larpManagerMirrorMeta/summary`);
        const [summarySnap, syncSettingsSnap] = await Promise.all([
          summaryRef.get(),
          larpManagerSyncSettingsRef(db, tenant).get(),
        ]);
        const settings = parseLarpManagerSyncSettings(syncSettingsSnap.data());
        const lastSynced = summarySnap.data()?.lastSyncedAt as
          | admin.firestore.Timestamp
          | undefined;
        const decision = shouldRunScheduledLarpManagerSync(
          settings,
          lastSynced ?? null,
          new Date()
        );
        if (!decision.run) {
          logger.info(
            `larpManagerSyncScheduled: skip ${tKey} (${decision.reason})`
          );
          continue;
        }
        await runLarpManagerSync(db, tenant, cfg);
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        logger.error(`larpManagerSyncScheduled failed tenant=${tKey}`, e);
        await db
          .doc(`${base}/larpManagerMirrorMeta/summary`)
          .set(
            {
              lastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
              lastOk: false,
              lastError: msg.slice(0, 1500),
            },
            { merge: true }
          );
      }
    }
  }
);

export const runLarpManagerSyncCallable = onCall(
  {
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const body = request.data as {
      gameId?: string;
      instanceId?: string;
      eventSlug?: string;
    };
    const tenant = resolveGameTenantFromBody(body);
    if (!tenant) {
      throw new HttpsError(
        "invalid-argument",
        "gameId (tenantKey) or instanceId+eventSlug is required"
      );
    }

    const base = gameEventBase(tenant);
    const memberSnap = await admin
      .firestore()
      .doc(`${base}/members/${request.auth.uid}`)
      .get();
    if (!memberSnap.exists) {
      throw new HttpsError("permission-denied", "Not a member of this game");
    }
    const role = (memberSnap.data() as { role?: string })?.role;
    if (role !== "owner" && role !== "superAdmin") {
      throw new HttpsError(
        "permission-denied",
        "Only owner or superAdmin can run LarpManager sync"
      );
    }

    const projectId = getGoogleCloudProjectId();
    const cfg = await loadLarpManagerSyncConfigForGame(
      admin.firestore(),
      projectId,
      tenant
    );
    if (!cfg) {
      throw new HttpsError(
        "failed-precondition",
        "Configure LarpManager integration (LM Integration) and credentials for this game"
      );
    }

    return runLarpManagerSync(admin.firestore(), tenant, cfg);
  }
);

/**
 * Task 013: player-driven per-character refresh. An authenticated user
 * can re-pull just THEIR owned character's inventory / abilities /
 * sheet from LarpManager without waiting for the next admin or
 * scheduled sync. Ownership is verified against
 * `${gameEventBase(tenant)}/characters/{characterUuid}.ownerId`.
 *
 * The implementation lives in `larpmanager/syncMyCharacter.ts` so it
 * can be unit-tested in isolation with an injected config loader (the
 * real loader reaches into Secret Manager, which is not available
 * under `node --test`).
 */
export const syncMyLarpManagerCharacterCallable = onCall(
  {
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 60,
  },
  async (request) => {
    return runSyncMyLarpManagerCharacter(
      {
        db: admin.firestore(),
        projectId: getGoogleCloudProjectId(),
        loadConfig: loadLarpManagerSyncConfigForGame,
      },
      request
    );
  }
);

/**
 * Syncs LarpManager registrations into Firestore and checks whether the
 * caller's email is registered for the event. Never trusts client self-report.
 */
export const checkLarpManagerRegistrationCallable = onCall(
  {
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const email = request.auth.token.email;
    if (!email || typeof email !== "string") {
      throw new HttpsError(
        "failed-precondition",
        "Your sign-in must include an email address to verify LarpManager registration"
      );
    }

    const body = request.data as {
      gameId?: string;
      instanceId?: string;
      eventSlug?: string;
      forceRefresh?: boolean;
    };
    const tenant = resolveGameTenantFromBody(body);
    if (!tenant) {
      throw new HttpsError(
        "invalid-argument",
        "gameId (tenantKey) or instanceId+eventSlug is required"
      );
    }

    const uid = request.auth.uid;
    const base = gameEventBase(tenant);
    const memberSnap = await admin.firestore().doc(`${base}/members/${uid}`).get();
    if (!memberSnap.exists) {
      throw new HttpsError("permission-denied", "Not a member of this game");
    }
    const projectId = getGoogleCloudProjectId();
    const cfg = await loadLarpManagerSyncConfigForGame(
      admin.firestore(),
      projectId,
      tenant
    );
    if (!cfg) {
      throw new HttpsError(
        "failed-precondition",
        "LarpManager is not connected for this event yet. Ask your organizer to "
          + "complete LM Integration in RoleKeeper."
      );
    }

    try {
      // `resolveLarpManagerPlayerAccess` returns sync failures as
      // `organizerSyncError` / `registrationSyncError` / `characterSyncError`
      // fields on the result; we only reach this catch for genuinely
      // unexpected exceptions (e.g. Firestore unavailable, programming bug).
      return await resolveLarpManagerPlayerAccess(
        admin.firestore(),
        tenant,
        cfg,
        uid,
        email,
        { forceSync: body.forceRefresh === true }
      );
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      logger.error("checkLarpManagerRegistrationCallable failed", e);
      throw new HttpsError("internal", msg.slice(0, 500));
    }
  }
);

/** Records a GPS ping for an opted-in player during a live event. */
export const recordLocationPing = onCall(
  { region: REGION },
  async (request) =>
    runRecordLocationPing(
      { db: admin.firestore() },
      request as CallableRequest<RecordLocationPingBody>
    )
);

/** Returns latest player positions for Home Assistant (API key auth). */
export const getLatestPlayerLocations = onCall(
  { region: REGION },
  async (request) =>
    runGetLatestPlayerLocations(
      { db: admin.firestore() },
      request as CallableRequest<GetLatestPlayerLocationsBody>
    )
);

/** Staff+ configuration for Home Assistant integration (API key generation). */
export const configureHomeAssistantIntegration = onCall(
  { region: REGION },
  async (request) =>
    runConfigureHomeAssistantIntegration(
      { db: admin.firestore() },
      request as CallableRequest<ConfigureHomeAssistantBody>
    )
);

/** Per-event TOTP and death QR signing secrets for authenticated members. */
export const getDeathInterventionSecrets = onCall(
  { region: REGION },
  async (request) =>
    runGetDeathInterventionSecrets(
      { db: admin.firestore() },
      request as CallableRequest<DeathInterventionSecretsBody>
    )
);
