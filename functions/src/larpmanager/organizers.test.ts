import { test } from "node:test";
import * as assert from "node:assert/strict";

import {
  findOrganizerRoleUuidFromRolesHtml,
  parseEmailsFromRoleEditHtml,
} from "./organizers";

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
