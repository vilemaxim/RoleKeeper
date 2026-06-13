/**
 * Unit tests for `parseCharacterSheetHtml` — the per-character LM
 * sheet HTML parser introduced in Task 008.
 *
 * Mix of synthetic-HTML tests (precise, deterministic) and a single
 * fixture-anchored test that pins the committed scrubbed Heldrek
 * capture so future LM template drift fails CI loudly.
 *
 * Pure parser tests — no network, no Firestore, no Firebase Functions
 * runtime surface.
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";

import {
  CharacterSheetParseError,
  parseCharacterSheetHtml,
} from "./characterSheet";
import type { CharacterSheet } from "./characterSheet";

// Compiled tests live under `functions/lib/larpmanager/`; fixtures are at
// `functions/test/fixtures/`. Two `..` hops get us to `functions/`, then
// into `test/fixtures/...`. Matches the convention used by
// `charactersByEmail.test.ts`.
const FIXTURE_DIR = path.join(
  __dirname,
  "..",
  "..",
  "test",
  "fixtures",
  "crucible-character-sheet"
);
const FIXTURE_PATH = path.join(
  FIXTURE_DIR,
  "character-sheet-oxe9sb0w02ig.html"
);

/** Wrap a stat row in the exact go-inline shape LM emits. */
function statRow(label: string, valueHtml: string): string {
  return `
    <div class="go-inline">
        <span class="hide-screen">|</span>
        <b>${label}:&nbsp;</b>${valueHtml}
    </div>`;
}

/** Minimal but representative character-sheet HTML container, modelled
 * on the real LM template's nesting. */
function buildSyntheticSheet(opts: {
  rows?: string;
  teaser?: string;
  presentation?: string;
  trailing?: string;
}): string {
  const rows = opts.rows ?? "";
  const teaser =
    opts.teaser !== undefined
      ? `<h2 class="c">Presentation</h2>\n<div class="teaser">${opts.teaser}</div>`
      : "";
  const presentation =
    opts.presentation !== undefined
      ? `<h2 class="c">Presentation</h2>\n${opts.presentation}`
      : "";
  const trailing = opts.trailing ?? "";
  return `<!DOCTYPE html>
<html><head><title>Char</title></head>
<body>
  <div class="page_character_view">
    <div class="character">
      <div class="presentation">
        <div class="first">${rows}</div>
        ${teaser || presentation}
        ${trailing}
      </div>
    </div>
  </div>
</body></html>`;
}

// --- Malformed-HTML guard --------------------------------------------------

test(
  "parseCharacterSheetHtml: throws CharacterSheetParseError for HTML that " +
    "lacks the minimal sheet scaffolding (no <body>, no character container)",
  () => {
    assert.throws(
      () => parseCharacterSheetHtml("not html"),
      CharacterSheetParseError
    );
  }
);

test(
  "parseCharacterSheetHtml: throws CharacterSheetParseError for the empty " +
    "string",
  () => {
    assert.throws(
      () => parseCharacterSheetHtml(""),
      CharacterSheetParseError
    );
  }
);

test(
  "parseCharacterSheetHtml: an LM error/login page that has <body> but no " +
    "character container still throws CharacterSheetParseError",
  () => {
    const html =
      '<!DOCTYPE html><html><body><form action="/login/"></form></body></html>';
    assert.throws(
      () => parseCharacterSheetHtml(html),
      CharacterSheetParseError
    );
  }
);

// --- Row extraction (synthetic) -------------------------------------------

test(
  "parseCharacterSheetHtml: extracts <b>Label:</b>Value rows in source-HTML " +
    "order, stripping inline tags and collapsing whitespace",
  () => {
    const rows =
      statRow("Player", '<a href="/public/usrxyz/">Player 1</a>') +
      statRow("Status", '<span class="status_s">Proposed</span>') +
      statRow("Race", "Human (Fire Affinity)") +
      statRow("Hit Points/Essence", "42");
    const html = buildSyntheticSheet({ rows });
    const sheet = parseCharacterSheetHtml(html);

    assert.ok(sheet.sections.length >= 1, "at least one section produced");
    const firstSection = sheet.sections[0]!;
    // Pin label/value pairs in source-HTML order.
    assert.deepEqual(
      firstSection.rows.map((r) => [r.label, r.value]),
      [
        ["Player", "Player 1"],
        ["Status", "Proposed"],
        ["Race", "Human (Fire Affinity)"],
        ["Hit Points/Essence", "42"],
      ]
    );
  }
);

