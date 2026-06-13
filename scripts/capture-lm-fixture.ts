/**
 * Capture LarpManager character export JSON + registrations CSV into
 * `functions/test/fixtures/<name>/` so future debugger tasks can reproduce
 * real-world sync bugs from anonymized payloads.
 *
 * The HTTP-touching code is lazy-loaded from `functions/lib/larpmanager/*`
 * inside `captureFromLm` so that simply requiring this module (e.g. from
 * `capture-lm-fixture.test.ts`) does NOT pull in the Functions runtime
 * surface or attempt any network IO. Only the two pure scrub helpers
 * (`scrubEmailsInCsv`, `scrubCharacterExportJson`) run in CI tests.
 *
 * Usage (see --help):
 *   npx ts-node scripts/capture-lm-fixture.ts \
 *     --base-url https://lm.example.com \
 *     --event-slug my-event-2026-1 \
 *     --username svc-account --password '***' \
 *     --out functions/test/fixtures/my-event
 *
 * PII scrub is ON by default. Pass `--no-scrub` to capture raw data — the
 * output directory will automatically be suffixed with `-unscrubbed` so
 * `.gitignore` (which excludes `functions/test/fixtures/*-unscrubbed/`)
 * prevents accidental commits.
 */

import * as crypto from "crypto";
import * as fs from "fs";
import * as path from "path";

// --- PURE SCRUB HELPERS (tested in CI; no network, no Firebase) -------------

const EMAIL_REGEX = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const SENSITIVE_KEY_REGEX = /email|player|user|real_name/i;

export interface EmailScrubResult {
  scrubbed: string;
  mapping: Record<string, string>;
}

/**
 * Replace every email in `csv` with `user{N}@example.test`. The N is offset
 * by a seed-derived integer so different captures produce different numbers,
 * but within one capture the mapping is stable (same input email → same
 * placeholder, idempotent over multiple occurrences).
 *
 * Non-email content (header row, names, character names, etc.) is preserved
 * byte-for-byte. When no email matches, returns the CSV unchanged and an
 * empty mapping.
 */
export function scrubEmailsInCsv(csv: string, seed: string): EmailScrubResult {
  const offset = seedOffset(seed);
  const mapping: Record<string, string> = {};
  let next = offset + 1;

  const scrubbed = csv.replace(EMAIL_REGEX, (email) => {
    const lower = email.toLowerCase();
    if (!Object.prototype.hasOwnProperty.call(mapping, lower)) {
      mapping[lower] = `user${next}@example.test`;
      next += 1;
    }
    return mapping[lower]!;
  });

  return { scrubbed, mapping };
}

/**
 * Walk a character-export JSON object and replace string values whose key is
 * `name`, `teaser`, or matches /email|player|user|real_name/i with a
 * deterministic same-length placeholder. `uuid` and `number` are NEVER
 * touched so future sync tests can still resolve characters by those stable
 * ids. Returns a new object; the caller's input is never mutated.
 */
export function scrubCharacterExportJson<T>(json: T, seed: string): T {
  return scrubAny(json, seed, "") as T;
}

function scrubAny(value: unknown, seed: string, keyPath: string): unknown {
  if (value === null || value === undefined) return value;
  if (Array.isArray(value)) {
    return value.map((v, i) => scrubAny(v, seed, `${keyPath}[${i}]`));
  }
  if (typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (k === "uuid" || k === "number") {
        out[k] = v;
        continue;
      }
      if (
        typeof v === "string" &&
        (k === "name" || k === "teaser" || SENSITIVE_KEY_REGEX.test(k))
      ) {
        out[k] = placeholderForSeed(seed, v.length, `${keyPath}.${k}`);
        continue;
      }
      out[k] = scrubAny(v, seed, `${keyPath}.${k}`);
    }
    return out;
  }
  return value;
}

function placeholderForSeed(
  seed: string,
  length: number,
  salt: string
): string {
  if (length <= 0) return "";
  const hash = crypto
    .createHash("sha256")
    .update(`${seed}::${salt}`)
    .digest("hex");
  let out = "";
  while (out.length < length) out += hash;
  return out.slice(0, length);
}

