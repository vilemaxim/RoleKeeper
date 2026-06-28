import * as crypto from "crypto";

/** SHA-256 hex digest of a plaintext API key for storage at rest. */
export function hashApiKey(plaintext: string): string {
  return crypto.createHash("sha256").update(plaintext, "utf8").digest("hex");
}

/** Constant-time comparison of a plaintext key against a stored hash. */
export function verifyApiKey(plaintext: string, storedHash: string): boolean {
  if (typeof storedHash !== "string" || storedHash.length === 0) return false;
  const computed = hashApiKey(plaintext);
  try {
    const a = Buffer.from(computed, "hex");
    const b = Buffer.from(storedHash, "hex");
    if (a.length !== b.length) return false;
    return crypto.timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

/** Generates a random API key suitable for one-time display. */
export function generateApiKey(): string {
  return crypto.randomBytes(32).toString("base64url");
}
