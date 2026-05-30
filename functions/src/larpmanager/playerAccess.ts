/**
 * Resolve player access: LarpManager registration + organizer role by email.
 */

import * as admin from "firebase-admin";

import type { GameTenant } from "../gameTenant";
import { gameEventBase, tenantKey } from "../gameTenant";
import {
  isEmailLarpManagerOrganizer,
  MEMBERSHIP_ORGANIZER_EMAIL_FIELD,
  MEMBERSHIP_ROLE_FIELD,
  syncLarpManagerOrganizers,
} from "./organizers";
import {
  buildCharacterCreatePageUrl,
  syncPlayerCharactersForUser,
} from "./playerCharacters";
import {
  buildRegistrationPageUrl,
  MEMBERSHIP_REGISTERED_AT_FIELD,
  MEMBERSHIP_REGISTERED_EMAIL_FIELD,
  registrationDocIdForEmail,
  syncLarpManagerRegistrations,
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

  const [orgSync, regSync] = await Promise.all([
    syncLarpManagerOrganizers(db, tenant, config, { force }),
    syncLarpManagerRegistrations(db, tenant, config, { force }),
  ]);

  const metaSnap = await db
    .doc(`${base}/larpManagerRegistrationsMeta/summary`)
    .get();
  const syncedAtTs = metaSnap.data()?.lastSyncedAt as
    | admin.firestore.Timestamp
    | undefined;
  const syncedAt = syncedAtTs ? syncedAtTs.toDate().toISOString() : null;

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

  let charSync = { hasCharacter: false, characterCount: 0 };
  if (isOrganizer || registered) {
    charSync = await syncPlayerCharactersForUser(
      db,
      tenant,
      config,
      uid,
      emailLower
    );
  }

  const hasCharacter = isOrganizer || charSync.hasCharacter;

  let characterMessage: string | null = null;
  if (!isOrganizer && registered && !charSync.hasCharacter) {
    characterMessage =
      "Create a character on LarpManager for this event, assign it to your " +
      "registration, then tap Check character status.";
  }

  return {
    registered: isOrganizer || registered,
    isOrganizer,
    role,
    registrationPageUrl,
    registrationCount: regSync.registrationCount,
    organizerCount: orgSync.organizerCount,
    syncedAt,
    message,
    hasCharacter,
    characterCount: charSync.characterCount,
    characterCreatePageUrl,
    characterMessage,
  };
}
