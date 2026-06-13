/**
 * Unit tests for `htmlToPlainText` — the LM teaser HTML→plain-text
 * sanitiser introduced in Task 011. Pure function tests, no IO.
 *
 * Pins the exact contract listed in `docs/tasks/ready/011-coder.md`
 * Acceptance Criteria: `<br>` and `</p>` become hard line breaks (so
 * multi-line teasers survive), all other tags are stripped, the
 * handful of entities the existing parsers handle are decoded, runs
 * of horizontal whitespace collapse to a single space (preserving
 * newlines), runs of 3+ newlines collapse to exactly 2, and inputs
 * that strip to empty / whitespace return `undefined` so the sync
 * writer can omit the field entirely on the mirror doc.
 */

import { test } from "node:test";
import * as assert from "node:assert/strict";

import { htmlToPlainText } from "./htmlText";

// --- Tag stripping --------------------------------------------------------

test("htmlToPlainText: <p>Fire Mage</p> → 'Fire Mage'", () => {
  assert.equal(htmlToPlainText("<p>Fire Mage</p>"), "Fire Mage");
});

test(
  "htmlToPlainText: two <p> blocks become a double-newline-separated " +
    "string ('A\\n\\nB')",
  () => {
    assert.equal(
      htmlToPlainText("<p>Fire Mage</p><p>Hero of the realm</p>"),
      "Fire Mage\n\nHero of the realm"
    );
  }
);

test("htmlToPlainText: <br> becomes a single newline", () => {
  assert.equal(htmlToPlainText("Line 1<br>Line 2"), "Line 1\nLine 2");
});

test(
  "htmlToPlainText: self-closing <br/> and <br /> variants both become " +
    "a single newline (case-insensitive)",
  () => {
    assert.equal(
      htmlToPlainText("Line 1<br/>Line 2<br />Line 3"),
      "Line 1\nLine 2\nLine 3"
    );
    assert.equal(
      htmlToPlainText("Line 1<BR>Line 2<Br/>Line 3"),
      "Line 1\nLine 2\nLine 3"
    );
  }
);

test(
  "htmlToPlainText: inline tags inside a paragraph (<strong>, <em>) are " +
    "stripped without leaving their text behind or eating surrounding spaces",
  () => {
    assert.equal(
      htmlToPlainText("<p>Hello <strong>world</strong></p>"),
      "Hello world"
    );
    assert.equal(
      htmlToPlainText("<p>Hello <em>brave</em> <strong>world</strong></p>"),
      "Hello brave world"
    );
  }
);

// --- Entity decoding ------------------------------------------------------

test(
  "htmlToPlainText: decodes the 6 entities the existing characterSheet " +
    "parser already handles (&amp; &lt; &gt; &quot; &#39; &nbsp;)",
  () => {
    assert.equal(htmlToPlainText("A &amp; B &lt; C"), "A & B < C");
    assert.equal(
      htmlToPlainText("Tom &quot;the cat&quot; said &#39;hi&#39;"),
      "Tom \"the cat\" said 'hi'"
    );
    assert.equal(
      htmlToPlainText("X&gt;Y"),
      "X>Y"
    );
    // &nbsp; decodes to a space (matching characterSheet.ts).
    assert.equal(htmlToPlainText("foo&nbsp;bar"), "foo bar");
  }
);

// --- Whitespace policy ----------------------------------------------------

test(
  "htmlToPlainText: runs of spaces/tabs collapse to one space, but NEWLINES " +
    "are preserved (LM organisers write multi-line teasers)",
  () => {
    assert.equal(
      htmlToPlainText("foo   \t  bar"),
      "foo bar",
      "horizontal whitespace collapses"
    );
    assert.equal(
      htmlToPlainText("foo<br>bar"),
      "foo\nbar",
      "<br> newline survives"
    );
    assert.equal(
      htmlToPlainText("foo  <br>  bar"),
      "foo\nbar",
      "horizontal whitespace around <br> is collapsed but the newline stays"
    );
  }
);

test(
  "htmlToPlainText: runs of 3+ consecutive newlines collapse to exactly 2 " +
    "(prevents three-<br>-in-a-row from producing a giant gap)",
  () => {
    assert.equal(
      htmlToPlainText("A<br><br><br><br>B"),
      "A\n\nB",
      "four <br>s collapse to two newlines"
    );
    assert.equal(
      htmlToPlainText("A<br><br>B"),
      "A\n\nB",
      "two <br>s preserved (the paragraph-separator amount)"
    );
  }
);

test("htmlToPlainText: trims leading and trailing whitespace", () => {
  assert.equal(htmlToPlainText("  Fire Mage  "), "Fire Mage");
  assert.equal(htmlToPlainText("\n\n<p>Fire Mage</p>\n\n"), "Fire Mage");
});

// --- Plain-text passthrough ----------------------------------------------

test(
  "htmlToPlainText: returns a plain-text string unchanged when there is " +
    "nothing to strip or decode",
  () => {
    assert.equal(htmlToPlainText("plain text"), "plain text");
  }
);

// --- Empty / null / undefined inputs -------------------------------------

test(
  "htmlToPlainText: empty input → undefined (signals 'omit teaser field' " +
    "to the sync writer)",
  () => {
    assert.equal(htmlToPlainText(""), undefined);
  }
);

test(
  "htmlToPlainText: whitespace-only input → undefined",
  () => {
    assert.equal(htmlToPlainText("   "), undefined);
    assert.equal(htmlToPlainText("\n\n\t"), undefined);
  }
);

test("htmlToPlainText: undefined input → undefined", () => {
  assert.equal(htmlToPlainText(undefined), undefined);
});

test("htmlToPlainText: null input → undefined", () => {
  assert.equal(htmlToPlainText(null), undefined);
});

test(
  "htmlToPlainText: HTML that strips to empty (<p>   </p>) → undefined " +
    "rather than the empty string",
  () => {
    assert.equal(htmlToPlainText("<p>   </p>"), undefined);
    assert.equal(htmlToPlainText("<p></p>"), undefined);
    assert.equal(htmlToPlainText("<br><br>"), undefined);
  }
);
