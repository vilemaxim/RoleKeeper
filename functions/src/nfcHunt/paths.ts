/** Tenant-relative Firestore paths for scavenger hunts (ADR 007). */

export function nfcHuntDoc(base: string, huntId: string): string {
  return `${base}/nfcHunts/${huntId}`;
}

export function nfcHuntTagDoc(
  base: string,
  huntId: string,
  tagUid: string
): string {
  return `${nfcHuntDoc(base, huntId)}/tags/${tagUid}`;
}

export function nfcHuntScansCollection(base: string, huntId: string): string {
  return `${nfcHuntDoc(base, huntId)}/scans`;
}

export function nfcHuntScanDoc(
  base: string,
  huntId: string,
  scanId: string
): string {
  return `${nfcHuntScansCollection(base, huntId)}/${scanId}`;
}

export function nfcHuntReviewScanDoc(
  base: string,
  huntId: string,
  scanId: string
): string {
  return `${nfcHuntDoc(base, huntId)}/reviewScans/${scanId}`;
}

export function characterNfcHuntScanDoc(
  base: string,
  characterId: string,
  scanId: string
): string {
  return `${base}/characters/${characterId}/nfcHuntScans/${scanId}`;
}
