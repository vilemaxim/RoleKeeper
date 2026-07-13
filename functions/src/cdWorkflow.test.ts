/**
 * Task 018: CD must non-interactively delete remote-only functions.
 *
 * Pins acceptance criteria from `docs/tasks/ready/018-coder.md`:
 *   - Deploy Functions uses `firebase deploy --only functions --force`
 *   - Inline comment documents why `--force` is required
 *   - Other CD deploy targets / project id remain unchanged
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";

const REPO_ROOT = join(__dirname, "../..");
const CD_WORKFLOW = readFileSync(
  join(REPO_ROOT, ".github/workflows/cd.yml"),
  "utf8"
);

test("CD Deploy Functions step uses --force for orphan deletion (Task 018)", () => {
  assert.match(
    CD_WORKFLOW,
    /firebase deploy --only functions --force --project rolekeeper-7ddcc/,
    "cd.yml Deploy Functions must pass --force so remote-only callables can be deleted in CI"
  );
});

test("CD workflow comments why --force is required (Task 018)", () => {
  assert.match(
    CD_WORKFLOW,
    /#.*--force.*(remote-only|orphan|delet)/i,
    "cd.yml must document that --force deletes remote-only functions after intentional removals"
  );
});

test("CD workflow retains other deploy targets and project id (Task 018)", () => {
  assert.match(
    CD_WORKFLOW,
    /firebase deploy --only firestore --project rolekeeper-7ddcc/
  );
  assert.match(
    CD_WORKFLOW,
    /firebase deploy --only storage --project rolekeeper-7ddcc/
  );
  assert.match(
    CD_WORKFLOW,
    /firebase deploy --only hosting --project rolekeeper-7ddcc/
  );
  assert.match(CD_WORKFLOW, /branches:\s*\[\s*main\s*\]/);
  assert.match(CD_WORKFLOW, /id-token:\s*write/);
});
