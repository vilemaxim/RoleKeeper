/**
 * Minimal LarpManager HTTP client: Django login + JSON export + optional per-character JSON.
 */

import { logger } from "firebase-functions";

import type { LarpManagerCharacterExport, LarpManagerSyncConfig } from "./types";
import {
  cookieMapToHeader,
  extractCsrfMiddlewareToken,
  looksLikeLoginPage,
  mergeCookieMaps,
  normalizeBaseUrl,
  parseSetCookieHeaders,
} from "./http";

export class LarpManagerHttpError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly url: string
  ) {
    super(message);
    this.name = "LarpManagerHttpError";
  }
}

async function fetchJson<T>(
  url: string,
  cookieHeader: string
): Promise<{ json: T; headers: Headers }> {
  const res = await fetch(url, {
    method: "GET",
    headers: {
      Cookie: cookieHeader,
      Accept: "application/json",
      "User-Agent": "RoleKeeper-LarpManagerSync/1.0",
    },
    redirect: "manual",
  });
  const text = await res.text();
  if (!res.ok) {
    throw new LarpManagerHttpError(
      `HTTP ${res.status}: ${text.slice(0, 200)}`,
      res.status,
      url
    );
  }
  try {
    return { json: JSON.parse(text) as T, headers: res.headers };
  } catch {
    throw new LarpManagerHttpError(
      "Response is not valid JSON",
      res.status,
      url
    );
  }
}

/**
 * Obtain a session cookie jar: either from explicit sessionId or username/password login.
 */
export async function establishLarpManagerSession(
  config: LarpManagerSyncConfig
): Promise<Map<string, string>> {
  const base = normalizeBaseUrl(config.baseUrl);

  if (config.sessionId && config.sessionId.length > 0) {
    const jar = new Map<string, string>();
    jar.set("sessionid", config.sessionId.trim());
    return jar;
  }

  if (!config.username || !config.password) {
    throw new Error(
      "Either sessionId or both username and password are required for LarpManager auth"
    );
  }

  const loginPath = config.loginPath ?? "/login/";
  const loginUrl = `${base}${loginPath.startsWith("/") ? "" : "/"}${loginPath}`;

  let jar = new Map<string, string>();
  const loginGet = await fetch(loginUrl, {
    method: "GET",
    headers: {
      "User-Agent": "RoleKeeper-LarpManagerSync/1.0",
    },
    redirect: "follow",
  });
  const loginPageText = await loginGet.text();
  jar = mergeCookieMaps(jar, parseSetCookieHeaders(loginGet.headers));
  const preLoginSessionId = jar.get("sessionid") ?? null;
  const csrf =
    extractCsrfMiddlewareToken(loginPageText) ?? jar.get("csrftoken");
  if (!csrf) {
    throw new Error(
      "Could not obtain csrfmiddlewaretoken from LarpManager login page " +
        `(GET ${loginUrl} HTTP ${loginGet.status}). ` +
        "Check that Advanced → Login path points at your LarpManager login form."
    );
  }

  const body = new URLSearchParams();
  body.set("username", config.username);
  body.set("password", config.password);
  body.set("csrfmiddlewaretoken", csrf);
  body.set("next", "/");

  const postCookie = cookieMapToHeader(jar);
  const loginPost = await fetch(loginUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Cookie: postCookie,
      Referer: loginUrl,
      "User-Agent": "RoleKeeper-LarpManagerSync/1.0",
    },
    body: body.toString(),
    redirect: "manual",
  });

  jar = mergeCookieMaps(jar, parseSetCookieHeaders(loginPost.headers));

  if (loginPost.status >= 300 && loginPost.status < 400) {
    const sessionid = jar.get("sessionid");
    if (!sessionid) {
      throw new Error(
        `LarpManager login redirected (HTTP ${loginPost.status}) but did not set a sessionid cookie — ` +
          "check the service account username/password and the Login path."
      );
    }
    if (preLoginSessionId && sessionid === preLoginSessionId) {
      logger.warn(
        "establishLarpManagerSession: login redirect did not rotate sessionid",
        { loginUrl, status: loginPost.status }
      );
    }
    return jar;
  }

  if (!loginPost.ok) {
    const errText = await loginPost.text();
    throw new Error(
      `LarpManager login failed HTTP ${loginPost.status} at ${loginUrl}: ${errText.slice(0, 300)}`
    );
  }

  const postBody = await loginPost.text();
  const sessionidAfter = jar.get("sessionid") ?? null;
  const sessionRotated =
    sessionidAfter !== null && sessionidAfter !== preLoginSessionId;

  if (!sessionRotated) {
    const looksLogin = looksLikeLoginPage(postBody);
    logger.error("establishLarpManagerSession: login appears to have failed", {
      loginUrl,
      status: loginPost.status,
      hadPreLoginSession: preLoginSessionId !== null,
      sessionRotated,
      looksLikeLoginPage: looksLogin,
      bodySnippet: postBody.slice(0, 400),
    });
    throw new Error(
      `LarpManager login did not authenticate (HTTP ${loginPost.status} at ${loginUrl}). ` +
        (looksLogin
          ? "Server re-displayed the login form — username/password rejected or extra hidden field required."
          : "Session cookie did not rotate after POST — check username, password, and Login path."
        )
    );
  }

  return jar;
}

