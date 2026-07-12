# Firebase Setup Guide - RoleKeeper

This guide walks you through connecting RoleKeeper to Firebase.

## Prerequisites

- [Node.js 20+](https://nodejs.org/)
- [Flutter](https://flutter.dev) with Dart 3.x
- [Firebase CLI](https://firebase.google.com/docs/cli): `npm install -g firebase-tools`
- A Google account for [Firebase Console](https://console.firebase.google.com)

---

## Step 1: Create a Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Click **Create a project** (or **Add project**)
3. Name it `RoleKeeper` (or your preferred name)
4. Disable Google Analytics if you prefer (optional for dev)
5. Click **Create project**

---

## Step 2: Configure FlutterFire

Run the FlutterFire CLI to register your app with Firebase and generate config:

```bash
cd /home/jeff/Projects/RoleKeeper
dart run flutterfire_cli:flutterfire configure
```

This will:

- Prompt you to sign in to Firebase (if not already)
- Let you select or create a Firebase project
- Register your Android, iOS, Web, and macOS apps
- Generate `lib/firebase_options.dart` with your project credentials
- Update `android/` and `ios/` with Firebase config files

**Important**: Run this from the project root. You can re-run it anytime to add new platforms or switch projects.

---

## Step 3: Link Firebase Project (Firebase CLI)

If you haven't already, link your local project to the Firebase project:

```bash
firebase use --add
```

Select your project and give it an alias (e.g. `default`). This updates `.firebaserc`.

---

## Step 4: Install Cloud Functions Dependencies

```bash
cd functions
npm install
npm run build
npm test   # optional: LarpManager sync unit tests
cd ..
```

---

## LarpManager read-sync (Cloud Functions)

This project can **mirror** [LarpManager](https://github.com/LoSkana/larpmanager) character export JSON (and optionally per-character inventory/abilities) into Firestore so the Flutter app can read from Firebase offline-first. See [docs/LARPMANAGER_INTEGRATION.md](docs/LARPMANAGER_INTEGRATION.md).

### Prerequisites

- **Blaze (pay-as-you-go)** on the Firebase project — required for **Cloud Scheduler** (the scheduled sync).
- A **dedicated LarpManager account** (maintainer-recommended) with a role that can access `/{event_slug}/export/char/` and, if you enable details, each character’s `inventory/json` and `abilities/json` URLs.
- Deploy **Firestore rules** after pulling changes (new paths below).

### 1. Per-tenant configuration (app + Firestore + Secret Manager)

Integration is **per RoleKeeper game** (`games/{gameId}`), not via `functions/.env`.

1. **Owner / superAdmin** opens **Home → LM Integration** and enters:
   - **Base URL** (e.g. `https://yourorg.larpmanager.com`)
   - **Event slug** (run slug from the LM URL)
   - **Login path** (default `/login/`; try `/accounts/login/` if login fails)
   - **Fetch inventory/abilities** (optional extra HTTP calls)
   - **Username + password** for the dedicated LarpManager account (first save **requires** both)

2. The app calls the Cloud Function **`saveLarpManagerIntegrationConfig`**, which:
   - Writes **non-sensitive** fields to **`games/{gameId}/larpManagerIntegration/config`** (Firestore).
   - Writes a **Secret Manager** secret named **`lm-auth-{sanitizedGameId}`** with payload `password:username:password` (password must not contain `:`). Advanced users can replace the secret value in the [Google Cloud Console](https://console.cloud.google.com/security/secret-manager) with `session:…` for Django session-only auth.

3. **Google Cloud IAM:** the **Cloud Functions** runtime service account (often `PROJECT_ID@appspot.gserviceaccount.com` or the default compute service account) needs permission to **create** secrets and **add versions**. Grant **Secret Manager Admin** on the project (or narrower roles if you create secrets manually). Without this, the first save from the app will fail when creating `lm-auth-*`.

4. No `LARPMANAGER_*` variables in `.env` are required for LarpManager anymore. See [functions/.env.example](functions/.env.example).

### 2. Scheduled sync: who turns it on?

The job **`larpManagerSyncScheduled`** runs **every 15 minutes** and **queries every game** whose **`larpManagerSyncSettings/config`** has **`scheduledSyncEnabled: true`**. For each such game it loads **`larpManagerIntegration/config`** + **Secret Manager** and only then pulls LarpManager, subject to:

- Optional **minimum interval** since `lastSyncedAt` and optional **UTC time window** pass.

**Default:** `scheduledSyncEnabled` is false — **no automatic pulls** until an **owner** or **superAdmin** enables them in **Home → LarpManager sync**.

**Manual “Sync now”** (same screen) calls **`runLarpManagerSyncCallable`** and does **not** require scheduled sync to be on.

### Home Assistant location reads

Staff+ can enable a per-event **Home Assistant** integration under **Home → Home Assistant**. It exposes **`getLatestPlayerLocations`** (API key auth, no Firebase sign-in). See [docs/HOME_ASSISTANT_INTEGRATION.md](docs/HOME_ASSISTANT_INTEGRATION.md).

Deploy with:

```bash
firebase deploy --only functions:getLatestPlayerLocations,functions:configureHomeAssistantIntegration
```

### 3. Deploy functions

```bash
cd functions && npm run build && cd ..
firebase deploy --only functions:saveLarpManagerIntegrationConfig,functions:larpManagerSyncScheduled,functions:runLarpManagerSyncCallable
firebase deploy --only firestore:rules,firestore:indexes
```

### 4. Firestore mirror layout

| Path | Content |
|------|---------|
| `games/{gameId}/larpManagerIntegration/config` | `baseUrl`, `eventSlug`, `loginPath`, `credentialsConfigured` (written by Cloud Function only). _Note: legacy `fetchDetails` field on existing docs is ignored — see `docs/adr/0001-remove-fetchdetails-toggle.md`._ |
| `games/{gameId}/larpManagerMirrorMeta/summary` | `lastSyncedAt`, `lastOk`, `lastError`, `characterCount`, `exportSha256`, … |
| `games/{gameId}/larpManagerMirrorChars/{characterUuid}` | `export`, optional `inventory` / `abilities`, `lastSyncedAt` |
| `games/{gameId}/larpManagerSyncSettings/config` | Scheduled sync on/off, `minIntervalMinutes`, optional UTC window (owner/superAdmin) |

**Security:** Any **member** of the game can read mirror documents (see `firestore.rules`). **Integration** and mirror docs are **not** client-writable. **Sync settings** are writable only by **owner** / **superAdmin**.

### 5. Callables (callable from the app)

| Function | Purpose |
|----------|---------|
| **`saveLarpManagerIntegrationConfig`** | Save URL/slug/flags + push username/password to Secret Manager |
| **`runLarpManagerSyncCallable`** | Manual sync (also **Sync now**) |

### 6. Unit tests (no network)

```bash
cd functions && npm test
```

---

## Step 5: Enable Authentication in Firebase Console

1. In [Firebase Console](https://console.firebase.google.com) → your project
2. Go to **Build** → **Authentication** → **Get started**
3. Enable **Google** sign-in (primary method; aligns with LARP Manager integration)
4. (Optional) Enable **Email/Password** and **Apple** later

**For web builds**: No additional config needed. The app uses Firebase Auth's `signInWithPopup`, which works with your Firebase project config.

---

## Step 5b: Firebase App Check

App Check reduces abuse from non-app clients by attaching attestation tokens to
Firestore, Storage, and callable requests. See
[docs/adr/005-firebase-app-check-walkthrough.md](docs/adr/005-firebase-app-check-walkthrough.md)
for the full rollout checklist.

### Console setup (human steps)

1. Firebase Console → **Build → App Check** → register each app:
   - **Android:** Play Integrity (production)
   - **iOS:** App Attest (DeviceCheck fallback optional)
   - **Web:** reCAPTCHA Enterprise (create site key in Google Cloud Console)
2. **Do not enforce yet** — deploy the client first and confirm tokens appear in metrics.
3. After verification, enforce App Check on **Firestore**, **Storage**, and **Cloud Functions** in Console.

### Local development (debug token)

Debug builds use the App Check **debug provider** (`AndroidProvider.debug` /
`AppleProvider.debug` in `lib/main.dart`).

1. Run the app once in debug mode (`flutter run`).
2. Copy the **App Check debug token** printed in the console log.
3. Firebase Console → **App Check → Manage debug tokens** → add the token for your device/emulator.
4. Re-run the app; Firestore and callable requests should succeed while enforcement is still off.

Each developer machine and CI runner needs its own debug token registered (or a
shared CI token stored as a GitHub Actions secret if you pre-generate one).

### Web builds

Pass the reCAPTCHA Enterprise site key at build time:

```bash
flutter build web --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=your-site-key
```

### Emulators and CI

- **Emulators:** App Check is typically bypassed or satisfied by the debug provider.
  `./scripts/test.sh` and CI emulator runs do not require Play Integrity tokens.
- **CI:** Flutter unit tests do not call production Firebase. If you add integration
  tests against a real project later, register a CI debug token in Console and
  store it in a GitHub Actions secret.

### Callable exceptions

`getLatestPlayerLocations` (Home Assistant API-key auth) intentionally does **not**
enforce App Check. All other callables in `functions/src/index.ts` set
`enforceAppCheck: true`.

---

## Step 6: Run with Emulators (Local Development)

To develop locally without hitting production:

```bash
# Terminal 1: Start emulators
firebase emulators:start --only auth,firestore,storage,functions

# Terminal 2: Run Flutter app
flutter run -d chrome   # or your preferred device
```

**Note**: To use emulators from Flutter, run with `--dart-define=USE_EMULATORS=true`:
`flutter run -d chrome --dart-define=USE_EMULATORS=true`. The app will connect to the Auth emulator. Add `FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080)` in `main.dart` too when using Firestore locally.

### Firestore security rules tests

Automated rules tests live in `functions/src/security/firestoreRules.test.ts` and run against the **Firestore emulator** (port 8080). They are included in `scripts/test.sh` and CI.

With emulators already running:

```bash
cd functions && npm run build && \
  GOOGLE_APPLICATION_CREDENTIALS= FIRESTORE_EMULATOR_HOST=localhost:8080 \
  node --test lib/security/firestoreRules.test.js
```

Or run the full stack (Flutter, Firestore rules, Functions, scripts):

```bash
./scripts/test.sh
```

---

## Step 7: Deploy (When Ready)

```bash
# Build and deploy web app to Firebase Hosting
flutter build web
firebase deploy --only hosting

# Deploy Firestore rules and indexes
firebase deploy --only firestore

# Deploy Cloud Functions
firebase deploy --only functions

# Deploy everything
firebase deploy
```

### Web app URL

After deploying hosting, the app is available at:

- **https://rolekeeper-7ddcc.web.app**
- **https://rolekeeper-7ddcc.firebaseapp.com**

### Custom domain (later)

To use your own domain (e.g. `app.yourdomain.com`):

1. Firebase Console → **Hosting** → **Add custom domain**
2. Enter your domain and follow the DNS instructions (add the A/CNAME records)
3. Firebase provisions SSL automatically

---

## Multi-tenant games (Firestore)

Data for each **game** (tenant) lives under `games/{gameId}`. The app currently uses a single default tenant: `default` (`kDefaultGameId` in code). On first home load after sign-in, the client ensures the user is in that game.

### Layout

| Path | Purpose |
|------|---------|
| `games/{gameId}` | Game metadata (`displayName`, timestamps) |
| `games/{gameId}/members/{userId}` | Role: `owner`, `superAdmin`, `staff`, or `player` |
| `users/{userId}/gameMemberships/{gameId}` | Mirror of membership (same fields) |
| `games/{gameId}/rules/death` | Death rules (was `rules/death`) |
| `games/{gameId}/characters/{characterId}` | Characters |
| `games/{gameId}/characterShortIdLookup/{shortId}` | Short ID → `ownerId` |
| `games/{gameId}/playerActivityEvents/{eventId}` | Activity log (Function mirrors to `users/.../activityEvents`) |
| `games/{gameId}/deathInterventionClaims/{eventId}` | Online medic claims |
| `games/{gameId}/larpManagerIntegration/config` | LM base URL, event slug, flags (`credentialsConfigured` — no password stored) |
| `games/{gameId}/larpManagerMirrorMeta/summary` | LarpManager sync status (Functions only write) |
| `games/{gameId}/larpManagerMirrorChars/{characterUuid}` | Mirrored LM character rows |
| `games/{gameId}/larpManagerSyncSettings/config` | Scheduled sync toggles (owner/superAdmin) |

**Rules (configure death) UI** is limited to **owner** and **superAdmin** (see `GameRole.canConfigureDeathRules`). New users join as **player**. Promote someone in the console by setting `role` on both `games/default/members/{uid}` and `users/{uid}/gameMemberships/default`.

### Migrating existing data

If you used the old top-level paths (`characters`, `rules/death`, `playerActivityEvents`, etc.), copy or move those documents into `games/default/...` before or after deploying the new rules. The app no longer reads the old locations.

---

## Project Structure

```
RoleKeeper/
├── firebase.json          # Firebase project config
├── .firebaserc            # Project aliases (dev/staging/prod)
├── firestore.rules        # Firestore security rules
├── firestore.indexes.json # Firestore composite indexes
├── storage.rules          # Storage security rules
├── functions/             # Cloud Functions (Node.js/TypeScript)
│   ├── src/index.ts       # LarpManager sync, location ping, integrations, etc.
│   ├── src/larpmanager/   # LM HTTP client + sync + tests
│   ├── package.json
│   └── tsconfig.json
└── lib/
    └── firebase_options.dart  # Generated by FlutterFire CLI
```

---

## Services in Use

| Service | Purpose |
|---------|---------|
| **Firebase Auth** | User sign-in (email, Google, Apple) |
| **Cloud Firestore** | Games (multi-tenant), characters, rules per game, events, templates |
| **Cloud Functions** | Active game events, **LarpManager integration save + scheduled/callable sync**, location ping, integrations, etc. |
| **Firebase Storage** | Avatars, character portraits, event media (deferred until needed) |
| **Firebase Hosting** | Serves the Flutter web app |
| **FCM** | Push notifications (Phase 2+) |

---

## Troubleshooting

**"DefaultFirebaseOptions have not been configured"**  
→ Run `dart run flutterfire_cli:flutterfire configure`

**"UnsupportedError not found in windows"**  
→ FlutterFire CLI has a known bug with Windows. Run configure again and **deselect Windows** when asked which platforms to support (select only android, ios, macos, web). Use the web config for Windows builds if needed.

**"Permission denied" on Firestore**  
→ Check `firestore.rules` and ensure the user is authenticated

**Functions fail to deploy**  
→ Run `cd functions && npm run build` and fix any TypeScript errors

**Emulator connection refused**  
→ Ensure `firebase emulators:start` is running before the app
