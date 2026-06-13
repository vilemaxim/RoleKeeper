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
import type {
  CharacterSheet,
  CharacterSheetBody,
} from "./characterSheet";

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
 * on the real LM template's nesting.
 *
 * Task 014: `body` (optional) is appended as a sibling `<div class="sheet">`
 * INSIDE the `.character` container so the parser can locate it the same
 * way it does in the real LM template (the sheet block sits next to
 * `.presentation` under `.character`).
 */
function buildSyntheticSheet(opts: {
  rows?: string;
  teaser?: string;
  presentation?: string;
  trailing?: string;
  body?: string;
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
  const body = opts.body !== undefined
    ? `<div class="sheet">${opts.body}</div>`
    : "";
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
      ${body}
    </div>
  </div>
</body></html>`;
}

/** Build the `<table class="mob abilities">` row LM emits for one ability. */
function abilityRow(nameInsideH4: string, descriptionInsideTd: string): string {
  return `
    <tbody><tr>
      <th>
        <h4>
          ${nameInsideH4}
        </h4>
      </th>
      <td>${descriptionInsideTd}</td>
    </tr></tbody>`;
}

/** Wrap one or more `abilityRow(...)` strings in the LM ability table
 *  header LM emits inside an `<h3>` group. */
function abilityGroup(label: string, rowsHtml: string): string {
  return `<h3>${label}</h3>\n<table class="mob abilities">${rowsHtml}</table>`;
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

// ==========================================================================
// Task 014: <div class="sheet"> body parsing — Experience points, the
// Abilities tree, and Inventories. Additive to the Task 008 surface; all
// tests above MUST still pass unchanged (the new `body` field is optional
// on `CharacterSheet`, and `sections[]` / `teaserHtml` / `presentationHtml`
// shapes are unchanged).
// ==========================================================================

// --- Experience points ----------------------------------------------------

test(
  "parseCharacterSheetHtml (Task 014): <h2>Experience points</h2> followed " +
    "by inline prose → body.experiencePoints is that prose with whitespace " +
    "collapsed and inline tags stripped",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      body:
        "<h2>Experience points</h2>" +
        "<p>You have   <strong>5</strong>  unspent XP.</p>" +
        "<h2>Abilities</h2>",
    });
    const sheet: CharacterSheet = parseCharacterSheetHtml(html);
    assert.ok(sheet.body, "body must be populated");
    assert.equal(
      sheet.body!.experiencePoints,
      "You have 5 unspent XP.",
      "inline tags stripped and whitespace collapsed"
    );
  }
);

test(
  "parseCharacterSheetHtml (Task 014): <h2>Experience points</h2> with " +
    "only whitespace before the next <h2> → experiencePoints is undefined",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      body: "<h2>Experience points</h2>\n   \n\n   \n<h2>Abilities</h2>",
    });
    const sheet = parseCharacterSheetHtml(html);
    assert.ok(sheet.body, "body must be populated even with empty XP");
    assert.equal(
      sheet.body!.experiencePoints,
      undefined,
      "an empty Experience points block must NOT surface the empty string"
    );
  }
);

// --- Abilities tree -------------------------------------------------------

test(
  "parseCharacterSheetHtml (Task 014): <h2>Abilities</h2> followed by two " +
    "<h3> groups (two rows each) → body.abilityGroups has length 2, labels " +
    "verbatim, names with trailing '(cost)' stripped, cost is the digit " +
    "string, description is the <td> flat plain text",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      body:
        "<h2>Abilities</h2>" +
        abilityGroup(
          "Shadow Affinity Skills",
          abilityRow(
            "Flashback (99)",
            "<p><strong>Frequency:</strong> Heist | <strong>Delivery:</strong> Self</p>"
          ) +
            abilityRow(
              "Shadow Step (3)",
              "<p>Teleport one move-stride into  shadow.</p>"
            )
        ) +
        abilityGroup(
          "Iron Affinity",
          abilityRow("Shadow 1 [Iron] (2)", "") +
            abilityRow(
              "Body 6 [Iron] (12)",
              "<p>Iron-clad heart.</p>"
            )
        ),
    });
    const sheet = parseCharacterSheetHtml(html);
    assert.ok(sheet.body, "body must be populated");
    assert.equal(sheet.body!.abilityGroups.length, 2);
    assert.deepEqual(
      sheet.body!.abilityGroups.map((g) => g.label),
      ["Shadow Affinity Skills", "Iron Affinity"],
      "group labels verbatim and in source-HTML order"
    );

    const shadow = sheet.body!.abilityGroups[0]!;
    assert.equal(shadow.abilities.length, 2);
    assert.equal(shadow.abilities[0]!.name, "Flashback");
    assert.equal(shadow.abilities[0]!.cost, "99");
    assert.equal(
      shadow.abilities[0]!.description,
      "Frequency: Heist | Delivery: Self",
      "description is the <td> contents with inline tags stripped and " +
        "whitespace collapsed"
    );
    assert.equal(shadow.abilities[1]!.name, "Shadow Step");
    assert.equal(shadow.abilities[1]!.cost, "3");
    assert.equal(
      shadow.abilities[1]!.description,
      "Teleport one move-stride into shadow."
    );

    const iron = sheet.body!.abilityGroups[1]!;
    assert.equal(iron.abilities.length, 2);
    assert.equal(iron.abilities[0]!.name, "Shadow 1 [Iron]");
    assert.equal(iron.abilities[0]!.cost, "2");
    assert.equal(
      iron.abilities[0]!.description,
      undefined,
      "an empty <td> must yield description: undefined, NOT empty string"
    );
    assert.equal(iron.abilities[1]!.name, "Body 6 [Iron]");
    assert.equal(iron.abilities[1]!.cost, "12");
    assert.equal(iron.abilities[1]!.description, "Iron-clad heart.");
  }
);

test(
  "parseCharacterSheetHtml (Task 014): an ability <h4> with NO trailing " +
    "'(cost)' paren → cost is undefined; name is the full <h4> text",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      body:
        "<h2>Abilities</h2>" +
        abilityGroup(
          "Common Skills",
          abilityRow("Common Skill Without Cost", "<p>A description.</p>")
        ),
    });
    const sheet = parseCharacterSheetHtml(html);
    const groups = sheet.body!.abilityGroups;
    assert.equal(groups.length, 1);
    const ab = groups[0]!.abilities[0]!;
    assert.equal(ab.name, "Common Skill Without Cost");
    assert.equal(ab.cost, undefined);
    assert.equal(ab.description, "A description.");
  }
);

test(
  "parseCharacterSheetHtml (Task 014): an ability <td> that is empty / " +
    "whitespace only → description is undefined (NOT the empty string)",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      body:
        "<h2>Abilities</h2>" +
        abilityGroup(
          "Race Skills",
          abilityRow("Empty (1)", "") +
            abilityRow("Whitespace (2)", "   \n   \t   ")
        ),
    });
    const sheet = parseCharacterSheetHtml(html);
    const abs = sheet.body!.abilityGroups[0]!.abilities;
    assert.equal(abs.length, 2);
    assert.equal(abs[0]!.description, undefined);
    assert.equal(abs[1]!.description, undefined);
  }
);

test(
  "parseCharacterSheetHtml (Task 014): Helper Abilities rows containing " +
    "'Used for prereq. Please ignore.' are surfaced VERBATIM — regression " +
    "guard against accidental filtering of the prereq markers",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      body:
        "<h2>Abilities</h2>" +
        abilityGroup(
          "Helper Abilities",
          abilityRow(
            "Metal Affinity 3+ (999)",
            "<p>Used for prereq. Please ignore.</p>"
          ) +
            abilityRow(
              "Silver Tier (0)",
              "<p>Silver Tier Cultivation</p>"
            )
        ),
    });
    const sheet = parseCharacterSheetHtml(html);
    const helpers = sheet.body!.abilityGroups[0]!.abilities;
    assert.equal(helpers.length, 2, "BOTH helper rows must surface");
    assert.equal(helpers[0]!.name, "Metal Affinity 3+");
    assert.equal(helpers[0]!.cost, "999");
    assert.equal(
      helpers[0]!.description,
      "Used for prereq. Please ignore.",
      "Used-for-prereq markers MUST NOT be filtered"
    );
    assert.equal(helpers[1]!.name, "Silver Tier");
    assert.equal(helpers[1]!.cost, "0");
    assert.equal(helpers[1]!.description, "Silver Tier Cultivation");
  }
);

// --- Inventories ----------------------------------------------------------

test(
  "parseCharacterSheetHtml (Task 014): <h3>Inventories</h3> with one " +
    "<div class=\"inventory-card\"> (title, one balance, View Details btn) " +
    "→ body.inventories[0] has matching title / balances / detailsUrl",
  () => {
    const url =
      "https://lm.example/crucible/manage/ci/inventory/g7j03os5vzhj/view/";
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      body:
        '<div class="character-inventories">' +
        "<h3>Inventories</h3>" +
        '<div class="inventory-cards">' +
        '<div class="inventory-card">' +
        "<h4>Heldrek's Personal Storage</h4>" +
        '<ul class="pool-balances"><li>Monster Cores: 0</li></ul>' +
        `<a href="${url}" class="btn">View Details</a>` +
        "</div>" +
        "</div>" +
        "</div>",
    });
    const sheet = parseCharacterSheetHtml(html);
    assert.equal(sheet.body!.inventories.length, 1);
    const inv = sheet.body!.inventories[0]!;
    assert.equal(inv.title, "Heldrek's Personal Storage");
    assert.deepEqual(inv.balances, [{ label: "Monster Cores", value: "0" }]);
    assert.equal(inv.detailsUrl, url);
  }
);

test(
  "parseCharacterSheetHtml (Task 014): <li> rows in pool-balances with no " +
    "':' separator are DROPPED from balances[]; the surviving rows split on " +
    "the first ':' with both sides trimmed",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      body:
        '<div class="character-inventories">' +
        "<h3>Inventories</h3>" +
        '<div class="inventory-card">' +
        "<h4>Stash</h4>" +
        '<ul class="pool-balances">' +
        "<li>Monster Cores: 0</li>" +
        "<li>garbled row with no separator</li>" +
        "<li>  Spaces Around  :   42  </li>" +
        "<li>Multi:Colon:Value</li>" +
        "</ul>" +
        "</div>" +
        "</div>",
    });
    const sheet = parseCharacterSheetHtml(html);
    const inv = sheet.body!.inventories[0]!;
    assert.deepEqual(
      inv.balances,
      [
        { label: "Monster Cores", value: "0" },
        { label: "Spaces Around", value: "42" },
        { label: "Multi", value: "Colon:Value" },
      ],
      "drop the row with no ':' and split surviving rows on the FIRST ':'"
    );
  }
);

test(
  "parseCharacterSheetHtml (Task 014): an inventory-card with NO " +
    "<a class=\"btn\"> button → detailsUrl is undefined",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1"),
      body:
        '<div class="character-inventories">' +
        "<h3>Inventories</h3>" +
        '<div class="inventory-card">' +
        "<h4>No Button Stash</h4>" +
        '<ul class="pool-balances"><li>Coins: 5</li></ul>' +
        "</div>" +
        "</div>",
    });
    const sheet = parseCharacterSheetHtml(html);
    const inv = sheet.body!.inventories[0]!;
    assert.equal(inv.title, "No Button Stash");
    assert.equal(inv.detailsUrl, undefined);
    assert.deepEqual(inv.balances, [{ label: "Coins", value: "5" }]);
  }
);

// --- Missing body block ---------------------------------------------------

test(
  "parseCharacterSheetHtml (Task 014): a sheet HTML with NO " +
    "<div class=\"sheet\"> block (just top stats + presentation) → " +
    "body is undefined; sections[] still populates normally",
  () => {
    const html = buildSyntheticSheet({
      rows: statRow("Player", "Player 1") + statRow("Race", "Human"),
      teaser: "<p>Fire Mage</p>",
      // No body opts → no <div class="sheet"> emitted.
    });
    const sheet = parseCharacterSheetHtml(html);
    assert.equal(
      sheet.body,
      undefined,
      "the optional body field must be omitted entirely when LM didn't " +
        "emit the sheet block"
    );
    assert.ok(
      sheet.sections.length >= 1 && sheet.sections[0]!.rows.length >= 2,
      "existing sections[] parsing must NOT regress when body is absent"
    );
    assert.equal(sheet.teaserHtml, "<p>Fire Mage</p>");
  }
);

// --- Regression guard: Task 008 surface stays unchanged when body present -

test(
  "parseCharacterSheetHtml (Task 014): adding a <div class=\"sheet\"> body " +
    "block does NOT cause any existing sections[] rows to disappear or " +
    "reorder (regression guard for Task 008 / 009 surface)",
  () => {
    const rows =
      statRow("Player", "Player 1") +
      statRow("Status", "Proposed") +
      statRow("Race", "Human");

    const withoutBody = parseCharacterSheetHtml(
      buildSyntheticSheet({ rows })
    );
    const withBody = parseCharacterSheetHtml(
      buildSyntheticSheet({
        rows,
        body:
          "<h2>Abilities</h2>" +
          abilityGroup(
            "Common Skills",
            abilityRow("Block (1)", "<p>Block one attack.</p>")
          ),
      })
    );

    assert.deepEqual(
      withBody.sections.map((s) => ({
        label: s.label,
        rows: s.rows.map((r) => [r.label, r.value]),
      })),
      withoutBody.sections.map((s) => ({
        label: s.label,
        rows: s.rows.map((r) => [r.label, r.value]),
      })),
      "sections[] shape (labels and row order) must be IDENTICAL whether " +
        "or not the body block is present"
    );
    assert.ok(withBody.body, "body still gets populated");
  }
);

// --- Fixture-anchored (committed Heldrek HTML) ----------------------------

test(
  "parseCharacterSheetHtml (Task 014): committed Heldrek fixture — " +
    "body.abilityGroups has EXACTLY these 10 labels in this order, " +
    "matching the LM page top-to-bottom",
  () => {
    if (!fs.existsSync(FIXTURE_PATH)) {
      throw new Error(
        `Heldrek fixture missing at ${FIXTURE_PATH}. ` +
          "Task 008 committed this file; re-run capture-lm-fixture if needed."
      );
    }
    const html = fs.readFileSync(FIXTURE_PATH, "utf8");
    const sheet = parseCharacterSheetHtml(html);
    assert.ok(sheet.body, "fixture must yield a populated body");
    const labels = sheet.body!.abilityGroups.map((g) => g.label);
    assert.deepEqual(
      labels,
      [
        "Shadow Affinity Skills",
        "Iron Affinity",
        "Common Skills",
        "Helper Abilities",
        "Silver Affinity",
        "Attack Affinity Skills",
        "Race Skills",
        "Body Affinity Skills",
        "Fire Affinity Skills",
        "Extra Hit Points",
      ],
      "abilityGroups must match the LM source-HTML order verbatim — no " +
        "alphabetization, no humanization, no drops"
    );
  }
);

test(
  "parseCharacterSheetHtml (Task 014): committed Heldrek fixture — first " +
    "ability of 'Shadow Affinity Skills' is " +
    "{name: 'Flashback', cost: '99', description: <starts with 'Frequency: Heist'>}",
  () => {
    if (!fs.existsSync(FIXTURE_PATH)) {
      throw new Error(`Heldrek fixture missing at ${FIXTURE_PATH}.`);
    }
    const html = fs.readFileSync(FIXTURE_PATH, "utf8");
    const sheet = parseCharacterSheetHtml(html);
    const shadow = sheet.body!.abilityGroups.find(
      (g) => g.label === "Shadow Affinity Skills"
    );
    assert.ok(shadow, "Shadow Affinity Skills group must exist");
    const first = shadow!.abilities[0]!;
    assert.equal(first.name, "Flashback");
    assert.equal(first.cost, "99");
    assert.ok(
      typeof first.description === "string" &&
        first.description.startsWith("Frequency: Heist"),
      `first ability's description must start with "Frequency: Heist", ` +
        `got: ${JSON.stringify(first.description)}`
    );
  }
);

