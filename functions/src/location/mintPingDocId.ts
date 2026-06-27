import * as crypto from "crypto";

import type * as admin from "firebase-admin";

/** Time-sortable ping id: `YYYYMMDDHHmmssSSS_<6 hex>`. */
export function mintLocationPingDocId(
  ts: admin.firestore.Timestamp
): string {
  const d = ts.toDate();
  const y = d.getUTCFullYear();
  const mo = String(d.getUTCMonth() + 1).padStart(2, "0");
  const da = String(d.getUTCDate()).padStart(2, "0");
  const h = String(d.getUTCHours()).padStart(2, "0");
  const mi = String(d.getUTCMinutes()).padStart(2, "0");
  const s = String(d.getUTCSeconds()).padStart(2, "0");
  const ms = String(d.getUTCMilliseconds()).padStart(3, "0");
  const tie = crypto.randomBytes(3).toString("hex");
  return `${y}${mo}${da}${h}${mi}${s}${ms}_${tie}`;
}
