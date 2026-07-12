# ADR 003: Death Intervention Signing and TOTP Secrets

## Status
Accepted — Task 004 implemented per-event secrets; Task 017 requires eager prefetch

## Context
Death intervention has two attack surfaces:

1. **Online medic QR** (`death_qr_parser.dart`): plaintext format
   `rolekeeper:death:medic:{shortId}:{fallenPlayerId}:{activityEventId}`.
   Any game member who knows three IDs can forge a valid QR.

2. **Offline medic TOTP** (`totp_service.dart`): shared seed `ROLEKEEPEROFFLINE`
   across all installs. Anyone with the app can generate valid offline codes.

Firestore rules (Task 003) gate **claims** by staff/medic role, but QR forgery
still allows a malicious member to trick a legitimate medic's client into
processing a fake scan before rules are hit, and offline TOTP bypasses server
entirely.

Field constraint: players often lose connectivity during play. Secrets must
already be on the device before death timer / offline intervention is needed.
Fetch-at-need (only when opening the death timer) breaks that use case.

## Decision

### Per-event TOTP secret (H3)
- Cloud Function (or existing callable) generates a random 32-byte secret per
  `games/{instanceId}/events/{eventSlug}` stored in a server-writable doc
  (e.g. `eventSession/config` field or `rules/death` subdoc).
- Flutter **eagerly** fetches secrets on LARP/home bootstrap while online and
  caches them in `flutter_secure_storage` keyed by `tenantKey`.
- Offline: use cached secret only. If never fetched, death timer must **not**
  start when a medic QR is required; offline intervention stays disabled with
  a clear UI message. Failures are logged (terminal + master + character logs).
- Rotate secret only on explicit organizer action (out of scope for Task 004).

### HMAC-signed QR payloads (H5)
- Server holds `deathQrSigningSecret` per event (same doc as TOTP or separate).
- **v2 medic QR format:**
  ```
  rolekeeper:death:v2:medic:{shortId}:{fallenPlayerId}:{activityEventId}:{hmacHex}
  ```
  where `hmacHex = HMAC-SHA256(secret, "{shortId}:{fallenPlayerId}:{activityEventId}")`
  truncated or full hex (implementation choice — use first 16 bytes hex = 32 chars
  to keep QR scannable).
- Medic client verifies HMAC before creating claim. Reject v1 unsigned QRs after
  rollout window (or accept v1 only if event secret unavailable — prefer hard cut).
- Revival-confirm QR uses same signing scheme with type prefix `revival-confirm`.

### Medic authorization (H4)
- Align with Task 003: `isStaffOrAbove` on `deathInterventionClaims` create.
- If product later adds dedicated `medic` role, extend rules helper; do not
  allow plain `player` to create claims.

### Abuse detection (product tradeoff)
- Per-event secrets on member devices are intentional so offline play works.
- Unauthorized use of an extracted seed is mitigated by logging healing /
  intervention events; when any device syncs, non-medic or not-nearby heals
  can be flagged in the master log.

## Consequences
- Requires online connectivity at least once per LARP session load (bootstrap)
  so the cache is warm before the field goes offline.
- Existing printed v1 QRs become invalid after cutover — acceptable pre-production.
- Secret distribution: callable on join/home load + secure local cache; death
  timer hard-fails if QR cannot be produced (Task 017).

## Alternatives considered
- **Asymmetric signing (RSA):** heavier QR payload; rejected for scan reliability.
- **Time-limited JWT in QR:** requires clock sync and longer payload; HMAC sufficient.
- **Keep global TOTP seed:** rejected — trivial forgery.
- **Fetch secrets only when starting death timer:** rejected — fails when the
  player is already offline at the moment of need.

## References
- Task 004: `docs/tasks/done/004-coder.md` (implementation)
- Task 017: `docs/tasks/ready/017-coder.md` (eager prefetch + QR hard-fail)
- Security findings H3, H4, H5
