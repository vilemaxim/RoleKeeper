# ADR 001: Location Tracking and Player Presence

## Status

Accepted (2026-06-27)

## Context

RoleKeeper is a multi-tenant LARP helper (Flutter PWA + Firebase). Organizers
(`owner`, `superAdmin`) configure per-LARP features; players operate within
tenant-scoped permissions.

We need continuous location collection during live events for multiple use
cases:

- **Anti-cheat** — verify a player was near a QR scan location (or flag/report
  mismatches).
- **In-game mechanics** — radius-based effects on players who are *in game*.
- **Skill-based tracking** — players with the right skill may locate other
  players, NPCs, or in-game items (future).
- **Emergency aid** — staff can locate a missing player.

Location must be available to **staff** and to **Home Assistant** for
automation during a game. Some player-visible location (skill-based) is
planned later.

The app is currently a **PWA**; native App Store builds are expected soonish.
BLE beacon accuracy can wait for native apps.

Death-timer events already attach optional GPS snapshots via
`ActivityEventLocation` → `createActiveGameEvent`. That pattern is
point-in-time; continuous tracking needs a separate, higher-volume store.

Players must **opt in** to location collection (v1). Admins may require it in a
later round. Admins need visibility into who has opted in (later round).

Players need an **out-of-game (OOC)** state for in-game mechanics, but OOC
players must **still be location-tracked** when opted in — they can cheat for
in-game allies, and staff/emergency workflows still need their position.

## Decision

### 1. Tenant-scoped configuration

| Document | Path | Purpose |
|----------|------|---------|
| Location rules | `games/{instanceId}/events/{eventSlug}/rules/locationTracking` | Admin enables tracking; `pingIntervalSeconds` (default 60, clamp 30–300) |
| Event session | `games/{instanceId}/events/{eventSlug}/eventSession/config` | Admin marks event **live**; pinging only while `isLive` |
| Member presence | `games/{instanceId}/events/{eventSlug}/members/{uid}` | `locationOptIn`, `presenceState`, `presenceUpdatedAt` |
| Location pings | `games/{instanceId}/events/{eventSlug}/locationPings/{id}` | Append-only time series |

Follow existing patterns: `RulesRepository`, `rules/{ruleId}` Firestore rules,
`canConfigureGameRules` for admin writes.

### 2. Presence is orthogonal to location collection

- `presenceState`: `in_game` | `out_of_game` (default `in_game`).
- **Opted-in players are pinged continuously while the event is live**, regardless
  of `presenceState`.
- Each ping records `presenceState` at send time.
- **In-game mechanics** (radius effects, skill tracking UI) filter to
  `presenceState == in_game` on the consumer side.
- **Anti-cheat and staff/emergency** use all pings regardless of presence.

### 3. Writes via callable only

`recordLocationPing` Cloud Function validates:

- Authenticated member of the tenant
- `rules/locationTracking.enabled == true`
- `eventSession/config.isLive == true`
- `members/{uid}.locationOptIn == true`

Does **not** reject on `presenceState`.

Client-side direct Firestore creates on `locationPings` are denied.

### 4. Location payload extensibility

Extend `ActivityEventLocation` (or a sibling type) with:

- `source`: `'gps'` in v1; future `'beacon'`, `'wifi'`
- Optional `beaconId`, `venueZoneId` (unused until native/beacon task)

Pings include `inGame` derived from `presenceState == in_game` for convenient
queries, plus the raw `presenceState` field.

### 5. Permissions: conditional, not startup

Remove location from the global `AppPermissionsWrapper` gate. Request
geolocation only when tracking is enabled, event is live, and the player has
opted in (or is about to opt in).

Implement **PWA web geolocation** in `LocationUtils` (browser API). Accept
iOS Safari PWA limitations: foreground-only continuous pings in v1.

### 6. Home Assistant integration

Per-tenant API key in `integrations/homeAssistant/config` (hashed at rest).
`getLatestPlayerLocations` callable returns recent positions for opted-in
members with pings in a configurable window (e.g. last 15 minutes). Staff+
configure/regenerate the key in-app.

### 7. Retention

Pings live under the tenant event path with no TTL in v1. Event archival is a
separate future task; data remains queryable for anti-cheat lookback.

### 8. Deferred (explicit out of scope for tasks 001–006)

- Staff map / player viewer UI
- Admin opt-in dashboard and stale-ping alerts
- QR scan geo-verification and radius effects
- Skill-based player/item tracking
- Mandatory location (admin override of opt-in)
- BLE beacon location provider (native apps)
- Event archive workflow
- Auto start/stop event session from schedule

## Consequences

### Positive

- Clear separation: high-volume pings vs discrete `activeEvents`
- Anti-cheat can audit OOG players at QR locations
- Mechanics can safely ignore OOG players without losing telemetry
- HA can drive physical effects during live events
- GPS provider abstraction ready for beacons on native builds

### Negative / risks

- Continuous pings increase Firestore write volume — monitor cost; batching may
  be needed later
- PWA background tracking is limited; pings stop when the app is backgrounded on
  some platforms
- Player privacy: opt-in copy and future mandatory mode need careful UX
- HA API key compromise exposes live positions — rate limit and rotate keys

## References

- `lib/utils/location_utils.dart` — existing native geolocation (web stubbed)
- `lib/models/activity_event.dart` — `ActivityEventLocation`
- `lib/services/rules_repository.dart` — death rules pattern
- `lib/models/death_rules.dart`, `lib/screens/rules_screen.dart`
- `functions/src/index.ts` — `createActiveGameEvent`, `sanitizeLocation`
