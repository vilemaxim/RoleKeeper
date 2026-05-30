# RoleKeeper

Rule-agnostic character and event management for LARP and murder-mystery games. Flutter client with Firebase (Auth, Firestore, Cloud Functions).

## Setup

1. **Flutter** — [install Flutter](https://docs.flutter.dev/get-started); Dart 3.x.
2. **Firebase** — follow **[FIREBASE_SETUP.md](FIREBASE_SETUP.md)** (FlutterFire CLI, emulators, deploy).
3. **LarpManager sync (optional)** — hosted or self-hosted [LarpManager](https://github.com/LoSkana/larpmanager) can be mirrored into Firestore via Cloud Functions. Full design: **[docs/LARPMANAGER_INTEGRATION.md](docs/LARPMANAGER_INTEGRATION.md)**. Quick ops: **FIREBASE_SETUP.md → “LarpManager read-sync”**.

### LarpManager sync cheat sheet

1. **Deploy** Cloud Functions (see [FIREBASE_SETUP.md](FIREBASE_SETUP.md)) and grant the Functions runtime service account **Secret Manager Admin** (or equivalent) so it can create `lm-auth-*` secrets.
2. **Owner / superAdmin:** **Home → LM Integration** — enter base URL, event slug, login path, optional fetch-details flag, and LarpManager **username + password** (first save). Non-sensitive fields go to Firestore (`games/{gameId}/larpManagerIntegration/config`); credentials go to **Secret Manager** (`lm-auth-{gameId}`), not Firestore.
3. **Home → LarpManager sync** — enable **scheduled sync** if you want automatic pulls; use **Sync now** for a manual run.
4. Mirror paths: `games/{gameId}/larpManagerMirrorMeta/summary` and `games/{gameId}/larpManagerMirrorChars/{id}`.

## Testing

**Flutter**

```bash
flutter test
```

**Cloud Functions (LarpManager helpers, no live HTTP)**

```bash
cd functions && npm test
```

Pre-push hook (optional):

```bash
./scripts/pre-push.sh
ln -sf ../../scripts/pre-push.sh .git/hooks/pre-push
```

CI runs tests on push/PR to `main`.

## Resources

- [Flutter documentation](https://docs.flutter.dev/)
