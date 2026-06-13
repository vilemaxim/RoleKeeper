/**
 * Resolve player access: LarpManager registration + organizer role by email.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import type { GameTenant } from "../gameTenant";
import { gameEventBase, tenantKey } from "../gameTenant";
import {
  syncLarpManagerCharactersByEmail,
  type LarpManagerCharactersByEmailSyncResult,
} from "./charactersByEmail";
import {
  isEmailLarpManagerOrganizer,
  MEMBERSHIP_ORGANIZER_EMAIL_FIELD,
  MEMBERSHIP_ROLE_FIELD,
  ORGANIZERS_META_DOC,
  syncLarpManagerOrganizers,
  type LarpManagerOrganizerSyncResult,
} from "./organizers";
import {
  buildCharacterCreatePageUrl,
  syncPlayerCharactersForUser,
} from "./playerCharacters";
import {
  buildRegistrationPageUrl,
  MEMBERSHIP_REGISTERED_AT_FIELD,
  MEMBERSHIP_REGISTERED_EMAIL_FIELD,
  REGISTRATIONS_META_DOC,
  registrationDocIdForEmail,
  syncLarpManagerRegistrations,
  type LarpManagerRegistrationSyncResult,
} from "./registrations";
import type { LarpManagerSyncConfig } from "./types";

export interface LarpManagerPlayerAccessResult {
  registered: boolean;
  isOrganizer: boolean;
  role: "owner" | "player";
  registrationPageUrl: string;
  registrationCount: number;
  organizerCount: number;
  syncedAt: string | null;
  message: string | null;
  hasCharacter: boolean;
  characterCount: number;
  characterCreatePageUrl: string;
  characterMessage: string | null;
  /** Short, user-safe error string when the organizer sync failed; `null` on success. */
  organizerSyncError: string | null;
  /** Short, user-safe error string when the registration sync failed; `null` on success. */
  registrationSyncError: string | null;
  /** Short, user-safe error string when the character sync failed; `null` on success. */
  characterSyncError: string | null;
}

/**
 * Trim and strip credentials / stack noise from an error so it is safe to
 * return to a Flutter caller. Never include the raw email, character names,
 * or service-account credentials.
 */
function safeSyncErrorMessage(err: unknown, fallback: string): string {
  const raw = err instanceof Error ? err.message : String(err ?? "");
  const trimmed = raw.split("\n")[0]?.trim() ?? "";
  if (!trimmed) return fallback;
  return trimmed.length > 240 ? `${trimmed.slice(0, 237)}…` : trimmed;
}