/** Bulk character export: GET /{event_slug}/export/char/ → JSON map keyed by character number. */
export async function fetchCharacterExportJson(
  config: LarpManagerSyncConfig,
  jar: Map<string, string>
): Promise<Record<string, LarpManagerCharacterExport>> {
  const base = normalizeBaseUrl(config.baseUrl);
  const slug = config.eventSlug.replace(/^\/+|\/+$/g, "");
  const url = `${base}/${slug}/export/char/`;
  const { json } = await fetchJson<Record<string, LarpManagerCharacterExport>>(
    url,
    cookieMapToHeader(jar)
  );
  return json;
}

export async function fetchCharacterInventoryJson(
  config: LarpManagerSyncConfig,
  jar: Map<string, string>,
  characterUuid: string
): Promise<unknown> {
  const base = normalizeBaseUrl(config.baseUrl);
  const slug = config.eventSlug.replace(/^\/+|\/+$/g, "");
  const url = `${base}/${slug}/character/${characterUuid}/inventory/json/`;
  const { json } = await fetchJson<unknown>(url, cookieMapToHeader(jar));
  return json;
}

export async function fetchCharacterAbilitiesJson(
  config: LarpManagerSyncConfig,
  jar: Map<string, string>,
  characterUuid: string
): Promise<unknown> {
  const base = normalizeBaseUrl(config.baseUrl);
  const slug = config.eventSlug.replace(/^\/+|\/+$/g, "");
  const url = `${base}/${slug}/character/${characterUuid}/abilities/json/`;
  const { json } = await fetchJson<unknown>(url, cookieMapToHeader(jar));
  return json;
}

/**
 * Organizer registration export: POST /{event_slug}/manage/registrations/ with download=1.
 * Returns a ZIP containing registration.csv.
 */
export async function fetchRegistrationsExportZip(
  config: LarpManagerSyncConfig,
  jar: Map<string, string>
): Promise<Buffer> {
  const base = normalizeBaseUrl(config.baseUrl);
  const slug = config.eventSlug.replace(/^\/+|\/+$/g, "");
  const url = `${base}/${slug}/manage/registrations/`;

  let cookieHeader = cookieMapToHeader(jar);
  const pageRes = await fetch(url, {
    method: "GET",
    headers: {
      Cookie: cookieHeader,
      "User-Agent": "RoleKeeper-LarpManagerSync/1.0",
    },
    redirect: "follow",
  });
  const pageHtml = await pageRes.text();
  jar = mergeCookieMaps(jar, parseSetCookieHeaders(pageRes.headers));
  const csrf =
    extractCsrfMiddlewareToken(pageHtml) ?? jar.get("csrftoken") ?? "";
  if (!csrf) {
    throw new Error(
      "Could not obtain csrfmiddlewaretoken from LarpManager registrations page — " +
        "export account may lack organizer registration access"
    );
  }

  const body = new URLSearchParams();
  body.set("csrfmiddlewaretoken", csrf);
  body.set("download", "1");

  cookieHeader = cookieMapToHeader(jar);
  const postRes = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Cookie: cookieHeader,
      Referer: url,
      "User-Agent": "RoleKeeper-LarpManagerSync/1.0",
    },
    body: body.toString(),
    redirect: "follow",
  });

  if (!postRes.ok) {
    const errText = await postRes.text();
    throw new LarpManagerHttpError(
      `Registration export failed HTTP ${postRes.status}: ${errText.slice(0, 300)}`,
      postRes.status,
      url
    );
  }

  const buf = Buffer.from(await postRes.arrayBuffer());
  if (buf.length < 4 || buf[0] !== 0x50 || buf[1] !== 0x4b) {
    throw new LarpManagerHttpError(
      "Registration export did not return a ZIP file — check export account permissions",
      postRes.status,
      url
    );
  }
  return buf;
}
