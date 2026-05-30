import { test } from "node:test";
import * as assert from "node:assert/strict";

import { establishLarpManagerSession } from "./client";

type FetchFn = typeof fetch;

interface MockResponseInit {
  status?: number;
  setCookies?: string[];
  body?: string;
  url?: string;
}

function mockResponse(init: MockResponseInit = {}): Response {
  const headers = new Headers();
  const setCookies = init.setCookies ?? [];
  for (const c of setCookies) headers.append("set-cookie", c);
  (headers as unknown as { getSetCookie: () => string[] }).getSetCookie =
    () => setCookies;
  const status = init.status ?? 200;
  const body = init.body ?? "";
  const res = new Response(body, { status, headers });
  if (init.url !== undefined) {
    Object.defineProperty(res, "url", {
      value: init.url,
      writable: false,
      configurable: true,
    });
  }
  return res;
}

/**
 * Run a body with `globalThis.fetch` and `firebase-functions` logger replaced
 * by silent stubs. Restores everything after.
 */
async function withMockedFetch(
  handler: FetchFn,
  body: () => Promise<void>
): Promise<void> {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = handler;
  const fnsLogger = (await import("firebase-functions")).logger as unknown as {
    warn: (...a: unknown[]) => void;
    error: (...a: unknown[]) => void;
    info: (...a: unknown[]) => void;
  };
  const origWarn = fnsLogger.warn;
  const origError = fnsLogger.error;
  const origInfo = fnsLogger.info;
  fnsLogger.warn = () => {};
  fnsLogger.error = () => {};
  fnsLogger.info = () => {};
  try {
    await body();
  } finally {
    globalThis.fetch = originalFetch;
    fnsLogger.warn = origWarn;
    fnsLogger.error = origError;
    fnsLogger.info = origInfo;
  }
}

const LOGIN_PAGE_HTML =
  '<form method="post" action="/login/">' +
  '<input type="hidden" name="csrfmiddlewaretoken" value="csrf-token-1">' +
  '<input name="username">' +
  '<input type="password" name="password">' +
  "</form>";

test(
  "establishLarpManagerSession throws when login POST silently re-renders the form",
  async () => {
    let postCount = 0;
    const handler: FetchFn = async (input, init) => {
      const url = typeof input === "string" ? input : (input as URL).toString();
      const method = (init?.method ?? "GET").toUpperCase();
      if (method === "GET" && url.endsWith("/login/")) {
        return mockResponse({
          status: 200,
          body: LOGIN_PAGE_HTML,
          setCookies: [
            "sessionid=anon-1; Path=/; HttpOnly",
            "csrftoken=csrf-cookie-1; Path=/",
          ],
          url,
        });
      }
      if (method === "POST" && url.endsWith("/login/")) {
        postCount += 1;
        return mockResponse({
          status: 200,
          body: LOGIN_PAGE_HTML,
          setCookies: [],
          url,
        });
      }
      throw new Error(`Unexpected request: ${method} ${url}`);
    };

    await withMockedFetch(handler, async () => {
      await assert.rejects(
        establishLarpManagerSession({
          baseUrl: "https://lm.example",
          eventSlug: "crucible",
          username: "svc",
          password: "wrong",
          fetchDetails: false,
        }),
        /login did not authenticate.*re-displayed the login form/i
      );
    });

    assert.equal(postCount, 1, "POST should be attempted exactly once");
  }
);

test(
  "establishLarpManagerSession succeeds when POST redirects with a rotated sessionid",
  async () => {
    const handler: FetchFn = async (input, init) => {
      const url = typeof input === "string" ? input : (input as URL).toString();
      const method = (init?.method ?? "GET").toUpperCase();
      if (method === "GET" && url.endsWith("/login/")) {
        return mockResponse({
          status: 200,
          body: LOGIN_PAGE_HTML,
          setCookies: [
            "sessionid=anon-1; Path=/; HttpOnly",
            "csrftoken=csrf-cookie-1; Path=/",
          ],
          url,
        });
      }
      if (method === "POST" && url.endsWith("/login/")) {
        return mockResponse({
          status: 302,
          body: "",
          setCookies: [
            "sessionid=authenticated-2; Path=/; HttpOnly",
            "csrftoken=csrf-cookie-2; Path=/",
          ],
          url,
        });
      }
      throw new Error(`Unexpected request: ${method} ${url}`);
    };

    await withMockedFetch(handler, async () => {
      const jar = await establishLarpManagerSession({
        baseUrl: "https://lm.example",
        eventSlug: "crucible",
        username: "svc",
        password: "right",
        fetchDetails: false,
      });
      assert.equal(jar.get("sessionid"), "authenticated-2");
    });
  }
);

test(
  "establishLarpManagerSession throws when POST redirects without a sessionid",
  async () => {
    const handler: FetchFn = async (input, init) => {
      const url = typeof input === "string" ? input : (input as URL).toString();
      const method = (init?.method ?? "GET").toUpperCase();
      if (method === "GET" && url.endsWith("/login/")) {
        return mockResponse({
          status: 200,
          body: LOGIN_PAGE_HTML,
          setCookies: ["csrftoken=csrf-cookie-1; Path=/"],
          url,
        });
      }
      if (method === "POST" && url.endsWith("/login/")) {
        return mockResponse({
          status: 302,
          body: "",
          setCookies: ["csrftoken=csrf-cookie-2; Path=/"],
          url,
        });
      }
      throw new Error(`Unexpected request: ${method} ${url}`);
    };

    await withMockedFetch(handler, async () => {
      await assert.rejects(
        establishLarpManagerSession({
          baseUrl: "https://lm.example",
          eventSlug: "crucible",
          username: "svc",
          password: "right",
          fetchDetails: false,
        }),
        /did not set a sessionid cookie/i
      );
    });
  }
);

test(
  "establishLarpManagerSession short-circuits when sessionId is provided",
  async () => {
    const handler: FetchFn = async () => {
      throw new Error("fetch should not be called when sessionId is provided");
    };
    await withMockedFetch(handler, async () => {
      const jar = await establishLarpManagerSession({
        baseUrl: "https://lm.example",
        eventSlug: "crucible",
        sessionId: "preset-session-id",
        fetchDetails: false,
      });
      assert.equal(jar.get("sessionid"), "preset-session-id");
    });
  }
);
