# LarpManager Integration Design

This document explores integrating [RoleKeeper](.) with [LarpManager](https://github.com/LoSkana/larpmanager), a free LARP event management platform. The goal: pull character data from LarpManager, cache it on the phone, and use it for character sheets and rules aids.

## Executive Summary

**Yes, integration is possible.** LarpManager-side access patterns:

1. **Authenticated (per player)** (default for player-owned data): The player logs into their LarpManager account (e.g. WebView). Their session is used to fetch **only their** characters via JSON/HTML endpoints. Data stays behind login—no public URLs. The same session can live **only on device** or be stored **encrypted server-side** so a **backend worker** talks to LarpManager (client reads Firestore)—same trust model, different where HTTP runs.
2. **External Access** (secret URLs): Unauthenticated secret URLs per character. Simpler for players without accounts, but exposes data to anyone with the link.
3. **Dedicated export account** (organizer + maintainer guidance): For **read-only** server sync, LoSkana recommends a **fictional LarpManager user** with an appropriate **role**, using the **JSON export view** for character sheets and inventory (most reliable export path). Password rotation like a service account. See [Approach C](#approach-c-dedicated-export-account-maintainer-guidance).

**RoleKeeper architecture choice:** Data can be fetched **on-device** (client calls LarpManager) or by a **backend sync worker** (server polls LarpManager, app reads Firestore only). For **bulk event data** on hosted [larpmanager.com](https://larpmanager.com), use **(3)** with organizer cooperation—not a “global API key,” but a **provisioned LM account** the maintainer described as appropriate for this use case. Otherwise backend sync uses **(1)** per user and/or **(2)** per token. See [Trust model and deployment targets](#trust-model-and-deployment-targets) and [Backend sync worker](#backend-sync-worker-rolekeeper-server).

---

## Approach A: Authenticated Access (Recommended)

**No data exposed to unauthenticated users.** The user logs into their LarpManager account; RoleKeeper fetches only the characters they're assigned to.

### How It Works

1. User taps "Link LarpManager" and is shown a **WebView** with LarpManager's login page.
2. User logs in with their normal credentials (email/password or Google SSO).
3. App captures the **session cookie** after successful login.
4. Using that session, RoleKeeper calls LarpManager's authenticated endpoints.
5. Access is enforced by LarpManager: users only get data for characters they own/are assigned to.

### Authenticated Endpoints Available

| Endpoint | Returns | Use |
|----------|---------|-----|
| `/{event_slug}/character/list/json/` | `[{uuid, name}, ...]` | List user's characters for an event |
| `/{event_slug}/character/{uuid}/` | Full HTML character sheet | Main sheet (parse for display) |
| `/{event_slug}/character/{uuid}/abilities/json/` | Abilities by type | Rules aids |
| `/{event_slug}/character/{uuid}/inventory/json/` | Inventory balances | Rules aids |

All require `@login_required` and `get_char_check(restrict_non_owners=True)`—only the character's assigned player (or event staff) can access.

### Implementation

```dart
// 1. WebView login flow - user logs in, we capture session cookie
// 2. Store sessionid cookie securely (e.g. flutter_secure_storage)
// 3. Use cookie for subsequent requests:
final response = await dio.get(
  '$baseUrl/$eventSlug/character/list/json/',
  options: Options(
    headers: {'Cookie': 'sessionid=$sessionId'},
  ),
);
```

**Cookie handling**: Use `flutter_inappwebview` and `CookieManager` to read the `sessionid` cookie after login, or `dio`'s cookie jar if you can inject it into the login flow.

### Trade-offs

| Pros | Cons |
|------|------|
| Data never exposed without auth | User must have LarpManager account |
| Uses existing LarpManager security | WebView login UX required |
| Only fetches *their* characters | Still need to parse HTML for full sheet (no single JSON endpoint) |
| No secret URLs to leak | Session handling (refresh, expiry) |

---

## Approach B: External Access (Secret URLs)

*Not recommended if you want to keep data behind authentication.*

### What It Does

When organizers enable **External Access** in Event → Writing configuration:

- A key icon appears next to each character
- Each character has a unique **access token** (12 characters, URL-safe)
- Organizers can copy a **secret URL** to share with players who aren't signed up

From the [ Characters tutorial](https://larpmanager.com/tutorials/characters/):

> **External Access**: If you want to allow any user to access the complete sheet of a character, enable this option. In the characters' page, a key icon will appear next to the character's name, with the link to share to allow to do so.

### URL Format

```
https://{larpmanager-host}/{event_slug}/character/external/{access_token}/
```

**Example** (larpmanager.com):
```
https://larpmanager.com/my-event-2025-1/character/external/AbCdEf123456/
```

**Components**:
- `event_slug`: Run identifier, e.g. `my-event-2025-1` (event name + run number)
- `access_token`: Per-character 12-char code from `Character.access_token`

### Requirements

1. **Event config**: `writing_external_access` must be enabled
2. **Per-character token**: Each character has its own token; organizers get it from the key icon

---

## Approach C: Dedicated export account (maintainer guidance)

**Context:** Direct guidance from **LoSkana** (LarpManager maintainer, [LoSkana/larpmanager](https://github.com/LoSkana/larpmanager)) for **read-only** sync into an app stack such as Firebase—paraphrased from maintainer conversation; confirm URLs and permissions in your LM build/UI.

**Summary of suggestion:**

- Treat the integration as **read-sync**: RoleKeeper reads updated data from LarpManager; it does not write sheet/inventory back through this path unless you design something separate.
- Prefer LarpManager’s **JSON export** for character sheets and inventory—the maintainer describes this as the **most reliable** way to export that data (as opposed to scraping HTML). Record the exact **view URL** and response shape from your instance once you locate it in the UI or codebase.
- Create a **dedicated fictional LarpManager user** used only for automation; assign a **role** that can access whatever must be exported; **rotate its password** on a schedule like any service account. Store credentials in **Secret Manager** (or equivalent), never in source control.
- **Before the event** (e.g. night before): run a full export load into Firebase/Firestore for a clean baseline.
- **During the event:** Re-run the export or poll that endpoint on an interval so inventory/progression stays fresh—there is still no documented outbound webhook from LM to you, so this remains **polling** unless that changes upstream ([Sync semantics](#sync-semantics)).

**Relationship to other approaches:** This is **organizer-approved bulk read**. It does not replace **Approach A** if you want each player to link their own LM identity for personal workflows; you can use **C** for “event mirror in Firebase” and **A** for optional per-player features, as long as data flows and privacy are clear to players.

**Respect for operators:** Use **reasonable poll intervals**, handle **429/5xx** with backoff, and avoid hammering [larpmanager.com](https://larpmanager.com) or any self-hosted instance.

---

## What the External URL Returns

The external URL returns a **full HTML page** (Django-rendered template). No JSON API is exposed for external access today.

**Character sheet includes**:
- Presentation (name, title, teaser)
- Custom fields (organizer-defined)
- Factions
- Plots
- Abilities (Experience Points / PX system)
- Inventories
- Relationships
- Quests / traits
- Prologues

Source: `larpmanager/views/user/character.py` → `character_external()` → `_character_sheet()`

---

## HTML Parsing & Implementation Notes

### HTML Parsing (Required for Full Sheet)

**Flow**:
1. User pastes/enters the External Access URL (or event slug + token)
2. App fetches the HTML with `http`/`dio`
3. Parse HTML with `html` or `xml` package
4. Extract structured data into local models
5. Cache in SQLite / Hive / Isar

**Pros**:
- Works with existing LarpManager
- No server changes
- Works with hosted larpmanager.com and self-hosted instances

**Cons**:
- Parsing can break if templates change
- Need to reverse-engineer HTML structure
- More work to handle all sheet sections (abilities, inventories, etc.)

**Implementation sketch**:
```dart
// lib/services/larpmanager_client.dart
class LarpManagerClient {
  Future<CharacterSheet> fetchCharacterSheet(String baseUrl, String eventSlug, String accessToken) async {
    final url = '$baseUrl/$eventSlug/character/external/$accessToken/';
    final response = await http.get(Uri.parse(url));
    return CharacterSheetParser.parse(response.body);
  }
}
```

---

### Approach 2: Contribute JSON Endpoint to LarpManager (Best Long-Term)

**Flow**:
1. Add `?format=json` or `Accept: application/json` support to `character_external`
2. LarpManager returns structured JSON instead of HTML when requested
3. RoleKeeper fetches JSON and caches it directly

**Pros**:
- Stable, versioned data structure
- Easy to extend for rules aids
- Benefits other integrations
- LarpManager is AGPL open source; PR is feasible

**Cons**:
- Requires PR and maintainer approval
- May take time to land

**Example PR** (in `larpmanager/views/user/character.py`):
```python
def character_external(request, event_slug: str, code: str):
    # ... existing validation ...

    if request.GET.get('format') == 'json' or 'application/json' in request.META.get('Accept', ''):
        return JsonResponse(get_character_sheet_json(context))
    return _character_sheet(request, context)
```

---

### Approach 3: WebView + Offline HTML Cache

**Flow**:
1. Show External Access URL in an in-app WebView when online
2. Use `flutter_inappwebview` or similar to cache the page for offline
3. Optionally parse cached HTML when offline for rules aids

**Pros**:
- Minimal custom parsing
- Exact visual match to LarpManager

**Cons**:
- WebView is heavy
- Hard to reuse structured data for rules aids
- Mostly “view only”, not ideal for rules logic

---

## Recommended Path

1. **Implement Approach A** (authenticated access) so data stays behind login.
2. WebView login → capture session → call `character/list/json` to get character UUIDs.
3. For each character: fetch HTML from `character/{uuid}/` and parse; optionally fetch `abilities/json` and `inventory/json` for rules data.
4. Cache locally; handle session expiry (prompt re-login when 401). “view full sheet in browser” when parsing is incomplete.

**If the app should not call LarpManager directly:** Use a [backend sync worker](#backend-sync-worker-rolekeeper-server) that stores delegated credentials encrypted server-side, polls the same HTTPS endpoints, and writes normalized documents to Firestore. The Flutter client then matches the rest of RoleKeeper’s sync story.

---

## Trust model and deployment targets

This section records **decisions** for how RoleKeeper obtains authority to read character and inventory data from LarpManager.

### Hosted larpmanager.com (no self-host)

| Mode | When to use | Authority |
|------|-------------|-----------|
| **Per-user delegated session (Hybrid A)** | Default. Player has a LarpManager account. | User completes LM login (WebView or one-time link flow); RoleKeeper stores `sessionid` only for that user (on-device or encrypted in backend). Polls **that user’s** list and sheets only. |
| **Per-character external token (Hybrid B)** | Player has no LM account; organizer enabled external access and shares the secret URL/token. | Bearer is the token; anyone with the token can read the sheet—treat as a password. Prefer backend storage with encryption if tokens are centralized. |
| **Dedicated export user + JSON export (Hybrid C)** | Organizer wants **one reliable server-side pipe** for sheets/inventory on hosted LM; maintainer-aligned. | Fictional LM user + **role** with export access; maintainer recommends **JSON export view**; session or login from worker; **rotate password**; see [Approach C](#approach-c-dedicated-export-account-maintainer-guidance). |

**Decision:** For hosted LM, **primary trust model for per-player data = Hybrid A**; **Hybrid B** when external access is in play; **Hybrid C** when the organizer will run a **dedicated export account** and RoleKeeper uses the **JSON export** path for bulk read-sync (maintainer-suggested). **Hybrid C** is not a public “API key for all tenants”—it is **per-event / per-org** provisioning by the people who own the LarpManager event.

### Self-hosted LarpManager (organizer controls the instance)

| Mode | When to use | Trade-off |
|------|-------------|-----------|
| **Same as hosted (A/B)** | Minimal ops; stay on upgrade path of stock LM. | Same limits as hosted for bulk read. |
| **Read Postgres (or LM DB) directly** | Need bulk, low-latency reads and you operate the DB. | Strong **schema coupling** to LM migrations; secure network access only. |
| **Custom API or webhooks on a fork** | Stable JSON contract and/or push sync to RoleKeeper. | **Fork maintenance** or dependency on an **upstream PR**; AGPL obligations for modified deployments ([LarpManager license](https://github.com/LoSkana/larpmanager/blob/main/LICENSE)). |

**Decision:** For self-hosted orgs with strict integration SLAs, prefer **upstream PR first** ([Upstream: JSON PR vs webhooks vs fork](#upstream-json-pr-vs-webhooks-vs-fork)); use a **short-lived fork** only when merge latency or bespoke hooks are unacceptable, and plan to reconcile with main.

---

## Sync semantics

LarpManager does not document **outbound webhooks** to third parties as of this design. Until those exist, “as real time as possible” means **polling** plus **on-demand** refresh, with an optional **future webhook** path.

### Background polling

- **Interval:** Start with **5–15 minutes** while the user has an active session or the backend worker is scheduled; increase under **429** responses or LM instability.
- **Backoff:** Exponential backoff on repeated **401** (expired session—stop until user re-links) or **5xx**.
- **Scope:** After `character/list/json/`, poll each linked character’s `inventory/json/` and `abilities/json/` (and HTML sheet if needed) only when hashes or `lastSyncedAt` warrant it, to reduce load.
- **Bulk JSON export (Hybrid C):** If the organizer uses a **dedicated export user**, poll the **JSON export** endpoint on the same kind of schedule (tighter during active play, looser overnight); parse one payload into per-character documents in Firestore as needed.

### On-demand sync

- Trigger full fetch for one character when the user **opens** the character sheet, **pull-to-refresh**, or completes **Link LarpManager**.
- Optionally debounce rapid opens (e.g. 30–60 seconds) to avoid stampedes.

### Change detection

- Compare **ETag** / **Last-Modified** if LM responses expose them; otherwise store a **content hash** of JSON payloads and skip writes when unchanged.

### Future: webhook upgrade path

If LarpManager (or a fork) can **POST signed events** to a RoleKeeper HTTPS endpoint (character updated, inventory changed):

1. **Verify** HMAC or Ed25519 signature with a per-event shared secret rotated by organizers.
2. **Idempotency:** `event_id` deduplication in Firestore or Cloud Function memory store.
3. **Retries:** Respond `2xx` quickly; enqueue work to refresh the affected character from LM if the payload is only a “ping.”

Until then, document **poll + on-demand** as the supported near–real-time story.

---

## Backend sync worker (RoleKeeper server)

Use this when the **Flutter client must not** talk to LarpManager (single backend, unified auth). The worker calls LarpManager over HTTPS using credentials that match **Hybrid A**, **B**, or **C**—never unverified JSON invented by the client.

### Flow

```text
User links LM (WebView or paste token) → app sends credential material to backend (over TLS) →
worker encrypts at rest → scheduled/on-demand job polls LM → writes Firestore → client reads Firestore only
```

For **Hybrid C**, the flow is **organizer-side**: an admin creates the fictional user and stores credentials in **Secret Manager**; the worker logs in (or refreshes a session) and calls the **JSON export** view—players may not need to send any LM secret to Firebase.

### Credential storage (encrypted at rest)

- **Session-based (A):** Store **encrypted blob** containing `sessionid` (and optionally `csrftoken` if required for POST paths). Never log cookie values.
- **External token (B):** Store **encrypted** `access_token` + `baseUrl` + `event_slug`.
- **Dedicated export user (C):** Store **encrypted** username + password (or a long-lived session blob if you implement login once and refresh) in **Secret Manager**, scoped per **event** or **organization**. Rotate the password on a cadence the organizer accepts; restrict which Cloud Functions can read the secret.
- **Encryption:** Use a **KMS-backed** key (e.g. Google Cloud KMS envelope encryption) or Firebase/App Check–protected Cloud Functions with secrets in **Secret Manager**. Per-user **data encryption keys** derived from a root secret improve blast-radius containment if a single document leaks.

### Suggested Firestore shape (illustrative)

Namespacing should align with existing RoleKeeper `ownerId` / user document patterns.

| Collection path (example) | Purpose |
|---------------------------|---------|
| `users/{uid}/larpManagerLinks/{linkId}` | `baseUrl`, `eventSlug`, `mode` (`session` \| `external`), `encryptedPayload`, `createdAt`, `lastPollAt`, `lastError` |
| `users/{uid}/larpManagerCharacters/{characterUuid}` | Normalized sheet fields, `abilities`, `inventory` snapshots, `lastSyncedAt`, `contentHash`, `sourceLinkId` |
| `games/{gameId}/larpManagerMirrorMeta/summary` | Implemented in Cloud Functions: sync status (`lastOk`, `exportSha256`, `characterCount`, …). |
| `games/{gameId}/larpManagerMirrorChars/{characterUuid}` | Per-character mirror (`export`, optional `inventory` / `abilities`). Any game member can read today — tighten rules if needed. |
| `games/{gameId}/larpManagerIntegration/config` | **Connection** (per tenant): `baseUrl`, `eventSlug`, `loginPath`, `credentialsConfigured`. Written by **`saveLarpManagerIntegrationConfig`** only. **Username/password** are **not** stored here — they live in **Secret Manager** as secret id `lm-auth-{sanitizedGameId}`. _Note: pre-Task-012 docs may still carry a `fetchDetails: bool` field; the loader ignores it. See `docs/adr/0001-remove-fetchdetails-toggle.md`._ |
| `games/{gameId}/larpManagerSyncSettings/config` | **Scheduled** sync on/off (`scheduledSyncEnabled`, default false), `minIntervalMinutes`, optional UTC window — **not** exposed in the app; change via Firestore/console if needed. Cloud Scheduler still ticks every 15 minutes but the function **skips** the pull unless this doc allows it. **Manual** callable sync ignores these flags. |

**Rules:** Firestore security rules must ensure **only `uid`** can read/write their link and cached character docs. The sync worker uses **Admin SDK** with logic that restricts writes to documents owned by the user who registered the link. **Hybrid C** mirrors may require **per-field or per-document** rules so a full-event export in Firestore does not leak across players.

### PII and retention

- Store **only** fields needed for character display and rules aids (name, abilities, inventory counts, etc.). Avoid persisting full HTML long-term if structured JSON is enough.
- Define **retention:** e.g. delete `larpManagerLinks` and cached characters **N days** after event end or on user unlink.
- Document processing in line with your privacy policy (LarpManager remains the source of truth for organizer-owned data).

### Implementation notes

- Run polls from **Cloud Functions (scheduled)** + **on-call HTTP** (user taps Sync) to match on-demand semantics above.
- Rate-limit **per uid** to protect LM and your quota.

---

## Upstream: JSON PR vs webhooks vs fork

### JSON on existing views (recommended first PR)

- Extend authenticated and/or external character views to return **JSON** when `Accept: application/json` or `?format=json` (see sketch under [Approach 2: Contribute JSON Endpoint](#approach-2-contribute-json-endpoint-to-larpmanager-best-long-term)).
- **Pros:** Low controversy, removes HTML parser fragility for integrators, works on larpmanager.com once released.
- **Cons:** Maintainer time for review; need a **versioned schema** (`schema_version` field) to avoid breaking apps.

**Evaluation:** **Pursue JSON PR first** before webhooks—it delivers the largest win for RoleKeeper and other clients with the smallest operational surface area for LM operators.

### Webhooks (second phase)

- **Pros:** True push-driven near–real-time; fewer polls against LM.
- **Cons:** Delivery guarantees, **signing**, replay protection, organizer UX for endpoint URL + secrets, abuse monitoring.

**Evaluation:** Propose **after** JSON is accepted, with a minimal MVP (e.g. “inventory changed” ping + character id) so RoleKeeper still verifies by re-fetching JSON.

### Fork vs upstream

| Path | Use when |
|------|----------|
| **Upstream only** | You can wait for releases; integration targets many events on larpmanager.com. |
| **Short-lived fork** | One org self-hosts and needs hooks **now**; budget to **rebase** on upstream and contribute patches back. |
| **Long-lived fork** | Discouraged: AGPL and merge debt; prefer **feature flags in upstream** if maintainers agree. |

---

## Data Model (RoleKeeper)

Suggested local model for cached character data:

```dart
class CachedLarpManagerCharacter {
  final String id;           // Character UUID from LarpManager
  final String eventSlug;
  final String? accessToken;  // Only for Approach B; null when using Approach A
  final String name;
  final String? title;
  final String? presentation;
  final String? fullText;
  final List<LarpManagerField> customFields;
  final List<LarpManagerAbility> abilities;
  final List<LarpManagerFaction> factions;
  final List<LarpManagerRelationship> relationships;
  final List<LarpManagerInventory> inventories;
  final DateTime lastSyncedAt;
  final String sourceUrl;     // Full external URL for refresh
}
```

---

## User Flow

1. **Link LarpManager**: User taps "Link LarpManager", selects/enters base URL.
2. **Login**: WebView shows LarpManager login; user signs in.
3. **Fetch**: App captures session, fetches character list and sheets.
4. **Rules aids**: Use cached abilities, inventories, etc. in rules logic.
5. **Refresh**: Pull-to-refresh or “Sync” to re-fetch and update cache.

---

## Technical Notes

### URL discovery

Organizers get the URL from:
- Event → Characters → Key icon next to character name
- Template: `{% url 'character_external' run.get_slug el.access_token %}`

### Self-hosted vs larpmanager.com

- **larpmanager.com**: Use `https://larpmanager.com` as base
- **Self-hosted**: User provides base URL (e.g. `https://larp.example.org`)

### Caching

Suggested stack:
- **HTTP**: `dio` with caching (or `http` + manual cache)
- **Storage**: `sqflite` or `isar` for structured data
- **Sync**: Simple “last synced” timestamp; optional background refresh

---

## Next Steps

1. [ ] Add `http`/`dio` and `html` to `pubspec.yaml`
2. [ ] Create `LarpManagerClient` and `CharacterSheetParser`
3. [ ] Define `CachedLarpManagerCharacter` model and local DB schema (or Firestore equivalents per [Backend sync worker](#backend-sync-worker-rolekeeper-server))
4. [ ] Add “Link LarpManager character” flow in app
5. [ ] Build character sheet display using cached data
6. [ ] Connect rules aids to cached abilities/inventories
7. [x] Cloud Functions mirror: `larpManagerSyncScheduled`, `runLarpManagerSyncCallable` → `games/{gameId}/larpManagerMirrorMeta/summary` + `larpManagerMirrorChars/*` (see [FIREBASE_SETUP.md](FIREBASE_SETUP.md)); optional: per-user `larpManagerLinks` + encryption ([Sync semantics](#sync-semantics))
8. [ ] (Optional) Draft PR to LarpManager: JSON on character views, then evaluate webhooks ([Upstream](#upstream-json-pr-vs-webhooks-vs-fork))
9. [ ] When using [Approach C](#approach-c-dedicated-export-account-maintainer-guidance): document the exact **JSON export** URL and payload shape from your LarpManager version (UI or source), and confirm the **role** needed for that view

---

## References

- [LarpManager GitHub](https://github.com/LoSkana/larpmanager)
- [LarpManager Characters Tutorial](https://larpmanager.com/tutorials/characters/)
- [Feature Descriptions](https://github.com/LoSkana/larpmanager/blob/main/docs/06-feature-descriptions.md) (Character Feature, Player Editor Feature)
- Source: `larpmanager/views/user/character.py` (character_external)
- Source: `larpmanager/models/writing.py` (Character.access_token)
- Source: `larpmanager/urls/event.py` (character_external route)
