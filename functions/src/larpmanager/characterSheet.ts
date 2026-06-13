/**
 * Parser for LarpManager's `/{slug}/character/{uuid}/` HTML character
 * sheet — surfaces the rich gameplay stats (Player, Status, Race,
 * Cultivation Tier, Hit Points/Essence, Total/Effective affinities,
 * Iron DR, etc.) that LM renders server-side but never exposes through
 * `/export/char/` or the `abilities/inventory` JSON endpoints.
 *
 * Exports:
 *   - `CharacterSheet`, `CharacterSheetSection`, `CharacterSheetRow`
 *     — the structured projection shape downstream code (Task 010 UI,
 *     Task 009 sync wiring) consumes.
 *   - `CharacterSheetParseError` — raised when the HTML is missing the
 *     minimal scaffolding the parser expects. Sync wiring catches it
 *     and records a structured `LarpManagerSyncResult.errors[]` entry
 *     instead of crashing the run.
 *   - `parseCharacterSheetHtml(html)` — the parser itself. Pure, no IO,
 *     no third-party HTML deps (regex-based, same posture as
 *     `charactersByEmail.ts`).
 *
 * Behaviour is pinned by `characterSheet.test.ts` against both
 * synthetic snippets and the committed Heldrek fixture.
 */

/** One label/value cell from a character-sheet section. */
export interface CharacterSheetRow {
  label: string;
  value: string;
}

/** One section as LM renders it on the HTML page. */
export interface CharacterSheetSection {
  /** Verbatim LM section heading. Empty string when LM groups rows
   * outside of a named `<h2>`/`<h3>` heading (the typical "stats block"
   * at the top of the sheet). */
  label: string;
  /** Rows in source-HTML order. */
  rows: CharacterSheetRow[];
}

/**
 * Structured projection of an LM character-sheet HTML page.
 *
 * The `Presentation` block (`<h2 class="c">Presentation</h2>` plus the
 * adjacent `<div class="teaser">…</div>`) is carved out into its own
 * fields so Task 010's UI can render it next to the existing
 * `CharacterStats.teaser` / `CharacterStats.presentation` block without
 * double-rendering it as just another row.
 */
export interface CharacterSheet {
  /** Sections in the exact order LM renders them on the HTML page. */
  sections: CharacterSheetSection[];
  /** Inner HTML of the `<div class="teaser">…</div>` block, trimmed.
   * Absent when the sheet has no teaser. */
  teaserHtml?: string;
  /** Inner HTML between `<h2 class="c">Presentation</h2>` and the next
   * `<h2>` (or end of the character container), trimmed. Absent when
   * empty. */
  presentationHtml?: string;
}

/**
 * Thrown when the HTML does not contain the minimal scaffolding the
 * parser expects (no `<body>`, no recognisable character-sheet
 * container). Sync wiring (Task 009) catches this and appends a
 * structured entry to `LarpManagerSyncResult.errors[]`.
 */
export class CharacterSheetParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CharacterSheetParseError";
  }
}

/**
 * Parse the structured projection out of an LM character-sheet HTML
 * page. See `CharacterSheet` for the shape contract; the unit tests in
 * `characterSheet.test.ts` pin behaviour against both synthetic HTML
 * snippets and the committed Heldrek fixture.
 *
 * Algorithm (regex-based, same posture as `charactersByEmail.ts` so the
 * dependency surface stays the same — no jsdom, no cheerio):
 *
 * 1. Guard the scaffolding: throw `CharacterSheetParseError` when
 *    `html` lacks a `<body>` or a `class="character"` container.
 * 2. Carve out the teaser block (`<div class="teaser">…</div>` inner
 *    HTML, trimmed) into `teaserHtml` and rewrite the working copy with
 *    that block removed so it cannot leak into a `sections[]` row.
 * 3. Carve out the Presentation block: the content between
 *    `<h2 class="c">Presentation</h2>` and the next `<h2>` (or end of
 *    the working copy) becomes `presentationHtml`, and the same range
 *    is removed from the working copy.
 * 4. Walk the remaining HTML token-by-token. Each `<h2>`/`<h3>`
 *    heading opens a new section (verbatim label, preserves source
 *    order — no humanisation, no alphabetisation). Each
 *    `<b>Label:</b>VALUE` row is appended to the current section. VALUE
 *    is the text between `</b>` and the next sibling boundary (next
 *    `<b>`, closing `</div>`, or next `<h2>`/`<h3>`), tag-stripped and
 *    whitespace-collapsed.
 * 5. Drop rows whose value is empty after trim; drop sections that
 *    have no surviving rows (don't surface "Field: " noise or empty
 *    abilities-table-only headings).
 *
 * Value-cell whitespace policy: `<br>` and internal whitespace collapse
 * to a single space (matching how LM renders inline cells visually);
 * the parser does not preserve hard newlines because LM never renders
 * them for the stat block this task targets.
 *
 * @throws CharacterSheetParseError when `html` lacks the minimal
 *   scaffolding (no `<body>`, no recognisable character container).
 */
