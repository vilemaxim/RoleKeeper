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

/** One ability row inside a `<table class="mob abilities">` in the LM
 *  sheet body block. Task 014. */
export interface SheetAbility {
  /** `<h4>` text with the trailing `" (NN)"` cost paren stripped. */
  name: string;
  /** Digits captured from the trailing `" (NN)"` paren of the `<h4>`,
   *  serialised as a string (LM has historically used either int or
   *  string for cost — string-form matches the existing
   *  `_asScalarString` tolerance in `CharacterStats.fromMirrorDoc`).
   *  Absent when the `<h4>` has no `" (NN)"` suffix. */
  cost?: string;
  /** Flat plain text of the row's `<td>` cell — inline tags stripped,
   *  whitespace + entities collapsed. Absent when the `<td>` is empty
   *  or whitespace-only. */
  description?: string;
}

/** One ability group from the sheet body block, e.g. "Shadow Affinity
 *  Skills". Each `<h3>` inside the sheet block paired with the
 *  immediately-following `<table class="mob abilities">` becomes one
 *  group. Order matches the LM source HTML verbatim. Task 014. */
export interface SheetAbilityGroup {
  /** Verbatim text of the `<h3>` heading. */
  label: string;
  /** Rows in source-HTML order. */
  abilities: SheetAbility[];
}

/** One row of an inventory card's pool-balances list — e.g.
 *  "Monster Cores: 0" → { label: "Monster Cores", value: "0" }.
 *  Task 014. */
export interface SheetInventoryBalance {
  label: string;
  value: string;
}

/** One `<div class="inventory-card">` block from the sheet body —
 *  title, balances, optional "View Details" link. Task 014. */
export interface SheetInventory {
  /** First `<h4>` inside the card. */
  title: string;
  /** Pool balances in source-HTML order. Rows whose `<li>` lacks a `:`
   *  separator are dropped. */
  balances: SheetInventoryBalance[];
  /** `href` of the card's `<a class="btn">` (the "View Details" link).
   *  Absent when the card has no such button. */
  detailsUrl?: string;
}

/** Structured projection of the LM sheet body block — the
 *  `<div class="sheet">` container that holds Experience points, the
 *  Abilities tree, and Inventories. Absent when LM did not emit the
 *  block (legacy / partial pages). Task 014.
 *
 *  Field order pinned: `experiencePoints` is OPTIONAL, the two list
 *  fields are required (always at least an empty array) so consumers
 *  can iterate without null-checking the lists themselves. */
export interface CharacterSheetBody {
  experiencePoints?: string;
  abilityGroups: SheetAbilityGroup[];
  inventories: SheetInventory[];
}

/**
 * Structured projection of an LM character-sheet HTML page.
 *
 * The `Presentation` block (`<h2 class="c">Presentation</h2>` plus the
 * adjacent `<div class="teaser">…</div>`) is carved out into its own
 * fields so Task 010's UI can render it next to the existing
 * `CharacterStats.teaser` / `CharacterStats.presentation` block without
 * double-rendering it as just another row.
 *
 * Task 014 added the optional `body` field, populated from
 * `<div class="sheet">` when LM emits it. The existing `sections[]` /
 * `teaserHtml` / `presentationHtml` shape is unchanged.
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
  /** Structured projection of the `<div class="sheet">` block (XP,
   *  abilities tree, inventories). Absent when LM did not emit the
   *  sheet block. Task 014. */
  body?: CharacterSheetBody;
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
    const value = flattenInnerHtml(valueRaw);
    if (label && value) {
      current.rows.push({ label, value });
    }
  }

  const result: CharacterSheet = {
    sections: sections.filter((s) => s.rows.length > 0),
  };
  if (teaserHtml !== undefined) result.teaserHtml = teaserHtml;
  if (presentationHtml !== undefined) result.presentationHtml = presentationHtml;

  // Task 014: structured projection of the <div class="sheet"> block
  // when LM emits it (XP, abilities tree, inventories). Extracted from
  // the ORIGINAL html (not `working`) because the teaser/presentation
  // carve-outs above touch the sibling .presentation div, never the
  // sheet div, and parseSheetBody just needs to know where the sheet
  // block starts/ends — keeping the source explicit avoids any
  // entanglement with the section-walking working copy.
  const sheetBlock = extractSheetBlock(html);
  if (sheetBlock !== null) {
    result.body = parseSheetBody(sheetBlock);
  }
  return result;
}

/** Extract the inner HTML of the first `<div class="sheet">` block —
 *  matched with a depth-counter (not non-greedy `</div>`) because the
 *  sheet block contains arbitrarily nested `<div>`s (inventory-card,
 *  character-inventories, etc.). Returns null when the block is
 *  absent. Task 014. */
