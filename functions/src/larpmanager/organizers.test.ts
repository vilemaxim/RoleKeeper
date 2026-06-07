import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as fs from "fs";
import * as path from "path";

import {
  buildOrganizerAccessDeniedMessage,
  findOrganizerRoleUuidFromRolesHtml,
  looksLikeLarpManagerAccessDeniedPage,
  parseEmailsFromRoleEditHtml,
} from "./organizers";

// Compiled tests live under `functions/lib/larpmanager/`; fixtures are at
// `functions/test/fixtures/`. Two `..` hops get us to `functions/`, then
// into `test/fixtures/...`.
const ACCESS_DENIED_FIXTURE_PATH = path.join(
  __dirname,
  "../../test/fixtures/crucible-roles/access-denied.html"
);

test("findOrganizerRoleUuidFromRolesHtml picks row without delete (LM 12-char ids)", () => {
  // LarpManager UuidMixin uses 12-char [a-z0-9] ids, not standard UUIDs.
  const html = `
    <table id="roles">
      <tbody>
        <tr id="abc123def456">
          <td><a href="/crucible/manage/roles/abc123def456/edit/"></a></td>
          <td>Staff</td>
          <td>Alice</td>
          <td><a href="/crucible/manage/roles/abc123def456/delete"
                 class="only_new_v18"><i class="fas fa-trash"></i></a></td>
        </tr>
        <tr id="9x2y0p3kl5mz">
          <td><a href="/crucible/manage/roles/9x2y0p3kl5mz/edit/"></a></td>
          <td>Organizer</td>
          <td>Jeffrey Brite, Service Account RoleKeeper</td>
          <td></td>
        </tr>
      </tbody>
    </table>
  `;
  assert.equal(findOrganizerRoleUuidFromRolesHtml(html), "9x2y0p3kl5mz");
});

test("findOrganizerRoleUuidFromRolesHtml still works with full UUIDs", () => {
  // Defensive: tolerate future format changes back to full UUIDs.
  const html = `
    <tr id="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa">
      <td><a href="orga_roles_delete"><i class="fas fa-trash"></i></a></td>
    </tr>
    <tr id="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb">
      <td>Organizer</td>
      <td></td>
    </tr>
  `;
  assert.equal(
    findOrganizerRoleUuidFromRolesHtml(html),
    "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
  );
});

test("findOrganizerRoleUuidFromRolesHtml ignores thead UUID-like ids", () => {
  // A <tr> in <thead> should not be considered a role row.
  const html = `
    <table id="roles">
      <thead>
        <tr id="header12abcd"><th>Name</th></tr>
      </thead>
      <tbody>
        <tr id="org123abcdef">
          <td>Organizer</td>
          <td></td>
        </tr>
      </tbody>
    </table>
  `;
  assert.equal(findOrganizerRoleUuidFromRolesHtml(html), "org123abcdef");
});

test("parseEmailsFromRoleEditHtml extracts member emails", () => {
  const html =
    '<option selected>Jane Doe - jane@example.com</option>' +
    '<option>Bob Smith - bob@test.org</option>';
  const emails = parseEmailsFromRoleEditHtml(html);
  assert.deepEqual(emails.sort(), ["bob@test.org", "jane@example.com"]);
});

test("findOrganizerRoleUuidFromRolesHtml falls back to single row (real LM shape)", () => {
  const html = `
    <table id="roles">
      <tbody>
        <tr id="ccc111ddd222">
          <td><a href="/crucible/manage/roles/ccc111ddd222/edit/"></a></td>
          <td>Organizer</td>
          <td>Jeffrey Brite, Service Account RoleKeeper</td>
          <td></td>
        </tr>
      </tbody>
    </table>
  `;
  assert.equal(findOrganizerRoleUuidFromRolesHtml(html), "ccc111ddd222");
});

test("findOrganizerRoleUuidFromRolesHtml accepts extra <tr> attributes", () => {
  const html =
    '<tr class="role-row" id="ddd333eee444" data-x="1">' +
    "<td>Organizer</td><td></td></tr>";
  assert.equal(findOrganizerRoleUuidFromRolesHtml(html), "ddd333eee444");
});

test("findOrganizerRoleUuidFromRolesHtml returns null when no UUID rows", () => {
  const html =
    '<form><input type="password" name="password"></form>';
  assert.equal(findOrganizerRoleUuidFromRolesHtml(html), null);
});

// --- Task 004: Access-denied detection -----------------------------------
//
// Production evidence: checkLarpManagerRegistrationCallable log entry at
// 2026-06-01T19:13:12.951584Z showed LM serving HTTP 200 with the
// "Access denied" template when the service account lacked `orga_roles`
// on Crucible's Organizer role. Fixture is a scrubbed slice of that body.

test("looksLikeLarpManagerAccessDeniedPage matches the captured LM fixture", () => {
  const html = fs.readFileSync(ACCESS_DENIED_FIXTURE_PATH, "utf8");
  assert.equal(
    looksLikeLarpManagerAccessDeniedPage(html),
    true,
    "should detect the captured production access-denied page"
  );
});

test(
  "looksLikeLarpManagerAccessDeniedPage rejects a normal roles page even when " +
    "an organizer is named 'Access denied' in the role row",
  () => {
    // Defensive: only the <title> shape counts. A roles page that happens
    // to mention the words "Access denied" in a row label must NOT trip
    // the detector (would cause a false organizer-error misclassification).
    const html = `
      <html><head><title>Manage roles - Example LARP</title></head>
      <body>
        <table id="roles"><tbody>
          <tr id="abc123def456">
            <td>Organizer</td>
            <td>Access denied team</td>
          </tr>
        </tbody></table>
      </body></html>
    `;
    assert.equal(looksLikeLarpManagerAccessDeniedPage(html), false);
  }
);

test("looksLikeLarpManagerAccessDeniedPage rejects a login page", () => {
  const html =
    "<html><head><title>Login - Example LARP</title></head>" +
    '<body><form><input type="password" name="password"></form></body></html>';
  assert.equal(looksLikeLarpManagerAccessDeniedPage(html), false);
});

test("looksLikeLarpManagerAccessDeniedPage handles empty / missing input", () => {
  assert.equal(looksLikeLarpManagerAccessDeniedPage(""), false);
});

test(
  "buildOrganizerAccessDeniedMessage names the exact LM permission and where " +
    "to grant it (acceptance criterion: actionable remediation step)",
  () => {
    const msg = buildOrganizerAccessDeniedMessage(
      "https://lm.example.com/example-event/manage/roles/",
      "example-event"
    );
    // The hedged old copy must be gone — it conflated permissions and
    // wrong-slug into one ambiguous message.
    assert.ok(
      !/event slug may be wrong/i.test(msg),
      "should not include the old 'or the event slug may be wrong' hedge"
    );
    // Must name the LM permission verbatim so the organizer can grep for
    // it in LM's permission picker.
    assert.match(
      msg,
      /\borga_roles\b/,
      "must name the exact LM permission (`orga_roles`)"
    );
    // Must tell them WHERE to grant it.
    assert.match(
      msg,
      /Organizer role/i,
      "must name which role to edit (Organizer)"
    );
    assert.match(
      msg,
      /\/example-event\/manage\/roles\//,
      "must include the event-scoped roles URL path so it is copy-pasteable"
    );
    // Must mention the original URL so the organizer knows which event
    // triggered the failure (multi-tenant clarity).
    assert.match(
      msg,
      /https:\/\/lm\.example\.com\/example-event\/manage\/roles\//,
      "must include the full rolesUrl so multi-tenant organizers know which event failed"
    );
  }
);