export function parseCharacterSheetHtml(html: string): CharacterSheet {
  if (
    !html ||
    !/<body\b/i.test(html) ||
    !/class=["'][^"']*\bcharacter\b/i.test(html)
  ) {
    throw new CharacterSheetParseError(
      "HTML lacks the minimal character-sheet scaffolding " +
        "(no <body>, or no .character container)"
    );
  }

  let working = html;

  // Carve out teaser (inner HTML of <div class="teaser">…</div>).
  let teaserHtml: string | undefined;
  const teaserRe =
    /<div\b[^>]*\bclass=["'][^"']*\bteaser\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i;
  const teaserMatch = teaserRe.exec(working);
  if (teaserMatch) {
    const inner = teaserMatch[1]!.trim();
    if (inner) teaserHtml = inner;
    working =
      working.slice(0, teaserMatch.index) +
      working.slice(teaserMatch.index + teaserMatch[0].length);
  }

  // Carve out Presentation block (h2.c "Presentation" through to next h2).
  let presentationHtml: string | undefined;
  const presStartRe =
    /<h2\b[^>]*\bclass=["'][^"']*\bc\b[^"']*["'][^>]*>\s*Presentation\s*<\/h2>/i;
  const presMatch = presStartRe.exec(working);
  if (presMatch) {
    const afterStart = presMatch.index + presMatch[0].length;
    const after = working.slice(afterStart);
    const nextH2Rel = after.search(/<h2\b/i);
    const blockEnd = nextH2Rel >= 0 ? afterStart + nextH2Rel : working.length;
    const inner = working.slice(afterStart, blockEnd).trim();
    if (inner) presentationHtml = inner;
    working = working.slice(0, presMatch.index) + working.slice(blockEnd);
  }

  // Walk h2/h3 headings + <b>Label:</b> rows in source-HTML order.
  const sections: CharacterSheetSection[] = [];
  let current: CharacterSheetSection = { label: "", rows: [] };
  sections.push(current);

  const tokenRe =
    /<h([23])\b[^>]*>([\s\S]*?)<\/h\1>|<b\b[^>]*>([\s\S]*?)<\/b>/gi;
  let m: RegExpExecArray | null;
  while ((m = tokenRe.exec(working)) !== null) {
    if (m[1] !== undefined) {
      const label = decodeAndCollapse(m[2]!);
      if (label) {
        current = { label, rows: [] };
        sections.push(current);
      }
      continue;
    }
    const label = cleanLabel(m[3]!);
    const valueStart = m.index + m[0].length;
    const remaining = working.slice(valueStart);
    const stop = /<b\b|<\/div>|<h[23]\b/i.exec(remaining);
    const valueRaw = stop ? remaining.slice(0, stop.index) : remaining;
    const value = decodeAndCollapse(stripInlineTags(valueRaw));
    if (label && value) {
      current.rows.push({ label, value });
    }
  }

  const result: CharacterSheet = {
    sections: sections.filter((s) => s.rows.length > 0),
  };
  if (teaserHtml !== undefined) result.teaserHtml = teaserHtml;
  if (presentationHtml !== undefined) result.presentationHtml = presentationHtml;
  return result;
}

/** Strip ALL inline tags (e.g. <a>, <span>, <br>, <em>) so the text
 * content of a value cell can be measured and compared. */
function stripInlineTags(s: string): string {
  return s.replace(/<[^>]+>/g, "");
}

/** Decode the handful of HTML entities LM emits in the stat block,
 * collapse runs of whitespace (incl. NBSP) to a single space, and trim
 * leading/trailing whitespace. Wider entity coverage isn't needed for
 * the stats this task targets and would inflate the dependency surface. */
function decodeAndCollapse(s: string): string {
  return s
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, " ")
    .trim();
}

/** Normalise the inside of a `<b>` label tag: decode entities, collapse
 * whitespace, then strip the trailing colon LM uses to separate
 * label/value. */
function cleanLabel(raw: string): string {
  return decodeAndCollapse(raw).replace(/\s*:\s*$/, "").trim();
}