function seedOffset(seed: string): number {
  if (!seed) return 0;
  const hash = crypto.createHash("sha256").update(seed).digest();
  return hash.readUInt32BE(0) % 10000;
}

// --- HTML scrub helper (manage-registrations capture) -----------------------

export interface HtmlScrubResult {
  scrubbed: string;
  emailMapping: Record<string, string>;
  userUuidMapping: Record<string, string>;
  displayNameReplacements: number;
}

/**
 * Scrub LarpManager's `/manage/registrations/` HTML for fixture capture.
 *
 * What it touches (deterministic, seeded):
 *   - every email-shaped substring → `user{N}@example.test` (matches the
 *     CSV scrub's identity so a single capture stays internally consistent
 *     across the two files; pass a shared `seed` and reuse the returned
 *     `emailMapping` if you need cross-file joins)
 *   - every `pop="<12-char-lm-user-uuid>"` → `pop="usr{N}<8-char-hash>"`
 *     (preserves the [a-z0-9]{4,40} shape the parser pins)
 *   - the free text inside the row's "name" `<td>` (the bit immediately
 *     before `<a class="post_popup_member">`) → `Player {N}` placeholder.
 *     This is the human's display name on LarpManager.
 *
 * What it intentionally LEAVES untouched (these are not user-identifying
 * on their own and are stable across LM exports — preserving them keeps
 * future captures comparable):
 *   - `<tr id="<registration_uuid>">` ids
 *   - character uuids inside `manage/characters/<uuid>/edit/` hrefs
 *   - structural HTML, classes, qtip attributes, CSS, JavaScript
 *
 * Caller `seed` is the same seed used by `scrubEmailsInCsv` /
 * `scrubCharacterExportJson` so a single capture run produces internally
 * consistent placeholders across all three files.
 */