test(
  "parseCharacterSheetHtml: drops rows whose value is empty / whitespace " +
    "only (don't surface 'Field: ' noise)",
  () => {
    const rows =
      statRow("Player", "Player 1") +
      statRow("Race", "") +
      statRow("Status", "   ") +
      statRow("Hit Points/Essence", "42");
    const html = buildSyntheticSheet({ rows });
    const sheet = parseCharacterSheetHtml(html);

    const labels = sheet.sections.flatMap((s) => s.rows.map((r) => r.label));
    assert.deepEqual(
      labels,
      ["Player", "Hit Points/Essence"],
      "empty-value rows are dropped"
    );
  }
);

test(
  "parseCharacterSheetHtml: returns an empty sections array (NOT a throw) " +
    "when the character container exists but has no <b>Label:</b> rows",
  () => {
    const html = buildSyntheticSheet({ rows: "" });
    const sheet = parseCharacterSheetHtml(html);
    assert.deepEqual(sheet.sections, []);
  }
);

// --- Teaser / presentation carve-out --------------------------------------

test(
  "parseCharacterSheetHtml: extracts teaserHtml from <div class=\"teaser\"> " +
    "and trims surrounding whitespace",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      teaser: "<p>Fire Mage</p> ",
    });
    const sheet = parseCharacterSheetHtml(html);
    assert.equal(sheet.teaserHtml, "<p>Fire Mage</p>");
  }
);

test(
  "parseCharacterSheetHtml: teaserHtml is undefined when LM emits no " +
    "<div class=\"teaser\"> block",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
    });
    const sheet = parseCharacterSheetHtml(html);
    assert.equal(sheet.teaserHtml, undefined);
  }
);

test(
  "parseCharacterSheetHtml: the Presentation block (h2 + teaser) does NOT " +
    "re-appear inside sections[] (carve-out so Task 010's UI doesn't double-render)",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      teaser: "<p>Fire Mage</p>",
    });
    const sheet = parseCharacterSheetHtml(html);

    const allLabels = sheet.sections.flatMap((s) => [
      s.label,
      ...s.rows.map((r) => r.label),
    ]);
    assert.ok(
      !allLabels.includes("Presentation"),
      "Presentation must be carved out, not surfaced as a section/row label"
    );
    const allValues = sheet.sections.flatMap((s) => s.rows.map((r) => r.value));
    assert.ok(
      allValues.every((v) => !v.includes("Fire Mage")),
      "teaser body must not also appear as a row value"
    );
  }
);

// --- Multi-section ordering (synthetic) -----------------------------------
//
// The Heldrek fixture has exactly one (anonymous) section because LM
// renders the stats block without an <h2>/<h3> heading and the
// Presentation block is carved out. The two tests below build synthetic
// sheets with explicit h2 sections so we can pin (a) ordering and
// (b) the "missing section" Acceptance Criteria — neither of which the
// single-section Heldrek fixture exercises.

function namedSection(label: string, rows: string): string {
  return `<h2>${label}</h2>${rows}`;
}

test(
  "parseCharacterSheetHtml: multiple named sections appear in source-HTML " +
    "order (no alphabetization, no humanization)",
  () => {
    const rows =
      statRow("Player", "Player 1") +
      namedSection("Zeta Stats", statRow("Iron DR", "2")) +
      namedSection("Alpha Stats", statRow("HP", "42"));
    const html = buildSyntheticSheet({ rows });
    const sheet = parseCharacterSheetHtml(html);

    const sectionLabels = sheet.sections.map((s) => s.label);
    // Leading row (Player) belongs to a section that precedes the first
    // <h2>; whether that section's label is "" or omitted is up to the
    // implementation, but Zeta Stats MUST appear before Alpha Stats.
    const zetaIdx = sectionLabels.indexOf("Zeta Stats");
    const alphaIdx = sectionLabels.indexOf("Alpha Stats");
    assert.notEqual(zetaIdx, -1, "Zeta Stats section present");
    assert.notEqual(alphaIdx, -1, "Alpha Stats section present");
    assert.ok(
      zetaIdx < alphaIdx,
      `Zeta Stats (${zetaIdx}) must appear before Alpha Stats (${alphaIdx}) ` +
        "— source order, not alphabetical"
    );
  }
);

test(
  "parseCharacterSheetHtml: removing one section's HTML drops THAT section " +
    "while the others still parse correctly (Acceptance Criteria pin)",
  () => {
    const fullRows =
      namedSection("Combat", statRow("HP", "42")) +
      namedSection("Affinities", statRow("Fire", "12")) +
      namedSection("Reactions", statRow("Iron DR", "2"));
    const missingAffinitiesRows =
      namedSection("Combat", statRow("HP", "42")) +
      namedSection("Reactions", statRow("Iron DR", "2"));

    const full = parseCharacterSheetHtml(
      buildSyntheticSheet({ rows: fullRows })
    );
    const partial = parseCharacterSheetHtml(
      buildSyntheticSheet({ rows: missingAffinitiesRows })
    );

    const fullLabels = full.sections.map((s) => s.label);
    const partialLabels = partial.sections.map((s) => s.label);
    assert.ok(fullLabels.includes("Affinities"));
    assert.ok(!partialLabels.includes("Affinities"));
    assert.ok(partialLabels.includes("Combat"), "Combat still parses");
    assert.ok(partialLabels.includes("Reactions"), "Reactions still parses");
  }
);

