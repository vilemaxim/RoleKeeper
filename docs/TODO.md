# RoleKeeper TODO

Tracked follow-ups and setup tasks. Check items off as completed.

---

## Flutter — `reportAppError` refactor

**Goal:** All user-visible errors use `reportAppError` from `lib/utils/error_reporting.dart` (see `.cursor/rules/error-handling.mdc`). Raw errors go to the terminal; UI shows mapped or generic user text.

**Already migrated:** `characters_screen`, `larp_manager_integration_screen`, `larp_manager_sync_settings_screen`, `larp_setup_flow_screen` (organizer finish path).

- [ ] `lib/screens/home_screen.dart` — registration verify, sign out, etc.
- [ ] `lib/screens/sign_in_screen.dart`
- [ ] `lib/screens/larp_picker_screen.dart`
- [ ] `lib/screens/larp_setup_flow_screen.dart` — remaining `catch` paths
- [ ] `lib/screens/create_character_screen.dart`
- [ ] `lib/screens/medic_scan_screen.dart`
- [ ] `lib/screens/death_timer_screen.dart` (user-facing failures only)
- [ ] `lib/utils/active_events_utils.dart` (if surfaced to UI)
- [ ] Audit `lib/services/*` — only where errors propagate to UI; keep silent catches where intentional

---

## Firebase Auth — custom domain

**Goal:** Replace the default Firebase Auth hostname (`rolekeeper-7ddcc.firebaseapp.com`) with a branded domain so Google sign-in and OAuth redirects use your domain (e.g. `app.yourdomain.com`).

**Current state (project config):**

| Item | Value |
|------|--------|
| Auth domain | `rolekeeper-7ddcc.firebaseapp.com` (`lib/firebase_options.dart`) |
| Hosting | `https://rolekeeper-7ddcc.web.app`, `https://rolekeeper-7ddcc.firebaseapp.com` |
| Web sign-in | Google `signInWithPopup` — OAuth may show `…firebaseapp.com/__/auth/handler` |

Replace `app.yourdomain.com` below with the real hostname (e.g. `app.rolekeeper.com`).

### Hosting & Firebase Console

- [ ] Choose production hostname (e.g. `app.yourdomain.com`)
- [ ] Firebase Console → **Hosting** → **Add custom domain** → enter hostname
- [ ] Add DNS records at registrar (A/AAAA or CNAME per Firebase instructions)
- [ ] Wait until Hosting shows domain **Connected** (SSL provisioned)
- [ ] **Authentication** → **Settings** → **Authorized domains** — confirm custom domain is listed (add manually if needed)
- [ ] **Authentication** → **Settings** → enable **custom auth domain** for the Hosting domain (complete any extra DNS verification)

### Google Cloud OAuth (required for Google sign-in)

- [ ] [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials?project=rolekeeper-7ddcc) → open **Web client** used by Firebase Auth
- [ ] **Authorized JavaScript origins** — add `https://app.yourdomain.com` (keep `firebaseapp.com` / `web.app` / `localhost` during transition)
- [ ] **Authorized redirect URIs** — add `https://app.yourdomain.com/__/auth/handler` (keep `https://rolekeeper-7ddcc.firebaseapp.com/__/auth/handler` until cutover is verified)

### App config & deploy

- [ ] Update `authDomain` in `lib/firebase_options.dart` to `app.yourdomain.com` (or run `dart run flutterfire_cli:flutterfire configure` after console setup)
- [ ] `flutter build web` && `firebase deploy --only hosting`
- [ ] Verify sign-in at `https://app.yourdomain.com` — Google should show your domain, redirect to `…/yourdomain.com/__/auth/handler`

### Local dev

- [ ] Confirm `localhost` remains in **Authorized domains** for `flutter run -d chrome`
- [ ] Document whether local builds keep default `authDomain` or use custom domain (optional)

**Notes:** No changes needed in `AuthService` or Cloud Functions for domain swap. Android/iOS use package-based OAuth, not `authDomain`.

**References:** [Firebase Auth custom domain](https://firebase.google.com/docs/auth/web/custom-domain), `FIREBASE_SETUP.md` (hosting section).