export async function resolveLarpManagerPlayerAccess(
  db: admin.firestore.Firestore,
  tenant: GameTenant,
  config: LarpManagerSyncConfig,
  uid: string,
  email: string,
  options?: { forceSync?: boolean }
): Promise<LarpManagerPlayerAccessResult> {
  const emailLower = email.trim().toLowerCase();
  const registrationPageUrl = buildRegistrationPageUrl(config);
  const base = gameEventBase(tenant);
  const tKey = tenantKey(tenant);
  const force = options?.forceSync === true;

  // Run the three HTTP-backed syncs independently so one failure cannot
  // hide the others or block the downstream character sync. The
  // characters-by-email sync was added in Task 006 (second iteration)
  // to populate the manage/registrations HTML join table. The downstream
  // collaborators (`isEmailLarpManagerOrganizer`, the cached reg-doc
  // lookup, and `syncPlayerCharactersForUser`'s Path-0/Path-C fallbacks)
  // all read cached Firestore docs, so a degraded sync still serves
  // previously-good data.
  const [orgSettled, regSettled, charsByEmailSettled] = await Promise.allSettled(
    [
      syncLarpManagerOrganizers(db, tenant, config, { force }),
      syncLarpManagerRegistrations(db, tenant, config, { force }),
      syncLarpManagerCharactersByEmail(db, tenant, config, { force }),
    ]
  );

  let orgSync: LarpManagerOrganizerSyncResult | null = null;
  let organizerSyncError: string | null = null;
  if (orgSettled.status === "fulfilled") {
    orgSync = orgSettled.value;
  } else {
    organizerSyncError = safeSyncErrorMessage(
      orgSettled.reason,
      "LarpManager organizer sync failed"
    );
    logger.error("resolveLarpManagerPlayerAccess: organizer sync failed", {
      sync: "syncLarpManagerOrganizers",
      eventBase: base,
      error: organizerSyncError,
    });
  }

  let regSync: LarpManagerRegistrationSyncResult | null = null;
  let registrationSyncError: string | null = null;
  if (regSettled.status === "fulfilled") {
    regSync = regSettled.value;
  } else {
    registrationSyncError = safeSyncErrorMessage(
      regSettled.reason,
      "LarpManager registration sync failed"
    );
    logger.error("resolveLarpManagerPlayerAccess: registration sync failed", {
      sync: "syncLarpManagerRegistrations",
      eventBase: base,
      error: registrationSyncError,
    });
  }

  // The HTML characters-by-email sync is best-effort: when it succeeds
  // it populates the most authoritative join table; when it fails we
  // continue with the existing CSV + email-mirror paths and surface the
  // error to the caller so the UI can show actionable copy if needed.
  // No public *SyncError surface for this one yet — folded into
  // `characterSyncError` below if the resolver itself fails. Failures
  // here are common during the orga_registrations permission rollout
  // and shouldn't blast through to the operator as a separate row.
  let charsByEmailSync: LarpManagerCharactersByEmailSyncResult | null = null;
  if (charsByEmailSettled.status === "fulfilled") {
    charsByEmailSync = charsByEmailSettled.value;
  } else {
    logger.warn(
      "resolveLarpManagerPlayerAccess: characters-by-email sync failed " +
        "(non-fatal; falling back to CSV+mirror paths)",
      {
        sync: "syncLarpManagerCharactersByEmail",
        eventBase: base,
        error: safeSyncErrorMessage(
          charsByEmailSettled.reason,
          "LarpManager characters-by-email sync failed"
        ),
      }
    );
  }
  void charsByEmailSync;

  // Counts fall back to the most recent cached meta totals so the UI still
  // reflects last-known-good numbers when a refresh failed.
  let organizerCount = orgSync?.organizerCount ?? 0;
  let registrationCount = regSync?.registrationCount ?? 0;
  if (orgSync === null) {
    try {
      const metaSnap = await db.doc(`${base}/${ORGANIZERS_META_DOC}`).get();
      const cached = metaSnap.data()?.organizerCount;
      if (typeof cached === "number") organizerCount = cached;
    } catch {
      // Cached meta unavailable — leave at 0.
    }
  }

  // The registrations-meta doc gives us `syncedAt`. Treat its read as best-
  // effort: if Firestore is unhappy we surface a null timestamp rather than
  // poisoning the whole response.
  let syncedAt: string | null = null;
  try {
    const metaSnap = await db
      .doc(`${base}/${REGISTRATIONS_META_DOC}`)
      .get();
    const data = metaSnap.data();
    const syncedAtTs = data?.lastSyncedAt as
      | admin.firestore.Timestamp
      | undefined;
    if (syncedAtTs) syncedAt = syncedAtTs.toDate().toISOString();
    if (regSync === null && typeof data?.registrationCount === "number") {
      registrationCount = data.registrationCount as number;
    }
  } catch (e) {
    logger.warn(
      "resolveLarpManagerPlayerAccess: registrations meta read failed",
      {
        eventBase: base,
        error: e instanceof Error ? e.message : String(e),
      }
    );
  }

  // Cached organizer / registration lookups never touch HTTP, so they are
  // safe to run even when the upstream sync failed — they just return
  // whatever the last successful sync wrote.
  const isOrganizer = await isEmailLarpManagerOrganizer(
    db,
    tenant,
    emailLower
  );

  const regSnap = await db
    .doc(
      `${base}/larpManagerRegistrations/${registrationDocIdForEmail(emailLower)}`
    )
    .get();
  const registered = regSnap.exists;

  const memberPatch: Record<string, unknown> = {};
  if (isOrganizer) {
    memberPatch[MEMBERSHIP_ROLE_FIELD] = "owner";
    memberPatch[MEMBERSHIP_ORGANIZER_EMAIL_FIELD] = emailLower;
  }
  if (registered) {
    memberPatch[MEMBERSHIP_REGISTERED_AT_FIELD] =
      admin.firestore.FieldValue.serverTimestamp();
    memberPatch[MEMBERSHIP_REGISTERED_EMAIL_FIELD] = emailLower;
  }

  if (Object.keys(memberPatch).length > 0) {
    await db.doc(`${base}/members/${uid}`).set(memberPatch, { merge: true });
    await db
      .doc(`users/${uid}/gameMemberships/${tKey}`)
      .set(memberPatch, { merge: true });
  }

  const role: "owner" | "player" = isOrganizer ? "owner" : "player";
  const characterCreatePageUrl = buildCharacterCreatePageUrl(config);

  let message: string | null = null;
  if (!isOrganizer && !registered) {
    message =
      "Sign in to LarpManager with the same email you use in RoleKeeper, " +
      "complete event registration, then tap Check registration status.";
  }

  let charSync: {
    hasCharacter: boolean;
    characterCount: number;
    organizerLookupAttempted: boolean;
    organizerLookupMatches: number;
    htmlLookupAttempted: boolean;
    htmlLookupMatches: number;
  } = {
    hasCharacter: false,
    characterCount: 0,
    organizerLookupAttempted: false,
    organizerLookupMatches: 0,
    htmlLookupAttempted: false,
    htmlLookupMatches: 0,
  };
  let characterSyncError: string | null = null;
  if (isOrganizer || registered) {
    try {
      charSync = await syncPlayerCharactersForUser(
        db,
        tenant,
        config,
        uid,
        emailLower,
        { isOrganizer }
      );
    } catch (e) {
      characterSyncError = safeSyncErrorMessage(
        e,
        "LarpManager character sync failed"
      );
      logger.error("resolveLarpManagerPlayerAccess: character sync failed", {
        sync: "syncPlayerCharactersForUser",
        eventBase: base,
        error: characterSyncError,
      });
      // Fall through: probe the cached `/characters` collection so a user
      // who already has a synced character doc isn't told "No character yet"
      // just because today's refresh attempt failed.
      try {
        const cachedChars = await db
          .collection(`${base}/characters`)
          .where("ownerId", "==", uid)
          .where("isArchived", "==", false)
          .limit(1)
          .get();
        if (!cachedChars.empty) {
          charSync = {
            hasCharacter: true,
            characterCount: cachedChars.size,
            organizerLookupAttempted: false,
            organizerLookupMatches: 0,
            htmlLookupAttempted: false,
            htmlLookupMatches: 0,
          };
        }
      } catch {
        // Cached read unavailable — leave at the safe default.
      }
    }
  }

  // `hasCharacter` is the truth: only true when there's an actual
  // `/characters` doc owned by this uid. We previously short-circuited this
  // to `true` for every organizer, which lied to the Flutter caller (the
  // Characters screen reads /characters directly and showed an empty state
  // anyway) and suppressed the diagnostic `characterMessage`. See Task 006.
  const hasCharacter = charSync.hasCharacter;

  // Build a single piece of actionable copy when we couldn't associate a
  // character. The three cases are deliberately distinct so each surfaces
  // the smallest fix the user can take on the LarpManager side:
  //   1. Organizer + email-mirror lookup found nothing — their LM email
  //      doesn't match any character on this event.
  //   2. Organizer + email-mirror lookup found multiple — they must pick
  //      one on LM-side; we won't auto-assign across characters.
  //   3. Plain registered player with no character — standard
  //      "create one on LM" copy (the pre-Task-006 behaviour).
  let characterMessage: string | null = null;
  if (!hasCharacter) {
    if (isOrganizer && charSync.organizerLookupAttempted) {
      if (charSync.organizerLookupMatches === 0) {
        characterMessage =
          "Your LarpManager email doesn't match any character on this event. " +
          "Confirm that your LarpManager character's assigned-player email " +
          "matches the email you used to sign in to RoleKeeper.";
      } else if (charSync.organizerLookupMatches > 1) {
        characterMessage =
          "Multiple LarpManager characters list your email. RoleKeeper won't " +
          "auto-pick — open LarpManager, reassign all but one of those " +
          "characters away from your email, then tap Check character status.";
      }
    } else if (registered) {
      characterMessage =
        "Create a character on LarpManager for this event, assign it to your " +
        "registration, then tap Check character status.";
    }
  }

  return {
    registered: isOrganizer || registered,
    isOrganizer,
    role,
    registrationPageUrl,
    registrationCount,
    organizerCount,
    syncedAt,
    message,
    hasCharacter,
    characterCount: charSync.characterCount,
    characterCreatePageUrl,
    characterMessage,
    organizerSyncError,
    registrationSyncError,
    characterSyncError,
  };
}
