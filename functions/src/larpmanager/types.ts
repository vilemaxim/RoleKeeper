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
  [key: string]: unknown;
}

export interface LarpManagerSyncResult {
  characterCount: number;
  detailsFetched: number;
  exportSha256: string;
  errors: string[];
}
