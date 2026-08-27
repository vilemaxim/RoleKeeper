import * as crypto from "crypto";
import * as admin from "firebase-admin";

/** Notification `type` used by scavenger-hunt scan results (Task 005). */
export const NFC_HUNT_SCAN_RESULT = "nfc_hunt_scan_result";

export interface CreateInAppNotificationInput {
  uid: string;
  type: string;
  title: string;
  body: string;
  tenantKey?: string;
  payload?: Record<string, unknown>;
}

/**
 * Server-side writer for `users/{uid}/inAppNotifications/{id}`.
 * Clients cannot create these documents; callables use this helper.
 */
export async function createInAppNotification(
  db: admin.firestore.Firestore,
  input: CreateInAppNotificationInput
): Promise<string> {
  const id = crypto.randomBytes(8).toString("hex");
  const data: Record<string, unknown> = {
    type: input.type,
    title: input.title,
    body: input.body,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    readAt: null,
    payload: input.payload ?? {},
  };
  if (input.tenantKey !== undefined) {
    data.tenantKey = input.tenantKey;
  }
  await db
    .collection(`users/${input.uid}/inAppNotifications`)
    .doc(id)
    .set(data);
  return id;
}