// --- Heldrek fixture (committed) ------------------------------------------
//
// One pinned end-to-end test against the scrubbed fixture the
// CODER_IMPLEMENTATION phase commits at
// functions/test/fixtures/crucible-character-sheet/
// character-sheet-oxe9sb0w02ig.html. Locks the exact ordered row shape
// so future LM template drift fails CI immediately rather than
// silently corrupting Task 010's UI.
//
// The fixture is intentionally not loaded at module top-level: the
// scrubbed file doesn't exist until the implementation phase runs the
// scrub helper. Loading inside the test keeps the other tests in this
// file runnable independently.

test(
  "parseCharacterSheetHtml: committed Heldrek fixture — exact ordered " +
    "sections[] matches the hand-curated expected shape (label-for-label, " +
    "row-for-row)",
  () => {
    if (!fs.existsSync(FIXTURE_PATH)) {
      throw new Error(
        `Heldrek fixture missing at ${FIXTURE_PATH}. ` +
          "The CODER_IMPLEMENTATION phase scrubs and commits this file " +
          "from functions/test/fixtures/crucible-character-sheet-unscrubbed/."
      );
    }
    const html = fs.readFileSync(FIXTURE_PATH, "utf8");
    const sheet: CharacterSheet = parseCharacterSheetHtml(html);

    // The Heldrek sheet has exactly one section: the unnamed stats block
    // LM renders before the (carved-out) Presentation heading. The
    // abilities/inventory blocks downstream of Presentation contain no
    // <b>Label:</b>Value rows in the parsable format, so they are dropped
    // (empty sections are not surfaced).
    assert.equal(
      sheet.sections.length,
      1,
      "exactly one section (the anonymous stats block)"
    );
    const stats = sheet.sections[0]!;
    assert.equal(
      stats.label,
      "",
      "LM does NOT wrap the top-of-sheet stats in an <h2> heading, so the " +
        "section label is the empty string"
    );

    const expectedRows: Array<[string, string]> = [
      ["Player", "Player 1"],
      ["Status", "Proposed"],
      ["Race", "Human (Fire Affinity)"],
      ["Cultivation Tier", "Silver (C)"],
      ["Hit Points/Essence", "42"],
      ["Total Fire Affinity", "12"],
      ["Total Metal Affinity", "4"],
      ["Total Attack Affinity", "2"],
      ["Total Body Affinity", "8"],
      ["Total Shadow Affinity", "1"],
      ["Iron DR", "2"],
      ["Effective Attack Affinity", "0"],
      ["Effective Body Affinity", "6"],
      ["Effective Death Affinity", "-2"],
      ["Effective Earth Affinity", "-2"],
      ["Effective Fate Affinity", "-2"],
      ["Effective Fire Affinity", "10"],
      ["Effective Life Affinity", "-2"],
      ["Effective Light Affinity", "-2"],
      ["Effective Metal Affinity", "2"],
      ["Effective Shadow Affinity", "-1"],
      ["Effective Water Affinity", "-2"],
      ["Effective Wood Affinity", "-2"],
    ];
    assert.deepEqual(
      stats.rows.map((r) => [r.label, r.value]),
      expectedRows
    );
  }
);

test(
  "parseCharacterSheetHtml: committed Heldrek fixture — teaserHtml carries " +
    "the scrubbed 'Fire Mage' tagline, presentation block is NOT in sections",
  () => {
    if (!fs.existsSync(FIXTURE_PATH)) {
      throw new Error(
        `Heldrek fixture missing at ${FIXTURE_PATH}. ` +
          "The CODER_IMPLEMENTATION phase scrubs and commits this file."
      );
    }
    const html = fs.readFileSync(FIXTURE_PATH, "utf8");
    const sheet = parseCharacterSheetHtml(html);

    assert.ok(
      sheet.teaserHtml && sheet.teaserHtml.includes("Fire Mage"),
      `teaserHtml must include 'Fire Mage', got: ${String(sheet.teaserHtml)}`
    );

    const allLabels = sheet.sections.flatMap((s) => [
      s.label,
      ...s.rows.map((r) => r.label),
    ]);
    assert.ok(
      !allLabels.some((l) => /presentation/i.test(l)),
      "Presentation must be carved out, not surfaced as a section/row label"
    );
    const allValues = sheet.sections.flatMap((s) => s.rows.map((r) => r.value));
    assert.ok(
      allValues.every((v) => !/Fire Mage/.test(v)),
      "teaser body must not also appear inside a row value"
    );
  }
);
