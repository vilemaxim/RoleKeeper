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
  // Task 012 / ADR 0001: the `fetchDetails: boolean` flag has been
  // removed. Admin and scheduled syncs always pull full per-character
  // data (inventory + abilities + parsed HTML sheet) for every
  // character with a uuid. See docs/adr/0001-remove-fetchdetails-toggle.md.
}

export interface LarpManagerCharacterExport {
  number?: number;
  name?: string;
  uuid?: string;
  teaser?: string;
  /**
   * Display name of the LarpManager user assigned to this character.
   * Always present on hosted larpmanager.com exports; absent on hidden
   * characters and on events without owner assignments. Never matchable
   * against a RoleKeeper email — see the Task 006 (second iteration)
   * analysis for why the email-mirror join was abandoned in favour of
   * the manage/registrations HTML scrape (`charactersByEmail.ts`).
   */
  owner?: string;
  /**
   * Opaque 12-char LarpManager UuidMixin id (`[a-z0-9]{12}`) of the user
   * assigned to this character. Stable across LM exports for the same
   * user, but NOT discoverable from a RoleKeeper email alone — the
   * manage/registrations HTML scrape is what joins email → owner_uuid →
   * character_uuid for us.
   */
  owner_uuid?: string;
  /**
   * Historical optimistic email fields kept declared (but no longer
   * populated by the hosted LM endpoint we tested) so downstream code
   * can still type-check usages introduced before Task 006's second
   * iteration. The organizer email-mirror lookup in `playerCharacters.ts`
   * still walks ALL string-valued fields so any LM install that DOES
   * surface emails on the export keeps working.
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
  /**
   * Count of characters whose per-character LM HTML sheet was both
   * fetched AND parsed without error during the sync. Independent of
   * `detailsFetched` so a sheet fetch/parse failure for one character
   * cannot regress the existing inventory+abilities counter (Task 009).
   */
  sheetsFetched: number;
  exportSha256: string;
  errors: string[];
}
