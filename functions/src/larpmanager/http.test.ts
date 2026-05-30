import { test } from "node:test";
import * as assert from "node:assert/strict";

import {
  cookieMapToHeader,
  extractCsrfMiddlewareToken,
  looksLikeLoginPage,
  looksLikeLoginUrl,
  mergeCookieMaps,
  normalizeBaseUrl,
  parseSetCookieHeaders,
} from "./http";

test("normalizeBaseUrl strips trailing slashes", () => {
  assert.equal(normalizeBaseUrl("https://lm.example/"), "https://lm.example");
});

test("extractCsrfMiddlewareToken finds token", () => {
  const html =
    '<input type="hidden" name="csrfmiddlewaretoken" value="abcXYZ123">';
  assert.equal(extractCsrfMiddlewareToken(html), "abcXYZ123");
});

test("cookieMapToHeader joins pairs", () => {
  const m = new Map<string, string>([
    ["sessionid", "s1"],
    ["csrftoken", "c1"],
  ]);
  assert.ok(cookieMapToHeader(m).includes("sessionid=s1"));
  assert.ok(cookieMapToHeader(m).includes("csrftoken=c1"));
});

test("mergeCookieMaps overwrites with newer", () => {
  const a = new Map([["sessionid", "old"]]);
  const b = new Map([["sessionid", "new"]]);
  assert.equal(mergeCookieMaps(a, b).get("sessionid"), "new");
});

test("parseSetCookieHeaders reads getSetCookie when present", () => {
  const h = new Headers();
  (h as unknown as { getSetCookie: () => string[] }).getSetCookie = () => [
    "sessionid=abc; Path=/; HttpOnly",
    "csrftoken=def; Path=/",
  ];
  const m = parseSetCookieHeaders(h);
  assert.equal(m.get("sessionid"), "abc");
  assert.equal(m.get("csrftoken"), "def");
});

test("looksLikeLoginPage detects Django login form", () => {
  const html =
    '<form method="post"><input type="hidden" name="csrfmiddlewaretoken" value="x">' +
    '<input name="username"><input type="password" name="password"></form>';
  assert.equal(looksLikeLoginPage(html), true);
});

test("looksLikeLoginPage rejects normal content pages", () => {
  const html = '<table id="roles"><tr id="abc"><td>Organizer</td></tr></table>';
  assert.equal(looksLikeLoginPage(html), false);
});

test("looksLikeLoginPage detects email-style login form (no csrf)", () => {
  const html =
    '<input name="email"><input type="password" name="password">';
  assert.equal(looksLikeLoginPage(html), true);
});

test("looksLikeLoginUrl recognises common login paths", () => {
  assert.equal(looksLikeLoginUrl("https://lm.example/login/"), true);
  assert.equal(
    looksLikeLoginUrl("https://lm.example/accounts/login/?next=/x/"),
    true
  );
  assert.equal(
    looksLikeLoginUrl("https://lm.example/crucible/manage/roles/"),
    false
  );
});
