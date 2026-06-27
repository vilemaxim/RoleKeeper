/**
 * Shared location payload helpers for callables (active events, pings).
 */

export function sanitizeLocation(
  loc: unknown
): Record<string, unknown> | undefined {
  if (!loc || typeof loc !== "object") return undefined;
  const o = loc as Record<string, unknown>;
  const lat = o.latitude;
  const lng = o.longitude;
  if (typeof lat === "number" && typeof lng === "number") {
    const out: Record<string, unknown> = { latitude: lat, longitude: lng };
    if (typeof o.accuracy === "number" && Number.isFinite(o.accuracy)) {
      out.accuracy = o.accuracy;
    }
    if (typeof o.altitude === "number" && Number.isFinite(o.altitude)) {
      out.altitude = o.altitude;
    }
    const source = o.source;
    if (typeof source === "string" && source.length > 0) {
      out.source = source;
    }
    return out;
  }
  return undefined;
}

export function withGpsSource(
  loc: Record<string, unknown>
): Record<string, unknown> {
  return { ...loc, source: loc.source ?? "gps" };
}
