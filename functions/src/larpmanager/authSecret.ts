/**
 * Single Secret Manager value for LarpManager auth (avoids optional secret pairs).
 *
 * Formats:
 * - `session:<sessionid>` — use raw Django session id (no cookie name)
 * - `password:<username>:<password>` — colon in password is NOT supported (use session: instead)
 */

export function parseLarpManagerAuthSecret(raw: string): {
  sessionId?: string;
  username?: string;
  password?: string;
} {
  const s = raw.trim();
  if (s.startsWith("session:")) {
    return { sessionId: s.slice("session:".length).trim() };
  }
  if (s.startsWith("password:")) {
    const rest = s.slice("password:".length);
    const idx = rest.indexOf(":");
    if (idx <= 0) {
      throw new Error(
        'LARPMANAGER_AUTH must be password:username:password (password cannot contain ":")'
      );
    }
    return {
      username: rest.slice(0, idx).trim(),
      password: rest.slice(idx + 1).trim(),
    };
  }
  throw new Error(
    'LARPMANAGER_AUTH must start with "session:" or "password:"'
  );
}
