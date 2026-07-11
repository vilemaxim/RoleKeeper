import * as crypto from "crypto";

import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import type { Firestore } from "firebase-admin/firestore";

import {
  gameEventBase,
  resolveGameTenantFromBody,
} from "./gameTenant";

export interface DeathInterventionSecretsBody {
  gameId?: string;
  instanceId?: string;
  eventSlug?: string;
}

function generateBase32Secret(byteLength = 20): string {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const bytes = crypto.randomBytes(byteLength);
  let bits = 0;
  let value = 0;
  let output = "";
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    output += alphabet[(value << (5 - bits)) & 31];
  }
  return output.slice(0, 32);
}

export async function runGetDeathInterventionSecrets(
  deps: { db: Firestore },
  request: CallableRequest<DeathInterventionSecretsBody>
): Promise<{ totpSecret: string; qrSigningSecret: string }> {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const uid = request.auth.uid;
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

  const base = gameEventBase(tenant);
  const memberSnap = await deps.db.doc(`${base}/members/${uid}`).get();
  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "Not a member of this game");
  }

  const configRef = deps.db.doc(`${base}/eventSession/config`);
  const configSnap = await configRef.get();
  const data = configSnap.data() ?? {};

  let totpSecret = data.deathTotpSecret as string | undefined;
  let qrSigningSecret = data.deathQrSigningSecret as string | undefined;

  if (!totpSecret || !qrSigningSecret) {
    totpSecret = generateBase32Secret();
    qrSigningSecret = crypto.randomBytes(32).toString("hex");
    await configRef.set(
      {
        deathTotpSecret: totpSecret,
        deathQrSigningSecret: qrSigningSecret,
      },
      { merge: true }
    );
  }

  return { totpSecret, qrSigningSecret };
}
