/**
 * Game tenant: `games/{instanceId}/events/{eventSlug}/...`
 */

export interface GameTenant {
  instanceId: string;
  eventSlug: string;
}

export const TENANT_KEY_SEP = "::";

export function tenantKey(t: GameTenant): string {
  return `${t.instanceId}${TENANT_KEY_SEP}${t.eventSlug}`;
}

export function parseTenantKey(key: string): GameTenant | null {
  const sep = key.indexOf(TENANT_KEY_SEP);
  if (sep <= 0 || sep >= key.length - TENANT_KEY_SEP.length) return null;
  return {
    instanceId: key.slice(0, sep),
    eventSlug: key.slice(sep + TENANT_KEY_SEP.length),
  };
}

export function gameEventBase(t: GameTenant): string {
  return `games/${t.instanceId}/events/${t.eventSlug}`;
}

export function gameEventDoc(t: GameTenant): string {
  return `${gameEventBase(t)}`;
}

export function resolveGameTenantFromBody(body: {
  gameId?: string;
  instanceId?: string;
  eventSlug?: string;
}): GameTenant | null {
  const key = body.gameId?.trim();
  if (key) {
    const fromKey = parseTenantKey(key);
    if (fromKey) return fromKey;
  }
  const inst = body.instanceId?.trim();
  const slug = body.eventSlug?.trim();
  if (inst && slug) {
    return { instanceId: inst, eventSlug: slug };
  }
  return null;
}

/** `.../games/{instanceId}/events/{eventSlug}/larpManagerSyncSettings/config` */
export function tenantFromSyncSettingsPath(path: string): GameTenant | null {
  const parts = path.split("/");
  const gamesIdx = parts.indexOf("games");
  if (gamesIdx < 0 || gamesIdx + 4 >= parts.length) return null;
  if (parts[gamesIdx + 2] !== "events") return null;
  return {
    instanceId: parts[gamesIdx + 1]!,
    eventSlug: parts[gamesIdx + 3]!,
  };
}