export function scrubManageRegistrationsHtml(
  html: string,
  seed: string
): HtmlScrubResult {
  const offset = seedOffset(seed);
  const emailMapping: Record<string, string> = {};
  let nextEmail = offset + 1;

  let scrubbed = html.replace(EMAIL_REGEX, (email) => {
    const lower = email.toLowerCase();
    if (!Object.prototype.hasOwnProperty.call(emailMapping, lower)) {
      emailMapping[lower] = `user${nextEmail}@example.test`;
      nextEmail += 1;
    }
    return emailMapping[lower]!;
  });

  const userUuidMapping: Record<string, string> = {};
  let nextUser = offset + 1;
  scrubbed = scrubbed.replace(
    /(\bpop=["'])([a-z0-9]{4,40})(["'])/gi,
    (_full, before: string, uuid: string, after: string) => {
      const lower = uuid.toLowerCase();
      if (!Object.prototype.hasOwnProperty.call(userUuidMapping, lower)) {
        const hash = crypto
          .createHash("sha256")
          .update(`${seed}::pop::${lower}`)
          .digest("hex")
          .slice(0, 8);
        userUuidMapping[lower] = `usr${nextUser}${hash}`;
        nextUser += 1;
      }
      return `${before}${userUuidMapping[lower]}${after}`;
    }
  );

  let displayNameReplacements = 0;
  // The "name" td in each row contains free-text content followed (after
  // optional whitespace / inline tags) by an <a class="post_popup_member">
  // link. Replace that free-text run with a deterministic Player {N}.
  //
  // The negative lookahead `(?!</td>)` prevents the body from spanning
  // across an intervening `</td>` — without it, the leading `<td>` of an
  // earlier column (e.g. the edit-link td) would match and the
  // replacement would erase that whole column. The lookahead anchors us
  // to the IMMEDIATE parent td of the post_popup_member anchor.
  scrubbed = scrubbed.replace(
    /(<td[^>]*>)((?:(?!<\/td>)[\s\S])*?)(<a[^>]*\bclass=["'][^"']*\bpost_popup_member\b)/gi,
    (full, openTd: string, body: string, anchor: string) => {
      const stripped = body.replace(/<[^>]+>/g, "").trim();
      if (!stripped) return full;
      displayNameReplacements += 1;
      const label = `Player ${displayNameReplacements}`;
      return `${openTd}\n        ${label}\n        ${anchor}`;
    }
  );

  return {
    scrubbed,
    emailMapping,
    userUuidMapping,
    displayNameReplacements,
  };
}

// --- HTML scrub helper (per-character sheet capture) -----------------------

export interface CharacterSheetScrubResult {
  scrubbed: string;
  emailMapping: Record<string, string>;
  userUuidMapping: Record<string, string>;
  displayNameMapping: Record<string, string>;
}

/**
 * Scrub LarpManager's `/{slug}/character/{uuid}/` HTML for fixture capture.
 *
 * What it touches (deterministic, seeded):
 *   - every email-shaped substring → `user{N}@example.test`
 *   - every 12-char LM user uuid in `pop="…"` / `owner_uuid="…"` attributes
 *     AND in `/public/<uuid>/` URLs (where the character sheet's "Player"
 *     anchor lives) → `usr{N}<8-char-hash>` (preserves the [a-z0-9]{4,40}
 *     shape so the existing parser regexes still match)
 *   - the human display name LM renders next to the `<b>Player:</b>` row
 *     (typically the anchor text inside `<a href=".../public/<lm_user_uuid>/">`)
 *     → `Player {N}`. Once the display name is discovered, every other
 *     occurrence of that same string in the document (e.g. the
 *     "Hi, {name}!" topbar greeting) is replaced too.
 *
 * What it intentionally LEAVES untouched:
 *   - the CHARACTER uuid (the `{uuid}` segment of `/character/{uuid}/` URLs
 *     and the `og:url` meta tag) — needed for the stable fixture filename
 *   - structural HTML, CSS class names, computed numeric values
 *     (HP, affinities, Iron DR — they are not PII)
 *
 * Idempotency: re-scrubbing already-scrubbed output produces the same
 * bytes. Placeholders (`user\d+@example\.test`, `usr\d+[a-f0-9]{8}`,
 * `Player \d+`) are skipped by the per-pattern replacement loops so they
 * do not escalate on a second pass.
 */
/**
 * Idempotency markers: the regex shapes the scrubber itself produces.
 * Each replacement pass checks the candidate against the matching
 * placeholder shape and short-circuits when it matches, so re-scrubbing
 * already-scrubbed output is a no-op rather than escalating into
 * `user2@example.test`, `usr2…`, `Player 2`.
 */
const PLACEHOLDER_EMAIL_RE = /^user\d+@example\.test$/;
const PLACEHOLDER_USER_UUID_RE = /^usr\d+[a-f0-9]{8}$/;
const PLACEHOLDER_DISPLAY_NAME_RE = /^Player \d+$/;

export function scrubCharacterSheetHtml(
  html: string,
  seed: string
): CharacterSheetScrubResult {
  const offset = seedOffset(seed);
  const emailMapping: Record<string, string> = {};
  const userUuidMapping: Record<string, string> = {};
  const displayNameMapping: Record<string, string> = {};

  // --- Pass 1: emails ----------------------------------------------------
  let nextEmail = offset + 1;
  let scrubbed = html.replace(EMAIL_REGEX, (email) => {
    if (PLACEHOLDER_EMAIL_RE.test(email)) return email;
    const lower = email.toLowerCase();
    if (!Object.prototype.hasOwnProperty.call(emailMapping, lower)) {
      emailMapping[lower] = `user${nextEmail}@example.test`;
      nextEmail += 1;
    }
    return emailMapping[lower]!;
  });

  // --- Pass 2: LM user uuids --------------------------------------------
  // Same `usr{N}<8-hex>` placeholder shape used by
  // `scrubManageRegistrationsHtml` so cross-fixture cross-references stay
  // recognisable. Touches three site types on the character sheet:
  //   pop="…", (data-)owner_uuid="…", and /public/<uuid>/ URLs.
  // The character uuid in /character/<uuid>/ URLs is NOT touched.
  let nextUser = offset + 1;
  const replaceUserUuid = (uuid: string): string => {
    const lower = uuid.toLowerCase();
    if (PLACEHOLDER_USER_UUID_RE.test(lower)) return uuid;
    if (!Object.prototype.hasOwnProperty.call(userUuidMapping, lower)) {
      const hash = crypto
        .createHash("sha256")
        .update(`${seed}::usr::${lower}`)
        .digest("hex")
        .slice(0, 8);
      userUuidMapping[lower] = `usr${nextUser}${hash}`;
      nextUser += 1;
    }
    return userUuidMapping[lower]!;
  };

  scrubbed = scrubbed.replace(
    /(\b(?:pop|data-owner_uuid|owner_uuid)=["'])([a-z0-9]{4,40})(["'])/gi,
    (_full, before: string, uuid: string, after: string) =>
      `${before}${replaceUserUuid(uuid)}${after}`
  );
  scrubbed = scrubbed.replace(
    /(\/public\/)([a-z0-9]{4,40})(\/)/gi,
    (_full, before: string, uuid: string, after: string) =>
      `${before}${replaceUserUuid(uuid)}${after}`
  );

  // --- Pass 3: display name ---------------------------------------------
  // LM renders the player's display name as the anchor text of
  //   <b>Player:</b> … <a href="…/public/<lm_user_uuid>/">NAME</a>
  // — that's the canonical source. Once we have NAME we propagate the
  // replacement to every other occurrence in the document (e.g. the
  // "Hi, {name}!" topbar greeting), because LM re-uses the same string
  // verbatim and a partial scrub would leak PII through the chrome.
  const PLAYER_ROW_RE =
    /<b\b[^>]*>\s*Player\s*:?\s*(?:&nbsp;)?\s*<\/b>[\s\S]{0,300}?<a\b[^>]*href=["'][^"']*\/public\/[a-z0-9]{4,40}\/[^"']*["'][^>]*>([\s\S]*?)<\/a>/i;
  const playerMatch = PLAYER_ROW_RE.exec(scrubbed);
  if (playerMatch) {
    const nameRaw = playerMatch[1]!.replace(/<[^>]+>/g, "").trim();
    if (nameRaw && !PLACEHOLDER_DISPLAY_NAME_RE.test(nameRaw)) {
      if (!Object.prototype.hasOwnProperty.call(displayNameMapping, nameRaw)) {
        const nextName = Object.keys(displayNameMapping).length + 1;
        displayNameMapping[nameRaw] = `Player ${nextName}`;
      }
      const placeholder = displayNameMapping[nameRaw]!;
      const escaped = nameRaw.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      scrubbed = scrubbed.replace(new RegExp(escaped, "g"), placeholder);
    }
  }

  return {
    scrubbed,
    emailMapping,
    userUuidMapping,
    displayNameMapping,
  };
}

// --- CLI -------------------------------------------------------------------

interface CliOptions {
  baseUrl: string;
  eventSlug: string;
  username?: string;
  password?: string;
  sessionId?: string;
  out: string;
  scrub: boolean;
  force: boolean;
  seed: string;
  /**
   * Character uuids to additionally fetch the per-character HTML sheet
   * for (`/{slug}/character/{uuid}/`). Each is written to
   * `<out>/character-sheet-<uuid>.html` (scrubbed by default).
   * Empty array means no character sheets are captured.
   */
  characterSheetUuids: string[];
}

const HELP_TEXT = `
capture-lm-fixture — dump a LarpManager event's character export JSON and
registrations CSV into functions/test/fixtures/<name>/ for use in future
regression tests.

USAGE
  npx ts-node scripts/capture-lm-fixture.ts [options]

REQUIRED
  --base-url <url>          LarpManager base URL (e.g. https://lm.example.com)
                            Falls back to env LM_BASE_URL.
  --event-slug <slug>       Event run slug (e.g. my-event-2026-1)
                            Falls back to env LM_EVENT_SLUG.
  Either --username + --password, or --session-id (or env equivalents
  LM_USERNAME, LM_PASSWORD, LM_SESSION_ID).

OPTIONAL
  --out <path>              Output directory. Default:
                            functions/test/fixtures/<event-slug>-<timestamp>
                            When --no-scrub is set, '-unscrubbed' is appended
                            so .gitignore protects you from accidental commits.
  --no-scrub                Disable PII scrub (default: scrub ON).
  --force                   Allow overwriting an existing fixture directory.
  --seed <s>                Override the deterministic scrub seed (default:
                            event slug + timestamp). Useful for stable
                            comparisons across captures of the same event.
  --character-uuid <uuid>   Also fetch /{slug}/character/<uuid>/ and write
                            the scrubbed HTML sheet to
                            <out>/character-sheet-<uuid>.html. Repeatable.
                            Falls back to env LM_CHARACTER_UUID (comma-
                            separated list). Sheet HTML is scrubbed of
                            emails, LM user uuids (pop=, owner_uuid=,
                            /public/<uuid>/), and display names; the
                            character uuid itself is preserved.
  -h, --help                Show this help and exit.

OUTPUT
  <out>/character-export.json      Pretty-printed bulk export
  <out>/registration.csv           Raw (or email-scrubbed) registrations CSV
  <out>/manage-registrations.html  manage/registrations HTML page (the
                                   (email, lm_user_uuid, character_uuid)
                                   join table — scrubbed of emails, user
                                   uuids, and display names by default)
  <out>/character-sheet-<uuid>.html  per-character sheet HTML for each
                                   --character-uuid (scrubbed by default).
  <out>/meta.json                  { baseUrl, eventSlug, capturedAt,
                                     characterCount, registrationCount,
                                     manageRegistrationRowCount,
                                     characterSheetUuids,
                                     sha256OfExport, scrubbed, seed }

SECURITY NOTES
  - Default behaviour scrubs emails (CSV) and name/teaser/sensitive keys
    (JSON) so the fixture is safe to commit.
  - Never commit a --no-scrub capture; .gitignore excludes
    functions/test/fixtures/*-unscrubbed/ to make this hard to do by accident.
`.trim();

export function parseCliArgs(argv: string[]): CliOptions | { help: true } {
  const args = [...argv];
  let baseUrl = process.env.LM_BASE_URL ?? "";
  let eventSlug = process.env.LM_EVENT_SLUG ?? "";
  let username = process.env.LM_USERNAME ?? "";
  let password = process.env.LM_PASSWORD ?? "";
  let sessionId = process.env.LM_SESSION_ID ?? "";
  let outArg: string | undefined;
  let scrub = true;
  let force = false;
  let seed = "";
  // LM_CHARACTER_UUID accepts a comma-separated list so a single env var
  // can drive a batch of sheets; --character-uuid is repeatable for the
  // same effect on the command line. Both feed the same accumulator.
  const characterSheetUuids: string[] = [];
  const envUuids = (process.env.LM_CHARACTER_UUID ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  characterSheetUuids.push(...envUuids);

  while (args.length > 0) {
    const a = args.shift()!;
    switch (a) {
      case "-h":
      case "--help":
        return { help: true };
      case "--base-url":
        baseUrl = required(a, args.shift());
        break;
      case "--event-slug":
        eventSlug = required(a, args.shift());
        break;
      case "--username":
        username = required(a, args.shift());
        break;
      case "--password":
        password = required(a, args.shift());
        break;
      case "--session-id":
        sessionId = required(a, args.shift());
        break;
      case "--out":
        outArg = required(a, args.shift());
        break;
      case "--no-scrub":
        scrub = false;
        break;
      case "--force":
        force = true;
        break;
      case "--seed":
        seed = required(a, args.shift());
        break;
      case "--character-uuid":
        characterSheetUuids.push(required(a, args.shift()));
        break;
      default:
        throw new Error(`Unknown argument: ${a} (try --help)`);
    }
  }

  if (!baseUrl) throw new Error("--base-url (or LM_BASE_URL) is required");
  if (!eventSlug) throw new Error("--event-slug (or LM_EVENT_SLUG) is required");
  if (!sessionId && !(username && password)) {
    throw new Error(
      "Either --session-id or (--username AND --password) is required"
    );
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  let out =
    outArg ?? path.join("functions", "test", "fixtures", `${eventSlug}-${stamp}`);
  if (!scrub && !out.endsWith("-unscrubbed")) {
    // Append the safety suffix so .gitignore catches accidental commits.
    out = `${out}-unscrubbed`;
  }
  if (!seed) {
    seed = `${eventSlug}::${stamp}`;
  }

  // Dedupe while preserving order so repeated --character-uuid / overlap
  // with LM_CHARACTER_UUID does not double-fetch the same sheet.
  const dedupedSheetUuids: string[] = [];
  for (const u of characterSheetUuids) {
    if (!dedupedSheetUuids.includes(u)) dedupedSheetUuids.push(u);
  }

  return {
    baseUrl,
    eventSlug,
    username: username || undefined,
    password: password || undefined,
    sessionId: sessionId || undefined,
    out,
    scrub,
    force,
    seed,
    characterSheetUuids: dedupedSheetUuids,
  };
}

function required(flag: string, value: string | undefined): string {
  if (value === undefined) {
    throw new Error(`Missing value for ${flag}`);
  }
  return value;
}

// --- LIVE CAPTURE (lazy-loaded) --------------------------------------------

interface LmClientModule {
  establishLarpManagerSession(
    config: LarpManagerSyncConfigShape
  ): Promise<Map<string, string>>;
  fetchCharacterExportJson(
    config: LarpManagerSyncConfigShape,
    jar: Map<string, string>
  ): Promise<Record<string, CharacterExportEntry>>;
  fetchRegistrationsExportZip(
    config: LarpManagerSyncConfigShape,
    jar: Map<string, string>
  ): Promise<Buffer>;
  fetchRegistrationsManagementHtml(
    config: LarpManagerSyncConfigShape,
    jar: Map<string, string>
  ): Promise<{ html: string; finalUrl: string }>;
  fetchCharacterSheetHtml(
    config: LarpManagerSyncConfigShape,
    jar: Map<string, string>,
    characterUuid: string
  ): Promise<{ html: string; finalUrl: string }>;
}

interface LmRegistrationsModule {
  extractRegistrationCsvFromZip(buf: Buffer): string;
}

interface LarpManagerSyncConfigShape {
  baseUrl: string;
  eventSlug: string;
  username?: string;
  password?: string;
  sessionId?: string;
}

interface CharacterExportEntry {
  number?: number;
  name?: string;
  uuid?: string;
  teaser?: string;
  [key: string]: unknown;
}

export interface CaptureMeta {
  baseUrl: string;
  eventSlug: string;
  capturedAt: string;
  characterCount: number;
  registrationCount: number;
  /**
   * Number of `<tr id="…">` rows the manage/registrations HTML scrape
   * produced, as counted by the parser at capture time. May be greater
   * than `registrationCount` (which comes from the CSV) because the HTML
   * page includes organizers / staff that the CSV omits — that's the
   * specific Task 006 (v2) gap the new endpoint closes.
   */
  manageRegistrationRowCount: number;
  /**
   * Character uuids whose `/{slug}/character/{uuid}/` HTML sheet was
   * captured into this fixture directory as `character-sheet-<uuid>.html`.
   * Absent / empty array when the capture run did not request any
   * character sheets (the default — sheets are only captured when the
   * operator passes `--character-uuid` or `LM_CHARACTER_UUID`).
   *
   * Optional on the type so existing fixture meta.json files (written
   * before Task 008) round-trip without manual migration; new captures
   * always emit the field (empty array when no sheets were requested).
   */
  characterSheetUuids?: string[];
  sha256OfExport: string;
  scrubbed: boolean;
  seed: string;
}

export interface BuildCaptureMetaArgs {
  baseUrl: string;
  eventSlug: string;
  capturedAt: string;
  characterCount: number;
  registrationCount: number;
  manageRegistrationRowCount: number;
  /**
   * See `CaptureMeta.characterSheetUuids`. Order-preserved as supplied;
   * callers are expected to pass uuids in capture order. Optional so
   * existing callers (and tests) compile unchanged.
   */
  characterSheetUuids?: string[];
  /**
   * The character-export JSON serialized to a string. The SHA-256 of this
   * exact byte sequence becomes `sha256OfExport`. Passing a pre-stringified
   * value (instead of the object itself) keeps this helper free of any
   * hidden serialization choices — callers control key ordering and
   * formatting and the hash stays stable.
   */
  exportJsonString: string;
  scrubbed: boolean;
  seed: string;
}

/**
 * Pure packaging step for the values that end up in `meta.json`. Lives here
 * (rather than inline inside `captureFromLm`) so the meta shape and the
 * SHA-256 computation are verifiable in CI without any LarpManager network
 * round-trip. See `capture-lm-fixture.test.ts` for the contract.
 */
export function buildCaptureMeta(args: BuildCaptureMetaArgs): CaptureMeta {
  const sha256OfExport = crypto
    .createHash("sha256")
    .update(args.exportJsonString)
    .digest("hex");
  const meta: CaptureMeta = {
    baseUrl: args.baseUrl,
    eventSlug: args.eventSlug,
    capturedAt: args.capturedAt,
    characterCount: args.characterCount,
    registrationCount: args.registrationCount,
    manageRegistrationRowCount: args.manageRegistrationRowCount,
    sha256OfExport,
    scrubbed: args.scrubbed,
    seed: args.seed,
  };
  if (args.characterSheetUuids !== undefined) {
    meta.characterSheetUuids = [...args.characterSheetUuids];
  }
  return meta;
}

async function captureFromLm(opts: CliOptions): Promise<CaptureMeta> {
  // Lazy require so importing this module from tests does NOT trigger
  // functions/lib/ resolution. functions must be built (npm run build)
  // before invoking this script — scripts/test.sh enforces that order.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const client = require("../functions/lib/larpmanager/client") as LmClientModule;
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const regs = require("../functions/lib/larpmanager/registrations") as LmRegistrationsModule;
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const cbe = require("../functions/lib/larpmanager/charactersByEmail") as {
    parseManageRegistrationsHtml: (html: string) => Array<{
      emailLower: string;
      lmUserUuid: string;
      characterUuids: string[];
    }>;
  };

  await prepareOutputDir(opts.out, opts.force);

  const config: LarpManagerSyncConfigShape = {
    baseUrl: opts.baseUrl,
    eventSlug: opts.eventSlug,
    username: opts.username,
    password: opts.password,
    sessionId: opts.sessionId,
  };

  console.log(`> Authenticating with LarpManager at ${opts.baseUrl} …`);
  const jar = await client.establishLarpManagerSession(config);

  console.log("> Fetching character export JSON …");
  const exportJson = await client.fetchCharacterExportJson(config, jar);
  const characterCount = Object.keys(exportJson).length;

  console.log("> Fetching registrations ZIP …");
  const zip = await client.fetchRegistrationsExportZip(config, jar);
  const csvRaw = regs.extractRegistrationCsvFromZip(zip);
  const registrationCount = countCsvRows(csvRaw);

  console.log("> Fetching manage/registrations HTML …");
  const { html: manageHtmlRaw } =
    await client.fetchRegistrationsManagementHtml(config, jar);
  const manageRegistrationRowCount =
    cbe.parseManageRegistrationsHtml(manageHtmlRaw).length;

  // Fetch + scrub per-character sheets (optional; see --character-uuid).
  // Done in order so the meta.json characterSheetUuids array round-trips
  // the same order the operator passed on the CLI / env.
  const characterSheetsScrubbed: Array<{ uuid: string; html: string }> = [];
  for (const uuid of opts.characterSheetUuids) {
    console.log(`> Fetching character sheet ${uuid} …`);
    const { html: sheetRaw } = await client.fetchCharacterSheetHtml(
      config,
      jar,
      uuid
    );
    const sheetFinal = opts.scrub
      ? scrubCharacterSheetHtml(sheetRaw, opts.seed).scrubbed
      : sheetRaw;
    characterSheetsScrubbed.push({ uuid, html: sheetFinal });
  }

  const exportJsonString = JSON.stringify(exportJson);

  const finalExport = opts.scrub
    ? scrubCharacterExportJson(exportJson, opts.seed)
    : exportJson;
  const finalCsv = opts.scrub
    ? scrubEmailsInCsv(csvRaw, opts.seed).scrubbed
    : csvRaw;
  const finalManageHtml = opts.scrub
    ? scrubManageRegistrationsHtml(manageHtmlRaw, opts.seed).scrubbed
    : manageHtmlRaw;

  const meta = buildCaptureMeta({
    baseUrl: opts.baseUrl,
    eventSlug: opts.eventSlug,
    capturedAt: new Date().toISOString(),
    characterCount,
    registrationCount,
    manageRegistrationRowCount,
    characterSheetUuids: opts.characterSheetUuids,
    exportJsonString,
    scrubbed: opts.scrub,
    seed: opts.seed,
  });

  fs.writeFileSync(
    path.join(opts.out, "character-export.json"),
    JSON.stringify(finalExport, null, 2) + "\n",
    "utf8"
  );
  fs.writeFileSync(path.join(opts.out, "registration.csv"), finalCsv, "utf8");
  fs.writeFileSync(
    path.join(opts.out, "manage-registrations.html"),
    finalManageHtml,
    "utf8"
  );
  for (const { uuid, html: sheetHtml } of characterSheetsScrubbed) {
    fs.writeFileSync(
      path.join(opts.out, `character-sheet-${uuid}.html`),
      sheetHtml,
      "utf8"
    );
  }
  fs.writeFileSync(
    path.join(opts.out, "meta.json"),
    JSON.stringify(meta, null, 2) + "\n",
    "utf8"
  );

  return meta;
}

/**
 * Ensure `out` exists and is safe to write into.
 *
 * Refuses to clobber an existing NON-EMPTY directory unless `force` is true
 * — this protects against accidentally overwriting a previously-captured
 * fixture that another test depends on. An existing empty directory is
 * always accepted (it's effectively the same as creating one).
 */
async function prepareOutputDir(out: string, force: boolean): Promise<void> {
  if (fs.existsSync(out)) {
    const entries = fs.readdirSync(out);
    if (entries.length > 0 && !force) {
      throw new Error(
        `Output directory ${out} already exists and is not empty. ` +
          "Pass --force to overwrite."
      );
    }
  } else {
    fs.mkdirSync(out, { recursive: true });
  }
}

/**
 * Count data rows in a CSV (excluding the header). Handles CRLF and stray
 * blank lines. This is a rough count and feeds `meta.json.registrationCount`;
 * the production sync uses `parseRegistrationRowsFromCsv` to dedupe by email.
 */
export function countCsvRows(csv: string): number {
  const lines = csv.split(/\r?\n/).filter((l) => l.trim().length > 0);
  return Math.max(0, lines.length - 1);
}

async function main(argv: string[]): Promise<void> {
  let parsed;
  try {
    parsed = parseCliArgs(argv);
  } catch (e) {
    console.error(`Error: ${(e as Error).message}`);
    console.error("Run with --help for usage.");
    process.exit(2);
  }
  if ("help" in parsed && parsed.help) {
    console.log(HELP_TEXT);
    return;
  }

  const meta = await captureFromLm(parsed as CliOptions);
  console.log("");
  console.log(`Fixture written to ${(parsed as CliOptions).out}`);
  const sheetCount = meta.characterSheetUuids?.length ?? 0;
  console.log(
    `   ${meta.characterCount} characters, ${meta.registrationCount} ` +
      `CSV registrations, ${meta.manageRegistrationRowCount} ` +
      `manage/registrations rows, ${sheetCount} ` +
      `character sheet${sheetCount === 1 ? "" : "s"}, ` +
      `scrubbed=${meta.scrubbed}, seed=${meta.seed}`
  );
}

// Only run when invoked directly, never when imported by tests.
if (require.main === module) {
  main(process.argv.slice(2)).catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
