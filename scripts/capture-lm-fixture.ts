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
  -h, --help                Show this help and exit.

OUTPUT
  <out>/character-export.json   Pretty-printed bulk export
  <out>/registration.csv        Raw (or email-scrubbed) registrations CSV
  <out>/meta.json               { baseUrl, eventSlug, capturedAt,
                                  characterCount, registrationCount,
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
  fetchDetails: boolean;
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
  return {
    baseUrl: args.baseUrl,
    eventSlug: args.eventSlug,
    capturedAt: args.capturedAt,
    characterCount: args.characterCount,
    registrationCount: args.registrationCount,
    sha256OfExport,
    scrubbed: args.scrubbed,
    seed: args.seed,
  };
}

async function captureFromLm(opts: CliOptions): Promise<CaptureMeta> {
  // Lazy require so importing this module from tests does NOT trigger
  // functions/lib/ resolution. functions must be built (npm run build)
  // before invoking this script — scripts/test.sh enforces that order.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const client = require("../functions/lib/larpmanager/client") as LmClientModule;
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const regs = require("../functions/lib/larpmanager/registrations") as LmRegistrationsModule;

  await prepareOutputDir(opts.out, opts.force);

  const config: LarpManagerSyncConfigShape = {
    baseUrl: opts.baseUrl,
    eventSlug: opts.eventSlug,
    username: opts.username,
    password: opts.password,
    sessionId: opts.sessionId,
    fetchDetails: false,
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

  const exportJsonString = JSON.stringify(exportJson);

  const finalExport = opts.scrub
    ? scrubCharacterExportJson(exportJson, opts.seed)
    : exportJson;
  const finalCsv = opts.scrub
    ? scrubEmailsInCsv(csvRaw, opts.seed).scrubbed
    : csvRaw;

  const meta = buildCaptureMeta({
    baseUrl: opts.baseUrl,
    eventSlug: opts.eventSlug,
    capturedAt: new Date().toISOString(),
    characterCount,
    registrationCount,
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
  console.log(`✅ Fixture written to ${(parsed as CliOptions).out}`);
  console.log(
    `   ${meta.characterCount} characters, ${meta.registrationCount} ` +
      `registrations, scrubbed=${meta.scrubbed}, seed=${meta.seed}`
  );
}

// Only run when invoked directly, never when imported by tests.
if (require.main === module) {
  main(process.argv.slice(2)).catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
