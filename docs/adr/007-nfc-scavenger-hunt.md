# ADR 007: Scavenger Hunt (QR / NFC Tag Tracking)

## Status

Accepted (2026-08-19)

## Context

RoleKeeper is a multi-tenant LARP helper (Flutter PWA + Firebase). Organizers
(`owner`, `superAdmin`) configure per-event features; players operate within
tenant-scoped permissions under `games/{instanceId}/events/{eventSlug}/`.

We need a scavenger-hunt feature where:

- An organizer enables one or more hunts per event.
- Tags are registered incrementally (not all at once), with optional labels
  and optional fixed GPS placement or a “floating” placement.
- Organizers may delegate tag placement to specific members via a per-hunt
  placer list (no new global role).
- Players scan tags via **QR codes** on/near physical tags (PWA-compatible).
  Native NFC may reuse the same `tagUid` in a later phase.
- Each scan is credited to the **character** (in-game persona), not merely the
  Firebase user.
- Duplicate scans by the same character on the same tag show “already scanned”
  with no extra credit.
- Unknown/damaged tags are logged for admin review; the player sees an error
  asking them to take a photo for plot.
- Location at scan time is **best-effort** (like death-timer events).
- Offline scans queue locally and sync later; results surface in a reusable
  in-app notification inbox (see Task 001).

Hunts are **not** gated on `eventSession/config.isLive`. Each hunt has its own
`enabled` flag. This supports playtest/default events and future toggling of
always-on test tenants without coupling to the live-session toggle.

## Decision

### 1. Scan medium (v1)

**QR codes** encoded with a RoleKeeper URI. Reuse existing
`lib/utils/qr_scanner.dart` (`mobile_scanner`). Do not depend on Web NFC for v1.

Payload format (v1):

```
rolekeeper:scavenger:v1:{tenantKey}:{huntId}:{tagUid}
```

- `tenantKey` — `instanceId::eventSlug` (matches existing callables).
- `huntId` — Firestore doc id under `nfcHunts`.
- `tagUid` — stable hardware id (trimmed string; document id for the tag).
  Use raw UID from tag/QR provisioning; no hashing in v1.

### 2. Firestore layout

All paths tenant-scoped unless noted.

| Document / collection | Path | Purpose |
|-----------------------|------|---------|
| Hunt | `games/{instanceId}/events/{eventSlug}/nfcHunts/{huntId}` | Config |
| Registered tag | `.../nfcHunts/{huntId}/tags/{tagUid}` | Admin/placer registry |
| Credit scan | `.../nfcHunts/{huntId}/scans/{scanId}` | Canonical credited scan |
| Review scan | `.../nfcHunts/{huntId}/reviewScans/{scanId}` | Unknown tag / admin review |
| Character mirror | `.../characters/{characterId}/nfcHuntScans/{scanId}` | Per-character history |
| In-app notification | `users/{uid}/inAppNotifications/{id}` | Reusable inbox (Task 001) |

**Hunt document fields:**

| Field | Type | Notes |
|-------|------|-------|
| `enabled` | bool | Player scans allowed when true |
| `name` | string | Display name |
| `expectedTagCount` | int | Target count (informational; may exceed registered tags) |
| `placerUids` | string[] | UIDs allowed to register tags (plus organizers) |
| `createdAt`, `updatedAt` | timestamp | |

**Tag document fields:**

| Field | Type | Notes |
|-------|------|-------|
| `label` | string? | Optional display label |
| `placement` | string | `fixed` \| `floating` |
| `location` | map? | `ActivityEventLocation` shape when `fixed` |
| `registeredByUid` | string | |
| `registeredAt` | timestamp | |

**Scan document fields:**

| Field | Type | Notes |
|-------|------|-------|
| `characterId` | string | Credit identity |
| `ownerUid` | string | Firebase uid (audit; character owner) |
| `tagUid` | string | Scanned tag id |
| `scannedAt` | timestamp | Server time on sync |
| `clientScannedAt` | timestamp? | Device time when queued offline |
| `location` | map? | Best-effort GPS |
| `queuedOffline` | bool | True if submitted from offline queue |
| `tenantKey` | string | Denormalized |
| `huntId` | string | Denormalized |

**Review scan fields:** same as scan plus `reason` (`unknown_tag`, etc.) and
no credit applied.

### 3. Uniqueness and outcomes

- **Credit uniqueness:** one credited scan per `(huntId, characterId, tagUid)`.
  Enforce in callable via query or deterministic doc id before write.
- **Already scanned:** return success with outcome `already_scanned`; create
  in-app notification; do not write a second credit doc.
- **Unknown tag:** write `reviewScans`; return outcome `unknown_tag` with user
  message including “take a photo in case plot needs it.”
- **Different characters** may each credit the same physical tag once.

### 4. Writes via callables only

| Callable | Who | Action |
|----------|-----|--------|
| `registerNfcHuntTag` | organizer or hunt placer | Upsert tag under hunt |
| `recordNfcHuntScan` | authenticated member with valid character | Process scan |

Client-side Firestore creates on hunt scans, review scans, and character mirrors
are **denied**. Organizers may create/update hunt config docs directly (rules)
or via future callables; v1 allows direct organizer writes on hunt docs.

Validation in `recordNfcHuntScan`:

- Caller is game member.
- Hunt exists and `enabled == true`.
- `characterId` belongs to caller (`characters/{id}.ownerId == uid`).
- QR payload tenant/hunt/tagUid consistent with request body.
- Location sanitized when present (reuse `sanitizeLocation` pattern).

### 5. Permissions

- **Hunt CRUD / enable / placer list:** `canConfigureGameRules` (owner,
  superAdmin).
- **Tag registration:** organizer **or** uid in `hunt.placerUids`.
- **Player scan:** any game member with an active character for the event.
- **Read scans / review / mismatch report:** `isStaffOrAbove` or organizer.

No new `GameRole` enum value. Placer permission is hunt-scoped.

### 6. Location mismatch report (admin, read-only)

For tags with `placement == fixed` and a stored placement location, flag scans
where haversine distance from scan location to tag location exceeds
**50 meters**. Scans without GPS or floating tags are excluded from mismatch
flags (shown as “no comparison” in admin UI).

### 7. Offline queue

Client stores pending scans in `SharedPreferences` (or equivalent). On reconnect,
drain queue through `recordNfcHuntScan`. Each final outcome creates an
`inAppNotifications` doc for the user (Task 005).

### 8. Relationship to playtest / default event

There is no platform-level “always-on playtest event” today. Hunts attach to
whatever `GameTenantRef` is selected (`games/.../events/...`). The test tenant
`rk-test.local::default` (`lib/constants/game_constants.dart`) may be used for
playtest; hunt `enabled` is independent of `eventSession.isLive`.

## Consequences

- **Positive:** PWA-compatible via QR; reuses QR scanner, location utils,
  callable patterns, and tenant isolation.
- **Positive:** Character-scoped credit matches in-game identity.
- **Positive:** Unknown-tag review path supports damaged tags without losing data.
- **Negative:** Physical tags need printed QR codes (not raw NFC tap) until a
  native app phase.
- **Negative:** Offline queue adds client complexity; mitigated by notification
  inbox built first (Task 001).

## References

- ADR 001 — location payload shape (`ActivityEventLocation`)
- `lib/utils/qr_scanner.dart` — scanner UI
- `functions/src/location/recordLocationPing.ts` — callable validation pattern
- `functions/src/index.ts` — `onActiveGameEventCreated` mirroring pattern
