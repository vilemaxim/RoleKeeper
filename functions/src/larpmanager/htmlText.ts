/**
 * Strip LM HTML teaser strings to plain text so Flutter's Text widget
 * renders `Fire Mage` instead of the literal `<p>Fire Mage</p>`.
 *
 * Co-located with `characterSheet.ts` so both pieces of LM HTML
 * handling live in the same folder. Deliberately NOT reusing
 * `characterSheet.ts`'s private helpers — those collapse all
 * whitespace including newlines, which is wrong for the teaser path
 * (we want `<br>` and `</p>` to become hard line breaks so multi-line
 * teasers survive into Flutter's Text widget).
 *
 * Pure function, no IO, no third-party deps (same posture as
 * `characterSheet.ts`).
 *
 * Behaviour is pinned by `htmlText.test.ts`. Wired into
 * `runLarpManagerSync` at the `row.teaser = ch.teaser` site so the
 * mirror doc carries display-clean text while `row.export.teaser`
 * keeps the verbatim LM HTML for any future consumer.
 *
 * Returns `undefined` for: `null`, `undefined`, empty input, and input
 * that strips to empty/whitespace. The sync writer maps `undefined`
 * to "omit the top-level `teaser` field on the mirror doc" rather
 * than writing `null`/`''`.
 *
 * Algorithm:
 *   1. Replace `<br>` / `<br/>` / `<br />` (case-insensitive) with
 *      `\n`.
 *   2. Replace `</p>` (case-insensitive) with `\n\n` — LM paragraph
 *      separator becomes a blank line in plain text.
 *   3. Strip every remaining tag (anything matching `<[^>]+>`).
 *   4. Decode the same 6 entities `characterSheet.ts` handles
 *      (`&amp;` `&lt;` `&gt;` `&quot;` `&#39;`, `&nbsp;` → space).
 *   5. Collapse runs of horizontal whitespace (` ` and `\t`) to a
 *      single space, but PRESERVE newlines so multi-line teasers
 *      survive.
 *   6. Collapse runs of 3+ consecutive newlines down to exactly 2 so
 *      `<br><br><br><br>` doesn't produce a giant gap.
 *   7. Trim per-line trailing horizontal whitespace introduced by the
 *      previous steps (e.g. `<p>foo</p>  <p>bar</p>` produced
 *      `foo\n\n  bar` after step 2 → 5).
 *   8. Trim leading/trailing whitespace overall.
 *   9. Return `undefined` if the result is empty.
 */
export function htmlToPlainText(
  html: string | null | undefined
): string | undefined {
  if (html === null || html === undefined || html === "") return undefined;

  let s = html;
  s = s.replace(/<br\s*\/?>/gi, "\n");
  s = s.replace(/<\/p>/gi, "\n\n");
  s = s.replace(/<[^>]+>/g, "");
  s = s
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'");
  s = s.replace(/[ \t]+/g, " ");
  s = s.replace(/\n{3,}/g, "\n\n");
  s = s.replace(/[ \t]+\n/g, "\n");
  s = s.replace(/\n[ \t]+/g, "\n");
  s = s.trim();

  return s.length > 0 ? s : undefined;
}
