/**
 * Firestore-driven controls for scheduled LarpManager sync (owner/superAdmin in app).
 * Manual callable sync ignores these flags.
 */

import type * as admin from "firebase-admin";

import { type GameTenant, gameEventBase } from "../gameTenant";

export interface LarpManagerScheduledSyncSettings {
  scheduledSyncEnabled: boolean;
  minIntervalMinutes: number;
  restrictSyncToWindowUtc: boolean;
  windowStartHourUtc: number;
  windowEndHourUtc: number;
}

export const defaultScheduledSyncSettings: LarpManagerScheduledSyncSettings = {
  scheduledSyncEnabled: false,
  minIntervalMinutes: 15,
  restrictSyncToWindowUtc: false,
  windowStartHourUtc: 8,
  windowEndHourUtc: 22,
};

function clamp(n: number, lo: number, hi: number): number {
  if (!Number.isFinite(n)) return lo;
  return Math.min(hi, Math.max(lo, n));
}

function clampHour(v: unknown, fallback: number): number {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n) || n < 0 || n > 23) return fallback;
  return n;
}

export function parseLarpManagerSyncSettings(
  data: admin.firestore.DocumentData | undefined
): LarpManagerScheduledSyncSettings {
  if (!data) {
    return { ...defaultScheduledSyncSettings };
  }
  return {
    scheduledSyncEnabled: data.scheduledSyncEnabled === true,
    minIntervalMinutes: clamp(
      Math.floor(Number(data.minIntervalMinutes)) || 15,
      5,
      24 * 60
    ),
    restrictSyncToWindowUtc: data.restrictSyncToWindowUtc === true,
    windowStartHourUtc: clampHour(
      data.windowStartHourUtc,
      defaultScheduledSyncSettings.windowStartHourUtc
    ),
    windowEndHourUtc: clampHour(
      data.windowEndHourUtc,
      defaultScheduledSyncSettings.windowEndHourUtc
    ),
  };
}

/** Inclusive UTC hour window. Supports overnight (e.g. start 22 end 6). */
export function isUtcHourInSyncWindow(
  hourUtc: number,
  start: number,
  end: number
): boolean {
  if (start === end) {
    return hourUtc === start;
  }
  if (start < end) {
    return hourUtc >= start && hourUtc <= end;
  }
  return hourUtc >= start || hourUtc <= end;
}

export function shouldRunScheduledLarpManagerSync(
  settings: LarpManagerScheduledSyncSettings,
  lastSyncedAt: admin.firestore.Timestamp | undefined | null,
  now: Date
): { run: boolean; reason: string } {
  if (!settings.scheduledSyncEnabled) {
    return { run: false, reason: "scheduled_sync_disabled" };
  }
  if (settings.restrictSyncToWindowUtc) {
    const h = now.getUTCHours();
    if (
      !isUtcHourInSyncWindow(
        h,
        settings.windowStartHourUtc,
        settings.windowEndHourUtc
      )
    ) {
      return { run: false, reason: "outside_utc_window" };
    }
  }
  if (lastSyncedAt !== null) {
    const elapsed = now.getTime() - lastSyncedAt.toMillis();
    const minMs = settings.minIntervalMinutes * 60 * 1000;
    if (elapsed < minMs) {
      return { run: false, reason: "min_interval_not_elapsed" };
    }
  }
  return { run: true, reason: "ok" };
}

export function larpManagerSyncSettingsRef(
  db: admin.firestore.Firestore,
  tenant: GameTenant
): admin.firestore.DocumentReference {
  return db.doc(`${gameEventBase(tenant)}/larpManagerSyncSettings/config`);
}
