/**
 * Cookie + CSRF helpers for Django session auth against LarpManager.
 */

/** Parse Set-Cookie headers into name -> value (first occurrence wins). */
export function parseSetCookieHeaders(headers: Headers): Map<string, string> {
  const out = new Map<string, string>();
  const raw = (headers as unknown as { getSetCookie?: () => string[] })
    .getSetCookie?.();
  if (raw && raw.length > 0) {
    for (const line of raw) {
      const [pair] = line.split(";");
      const eq = pair.indexOf("=");
      if (eq <= 0) continue;
      const name = pair.slice(0, eq).trim();
      const value = pair.slice(eq + 1).trim();
      if (!out.has(name)) out.set(name, value);
    }
    return out;
  }
  const single = headers.get("set-cookie");
  if (!single) return out;
  for (const part of single.split(/,(?=\s*[^=]+=)/)) {
    const [pair] = part.trim().split(";");
    const eq = pair.indexOf("=");
    if (eq <= 0) continue;
    const name = pair.slice(0, eq).trim();
    const value = pair.slice(eq + 1).trim();
    if (!out.has(name)) out.set(name, value);
  }
  return out;
}

export function mergeCookieMaps(
  existing: Map<string, string>,
  fromResponse: Map<string, string>
): Map<string, string> {
  const next = new Map(existing);
  for (const [k, v] of fromResponse) {
    next.set(k, v);
  }
  return next;
}

export function cookieMapToHeader(jar: Map<string, string>): string {
  const parts: string[] = [];
  for (const [k, v] of jar) {
    parts.push(`${k}=${v}`);
  }
  return parts.join("; ");
}

/** Extract Django CSRF token from HTML body. */
export function extractCsrfMiddlewareToken(html: string): string | null {
  const m = html.match(
    /name=["']csrfmiddlewaretoken["']\s+value=["']([^"']+)["']/i
  );
  return m?.[1] ?? null;
}

export function normalizeBaseUrl(url: string): string {
  return url.replace(/\/+$/, "");
}

/**
 * Heuristic: does this HTML look like a Django/LarpManager login form?
 * Used to detect when an authenticated page silently redirected us back to login.
 */
export function looksLikeLoginPage(html: string): boolean {
  if (!html) return false;
  const hasPasswordInput =
    /<input[^>]*type=["']password["']/i.test(html) ||
    /<input[^>]*name=["']password["']/i.test(html);
  if (!hasPasswordInput) return false;
  const hasUsernameInput =
    /<input[^>]*name=["'](username|login|email)["']/i.test(html);
  const hasCsrf = /name=["']csrfmiddlewaretoken["']/i.test(html);
  return hasUsernameInput || hasCsrf;
}

/** True when a URL looks like a login endpoint (path ends in /login or contains ?next=). */
export function looksLikeLoginUrl(url: string): boolean {
  if (!url) return false;
  try {
    const u = new URL(url);
    if (/\/(login|signin|sign-in|accounts\/login)\/?$/i.test(u.pathname)) {
      return true;
    }
    if (u.searchParams.has("next")) return true;
    return false;
  } catch {
    return /\/login\/?(\?|$)/i.test(url) || /[?&]next=/i.test(url);
  }
}