function extractSheetBlock(html: string): string | null {
  const startRe =
    /<div\b[^>]*\bclass=["'][^"']*\bsheet\b[^"']*["'][^>]*>/i;
  const startMatch = startRe.exec(html);
  if (!startMatch) return null;
  const contentStart = startMatch.index + startMatch[0].length;

  const tagRe = /<(\/?)div\b[^>]*>/gi;
  tagRe.lastIndex = contentStart;
  let depth = 1;
  let m: RegExpExecArray | null;
  while ((m = tagRe.exec(html)) !== null) {
    if (m[1] === "/") {
      depth--;
      if (depth === 0) return html.slice(contentStart, m.index);
    } else {
      depth++;
    }
  }
  // Unbalanced div — surface everything from the start tag onward.
  // Defensive; real LM templates always close cleanly.
  return html.slice(contentStart);
}

/** Parse the inner HTML of the sheet block into a structured body.
 *  Always returns a body (with at least empty arrays for the list
 *  fields); the caller decides whether to attach it. Task 014. */
function parseSheetBody(blockHtml: string): CharacterSheetBody {
  const body: CharacterSheetBody = {
    abilityGroups: [],
    inventories: [],
  };

  // Experience points — content between <h2>Experience points</h2>
  // and the next <h2> (or end of block). Whitespace-only blocks
  // collapse to undefined so the field is omitted rather than
  // surfacing "". Matches the fixture, where LM emits the heading
  // with an empty body when the character has nothing to spend.
  const xpRe =
    /<h2\b[^>]*>\s*Experience\s+points?\s*<\/h2>([\s\S]*?)(?=<h2\b|$)/i;
  const xpMatch = xpRe.exec(blockHtml);
  if (xpMatch) {
    const text = flattenInnerHtml(xpMatch[1]!);
    if (text) body.experiencePoints = text;
  }

  // Ability groups — each <h3>...</h3> immediately followed by a
  // <table class="mob abilities"> opens one group. This pairing
  // intentionally skips <h3>Inventories</h3> (followed by
  // <div class="inventory-cards">, not a mob-abilities table) so the
  // inventory section never accidentally appears as an empty group.
  const groupRe =
    /<h3\b[^>]*>([\s\S]*?)<\/h3>\s*<table\b[^>]*\bclass=["'][^"']*\bmob\b[^"']*\babilities\b[^"']*["'][^>]*>([\s\S]*?)<\/table>/gi;
  let g: RegExpExecArray | null;
  while ((g = groupRe.exec(blockHtml)) !== null) {
    const label = flattenInnerHtml(g[1]!);
    if (!label) continue;
    body.abilityGroups.push({
      label,
      abilities: parseAbilityRows(g[2]!),
    });
  }

  // Inventories — every <div class="inventory-card"> block becomes
  // one SheetInventory. Non-greedy </div> matching is safe here
  // because LM cards have no nested <div>; they contain only <h4>,
  // <ul class="pool-balances">, and <a class="btn">.
  const cardRe =
    /<div\b[^>]*\bclass=["'][^"']*\binventory-card\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/gi;
  let c: RegExpExecArray | null;
  while ((c = cardRe.exec(blockHtml)) !== null) {
    const inv = parseInventoryCard(c[1]!);
    if (inv) body.inventories.push(inv);
  }

  return body;
}

/** Parse the rows inside one `<table class="mob abilities">`. */
function parseAbilityRows(tableHtml: string): SheetAbility[] {
  const out: SheetAbility[] = [];
  const rowRe =
    /<tr\b[^>]*>[\s\S]*?<h4\b[^>]*>([\s\S]*?)<\/h4>[\s\S]*?<td\b[^>]*>([\s\S]*?)<\/td>[\s\S]*?<\/tr>/gi;
  let r: RegExpExecArray | null;
  while ((r = rowRe.exec(tableHtml)) !== null) {
    const rawName = flattenInnerHtml(r[1]!);
    if (!rawName) continue;
    const costMatch = /\s*\((\d+)\)\s*$/.exec(rawName);
    const name = costMatch
      ? rawName.slice(0, costMatch.index).trim()
      : rawName;
    if (!name) continue;
    const ability: SheetAbility = { name };
    if (costMatch) ability.cost = costMatch[1]!;
    const desc = flattenInnerHtml(r[2]!);
    if (desc) ability.description = desc;
    out.push(ability);
  }
  return out;
}

/** Parse one `<div class="inventory-card">` inner HTML into a
 *  SheetInventory. Returns null when the card has no `<h4>` title
 *  (defensive — real LM cards always have one). */
function parseInventoryCard(inner: string): SheetInventory | null {
  const titleMatch = /<h4\b[^>]*>([\s\S]*?)<\/h4>/i.exec(inner);
  if (!titleMatch) return null;
  const title = flattenInnerHtml(titleMatch[1]!);
  if (!title) return null;

  const balances: SheetInventoryBalance[] = [];
  const balancesMatch =
    /<ul\b[^>]*\bclass=["'][^"']*\bpool-balances\b[^"']*["'][^>]*>([\s\S]*?)<\/ul>/i.exec(
      inner
    );
  if (balancesMatch) {
    const liRe = /<li\b[^>]*>([\s\S]*?)<\/li>/gi;
    let li: RegExpExecArray | null;
    while ((li = liRe.exec(balancesMatch[1]!)) !== null) {
      const text = flattenInnerHtml(li[1]!);
      const idx = text.indexOf(":");
      if (idx < 0) continue;
      const label = text.slice(0, idx).trim();
      const value = text.slice(idx + 1).trim();
      if (label && value) balances.push({ label, value });
    }
  }

  let detailsUrl: string | undefined;
  const btnRe =
    /<a\b[^>]*\bclass=["'][^"']*\bbtn\b[^"']*["'][^>]*>/i;
  const btnMatch = btnRe.exec(inner);
  if (btnMatch) {
    const hrefMatch = /\bhref=["']([^"']+)["']/i.exec(btnMatch[0]);
    if (hrefMatch) detailsUrl = hrefMatch[1];
  }

  const inv: SheetInventory = { title, balances };
  if (detailsUrl !== undefined) inv.detailsUrl = detailsUrl;
  return inv;
}

/** Strip ALL inline tags (e.g. <a>, <span>, <br>, <em>) so the text
 * content of a value cell can be measured and compared. */
function stripInlineTags(s: string): string {
  return s.replace(/<[^>]+>/g, "");
}

/** Strip inline tags AND collapse entities/whitespace — the combo
 *  this parser uses to turn any inner-HTML fragment into the flat
 *  plain text it surfaces in the structured projection. */
function flattenInnerHtml(html: string): string {
  return decodeAndCollapse(stripInlineTags(html));
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