test(
  "parseCharacterSheetHtml (Task 014): committed Heldrek fixture — " +
    "Helper Abilities has exactly 11 entries; all have a description that " +
    "either contains 'Used for prereq' or matches 'Silver Tier Cultivation'",
  () => {
    if (!fs.existsSync(FIXTURE_PATH)) {
      throw new Error(`Heldrek fixture missing at ${FIXTURE_PATH}.`);
    }
    const html = fs.readFileSync(FIXTURE_PATH, "utf8");
    const sheet = parseCharacterSheetHtml(html);
    const helpers = sheet.body!.abilityGroups.find(
      (g) => g.label === "Helper Abilities"
    );
    assert.ok(helpers, "Helper Abilities group must exist");
    assert.equal(
      helpers!.abilities.length,
      11,
      "exactly 11 helper ability rows (regression-locked to the fixture)"
    );
    for (const a of helpers!.abilities) {
      assert.ok(
        typeof a.description === "string",
        `every helper ability must have a description, name=${a.name}`
      );
      const d = a.description!;
      assert.ok(
        d.includes("Used for prereq") || d === "Silver Tier Cultivation",
        `helper description must be a prereq marker or Silver Tier ` +
          `Cultivation, got: ${JSON.stringify(d)} (name=${a.name})`
      );
    }
  }
);

