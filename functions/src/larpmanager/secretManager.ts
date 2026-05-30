/**
 * Per-game LarpManager credentials in Google Cloud Secret Manager.
 * Secret id: lm-auth-{sanitizedGameId}
 */

import { SecretManagerServiceClient } from "@google-cloud/secret-manager";

const client = new SecretManagerServiceClient();

/** Secret Manager secret ids: [a-zA-Z0-9_-]+ */
export function larpManagerSecretIdForGame(gameId: string): string {
  const s = gameId
    .replace(/[^a-zA-Z0-9_-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 200);
  const base = s.length > 0 ? s : "game";
  return `lm-auth-${base}`;
}

export async function upsertLarpManagerAuthSecret(
  projectId: string,
  gameId: string,
  payloadUtf8: string
): Promise<void> {
  const secretId = larpManagerSecretIdForGame(gameId);
  const parent = `projects/${projectId}`;
  const name = `${parent}/secrets/${secretId}`;

  try {
    await client.getSecret({ name });
  } catch (e: unknown) {
    const code = (e as { code?: number }).code;
    if (code !== 5) throw e;
    await client.createSecret({
      parent,
      secretId,
      secret: {
        replication: { automatic: {} },
      },
    });
  }

  await client.addSecretVersion({
    parent: name,
    payload: {
      data: Buffer.from(payloadUtf8, "utf8"),
    },
  });
}

export async function accessLarpManagerAuthSecret(
  projectId: string,
  gameId: string
): Promise<string | null> {
  const secretId = larpManagerSecretIdForGame(gameId);
  const name = `projects/${projectId}/secrets/${secretId}/versions/latest`;
  try {
    const [version] = await client.accessSecretVersion({ name });
    const buf = version.payload?.data;
    if (!buf) return null;
    return Buffer.from(buf as Uint8Array).toString("utf8");
  } catch (e: unknown) {
    const code = (e as { code?: number }).code;
    if (code === 5) return null;
    throw e;
  }
}
