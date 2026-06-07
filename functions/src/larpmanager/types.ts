/**
 * LarpManager read-sync types (see docs/LARPMANAGER_INTEGRATION.md).
 */

export interface LarpManagerSyncConfig {
  baseUrl: string;
  /** Event run slug, e.g. my-event-2025-1 */
  eventSlug: string;
  /** Django username for dedicated export user (password auth). */
  username?: string;
  password?: string;
  /** Raw session id value only (no "sessionid=" prefix). If set, login is skipped. */
  sessionId?: string;
  /** Path for login GET/POST, default /login/ */
  loginPath?: string;
  /** Fetch per-character inventory + abilities JSON after bulk export. */
  fetchDetails: boolean;
}

export interface LarpManagerCharacterExport {
  number?: number;
  name?: string;
  uuid?: string;
  teaser?: string;
  /**
   * Optional email of the LarpManager user assigned to this character. LM
   * uses one of several field names across installations / event configs
   * (`player_email` on hosted larpmanager.com; older installs sometimes use
   * `player`, `user_email`, or a bare `email`). These fields are declared so
   * downstream code can be explicit about what it consumes, but the
   * organizer email-mirror lookup in `playerCharacters.ts` walks ALL
   * string-valued fields rather than relying on any single key so it stays
   * resilient to future LM schema drift.
   */
  player_email?: string;
  player?: string;
  user_email?: string;
  email?: string;
  [key: string]: unknown;
}

export interface LarpManagerSyncResult {
  characterCount: number;
  detailsFetched: number;
  exportSha256: string;
  errors: string[];
}