test(
  "parseCharacterSheetHtml (Task 014): committed Heldrek fixture — " +
    "body.inventories has exactly one entry with the exact title, balances, " +
    "and detailsUrl shape",
  () => {
    if (!fs.existsSync(FIXTURE_PATH)) {
      throw new Error(`Heldrek fixture missing at ${FIXTURE_PATH}.`);
    }
    const html = fs.readFileSync(FIXTURE_PATH, "utf8");
    const sheet = parseCharacterSheetHtml(html);
    const invs = sheet.body!.inventories;
    assert.equal(invs.length, 1);
    const inv = invs[0]!;
    assert.equal(inv.title, "Heldrek's Personal Storage");
    assert.deepEqual(inv.balances, [
      { label: "Monster Cores", value: "0" },
    ]);
    assert.equal(
      inv.detailsUrl,
      "https://sovereignscrolls.larpmanager.com/crucible/manage/ci/inventory/g7j03os5vzhj/view/"
    );
  }
);

test(
  "parseCharacterSheetHtml (Task 014): committed Heldrek fixture — " +
    "body.experiencePoints is undefined (the fixture's " +
    "<h2>Experience points</h2> has no body content)",
  () => {
    if (!fs.existsSync(FIXTURE_PATH)) {
      throw new Error(`Heldrek fixture missing at ${FIXTURE_PATH}.`);
    }
    const html = fs.readFileSync(FIXTURE_PATH, "utf8");
    const sheet = parseCharacterSheetHtml(html);
    assert.equal(
      sheet.body!.experiencePoints,
      undefined,
      "the fixture has an empty Experience points block; the parser must " +
        "omit experiencePoints rather than surface ''."
    );
  }
);

test(
  "CharacterSheetBody (Task 014): the type exposes abilityGroups and " +
    "inventories as arrays — compile-pinned via a literal construction " +
    "without any casts",
  () => {
    const body: CharacterSheetBody = {
      abilityGroups: [],
      inventories: [],
    };
    assert.ok(Array.isArray(body.abilityGroups));
    assert.ok(Array.isArray(body.inventories));
    assert.equal(body.experiencePoints, undefined);
  }
);
