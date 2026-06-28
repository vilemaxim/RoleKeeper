# Home Assistant integration

RoleKeeper can expose **latest player GPS positions** to [Home Assistant](https://www.home-assistant.io/) during a live LARP event. This is a **read-only REST callable** — Home Assistant polls RoleKeeper; RoleKeeper does not accept webhooks from HA in v1.

## Prerequisites

1. **Location tracking** enabled for the event (`Rules →` location tracking rules — Task 004).
2. **Event session live** (`Rules → Start event`).
3. Players **opted in** to location sharing and actively pinging (Task 005).
4. A staff member (owner, superAdmin, or staff) enables the integration in the app.

## Enable in RoleKeeper

1. Sign in as **staff or above**.
2. Open **Home → Home Assistant**.
3. Turn on **Enable integration**.
4. Copy the **API key** from the one-time dialog and store it securely in Home Assistant.
5. To rotate the key, use **Regenerate API key** (the old key stops working immediately).

The app stores only a **SHA-256 hash** of the key in Firestore (`games/.../integrations/homeAssistant`). Plaintext is never persisted.

## Callable: `getLatestPlayerLocations`

- **Region:** `us-central1` (same as other RoleKeeper callables).
- **Auth:** No Firebase Auth required when a valid API key is supplied.
- **Body:**
  ```json
  {
    "gameId": "yourInstanceId::yourEventSlug",
    "apiKey": "paste-key-from-app"
  }
  ```
- **Response:**
  ```json
  {
    "players": [
      {
        "playerId": "firebase-uid",
        "latitude": 51.5074,
        "longitude": -0.1278,
        "accuracy": 12.5,
        "timestamp": { "...": "Firestore Timestamp" },
        "presenceState": "in_game",
        "inGame": true
      }
    ]
  }
  ```

Only **opted-in** members with at least one ping in the **last 15 minutes** are included. **Out-of-game** players appear when they have recent pings (anti-cheat / staff workflows).

Invalid keys, disabled integration, or unknown tenants all return **`permission-denied`** with a generic message (no tenant enumeration).

## Example: REST sensor (Home Assistant)

Replace placeholders with your Firebase project id, tenant key, and API key.

```yaml
rest:
  - resource: "https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/getLatestPlayerLocations"
    method: POST
    headers:
      Content-Type: "application/json"
    payload: '{"gameId":"INSTANCE::EVENT","apiKey":"YOUR_API_KEY"}'
    scan_interval: 60
    sensor:
      - name: "LARP player locations"
        value_template: "{{ value_json.players | length }}"
        json_attributes:
          - players
```

Use `json_attributes.players` in automations (radius checks, notifications, etc.). Parse `latitude` / `longitude` per entry as needed.

## Key rotation

1. In RoleKeeper: **Home Assistant → Regenerate API key**; copy the new key.
2. Update the HA REST sensor / secret store with the new `apiKey` value.
3. Reload or restart the integration.

Old keys fail immediately after regeneration.

## Security notes

- Treat the API key like a password; restrict who can view HA configuration.
- Disable the integration in RoleKeeper when not needed for an event.
- Responses are capped (500 players) to limit abuse.

## Related docs

- [docs/adr/001-location-tracking-and-presence.md](adr/001-location-tracking-and-presence.md)
- [FIREBASE_SETUP.md](../FIREBASE_SETUP.md)
