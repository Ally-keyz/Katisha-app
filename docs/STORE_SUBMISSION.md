# Katisha — Store Submission Guide

Production-readiness checklist for releasing Katisha on the **Google Play Store** and the **Apple App Store**.
This documents every item that could NOT be completed automatically from code and needs **developer/owner action**.

---

## 1. Identity (DONE in code)

| Item | Old | New |
|------|-----|-----|
| Android `applicationId` / `namespace` | `rw.vuduka.vuduka` | `rw.katisha.today` |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` | `rw.vuduka.vuduka` | `rw.katisha.today` |
| Android `MainActivity` package | `rw.vuduka.vuduka` | `rw.katisha.today` |
| App display name | Katisha | Katisha (unchanged) |

> ⚠️ Bundle/application IDs are **immutable after first store submission**. We changed it now, before any submission — this is the correct time.
> The Firebase `ios/Runner/GoogleService-Info.plist` still references the old bundle ID and an old "vuduka-transport" project. Firebase is **not currently wired up** (deps commented out in `pubspec.yaml`, no `FirebaseApp.configure`, messaging service removed). When you enable push via FCM, download a **fresh** `GoogleService-Info.plist` / `google-services.json` generated for the new `rw.katisha.today` bundle ID.

---

## 2. Android Release Signing (DONE)

- Generated keystore: `android/app/katisha-release.jks`
- Config: `android/key.properties` (loaded by `android/app/build.gradle.kts`)
- Both files are in `.gitignore` (never commit them).
- Verified: `app-release.apk` signs with **Katisha production cert** (SHA-256 `4CB8F827…`), no longer debug keys.

### 🔐 CRITICAL — Back this up now
If you lose this keystore and password you **cannot update** the app on Google Play ever again (new key = new app identity). Store in at least 2 secure places (e.g. password manager + encrypted backup):

```
Keystore file : android/app/katisha-release.jks
Store/Key pass: 4rXwkht3stTv2rkofzZJIqvelLmM4l6r
Key alias     : katisha
SHA-256       : 4CB8F827076384F68EDDDBEBC57F0485321B6F06DD7A961891A09F9FC41A052C
```

> ⚠️ The password above appears in this doc for reference — remove it and rely on your private backup after you've recorded it. The values are already excluded from git.

### App Bundle (required by Play)
Play Store **requires an Android App Bundle (`.aab`)**, not an APK:
```bash
flutter build appbundle --release
```
For a smaller per-device download, split ABI in Play Console is automatic with AAB.

---

## 3. Permissions / Privacy — cleaned up in code

### Android (removed)
- `CAMERA` (was "for future QR scanning" — no scanner feature exists)
- `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN` (printing uses the system print framework, not Bluetooth)
- `USE_EXACT_ALARM`, `SCHEDULE_EXACT_ALARM` (notifications use `inexactAllowWhileIdle`)
- Removed broken `MyFirebaseMessagingService` manifest entry (class didn't exist, Firebase not a dependency) — was a latent crash + review risk
- `usesCleartextTraffic="true"` removed; `network_security_config.xml` now blocks cleartext

### iOS (removed)
- `NSCameraUsageDescription` (no camera feature)
- `NSBluetoothAlwaysUsageDescription` (AirPrint needs no Bluetooth permission)
- `NSLocalNetworkUsageDescription` + `NSBonjourServices` (not needed; AirPrint handled by the system)
- `NSAllowsArbitraryLoads` changed `true` → `false` (was an App Store rejection risk; now HTTPS-only + local networking allowed for dev)

### Kept (justified)
- `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED` (journey alerts / scheduled notifications)
- `INTERNET`
- iOS `UIBackgroundModes`: `remote-notification`, `fetch`

---

## 4. Google Play Console — actions required (owner)

1. **Create a Google Play developer account** (one-time $25) and a new app titled **Katisha**.
2. **Set up app signing** in Play Console → *App signing*: choose "Let Google manage your signing key" and upload the **Upload key** derived from `katisha-release.jks` (same key can be the upload key). Keep the keystore safe (see §2).
3. **Upload** `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`.
4. **Content ratings** questionnaire.
5. **Target audience**: e.g. 13+; state the app does not target children.
6. **Data safety form** — declare what the app collects/transmits (see §6).
7. **Privacy policy URL** — required if you declare personal-data collection. Host one (no-cookie) at e.g. `https://katisha.today/privacy`.
8. **Ads**: none.
9. **Store listing** — see §5 (ASO).

---

## 5. ASO (App Store Optimization) — copy ready to paste

### App name (display)
- **Google Play**: `Katisha – Bus Ticket Booking`
- **iOS Search**: search-title should be ≤ 30 chars → `Katisha Bus Tickets`

### Short description (Google Play, ≤ 80 chars)
`Book bus tickets across East Africa securely with Katisha. Quick payments and instant digital tickets.`

### Full description (Google Play)
```
Katisha is the fastest way to book bus tickets across East Africa — directly from your phone.

Features:
• Search and compare routes and departures in seconds
• Secure mobile money and card payments
• Instant digital tickets with QR code for easy boarding
• Live journey alerts before departure
• View and manage all your trips in one place
• Available in English, French, Kinyarwanda and Swahili

Travel smarter with Katisha. Download free and book your next journey today.
```

### iOS subtitle / keywords (≤ 100 chars)
```
Subtitle: Book bus tickets in East Africa securely
Keywords: bus, ticket, travel, booking, rwanda, kenya, uganda, katisha, transport, journey
```

### Category
- Google Play: **Travel & Local**
- iOS: **Travel** (primary)

### Suggested screenshots / previews
1. Home + route search
2. Route results with prices & times
3. Payment/checkout (Momo / card)
4. Digital ticket w/ QR
5. My Trips list
6. Journey alert notification

Capture on an iPhone (6.7") for iOS (3 sizes) and a Pixel/Android phone for Play.

### Short promotional text (Play, optional, rotates)
`New routes added weekly. Book Kampala, Nairobi, Kigali and more today.`

---

## 6. Data Safety / Privacy Labels

App collects (verify against actual code before submitting):
- **Personal info**: name, phone number (login/booking)
- **Financial info**: payment identifier used at checkout via Momo / card processor — the server issues tickets, Katisha does **not** store full card numbers
- **Location**: not required
- **Usage/Diagnostics**: not required by default
- **Device ID**: FCM token for push (when Firebase is enabled)

Google Play **Data safety** declarations and iOS **Privacy nutrition labels** should reflect only what is actually collected. Confirm each field against the live behaviour before finalizing.

### Push notifications
Local notifications work today. Remote push (FCM/APNs) is **not yet enabled** (Firebase deps commented out). If you enable it: add `firebase_core` + `firebase_messaging`, add the AppDelegate FCM wiring + background handler, register the new `GoogleService-Info.plist`/`google-services.json` (with `rw.katisha.today`), and re-add a real `FirebaseMessagingService`.

---

## 7. Apple App Store — actions required (owner)

1. **Apple Developer Program** membership ($99/yr).
2. **App ID** `rw.katisha.today` — enable *Push Notifications* capability if adding FCM later.
3. **Bundle identifier** in Xcode = `rw.katisha.today` (already set).
4. **Provisioning / signing**: you need an Apple Distribution certificate + provisioning profile (team member with the Apple account must run this in Xcode). This is not something reproducible without the account.
5. `flutter build ipa --release` then **App Store Connect** upload (Xcode Organizer / `xcrun altool`).
6. **App Store Connect**: app name, subtitle, keywords (§5), privacy policy URL, App Privacy labels (§6).
7. **App Review notes**: mention testing is available with internet + on-display screenshots; the app needs an active network to reach `https://api.katisha.today`.
8. Deployment target is currently `IPHONEOS_DEPLOYMENT_TARGET = 14.0` — acceptable; raise if your build tooling requires it.

---

## 8. Performance / size (code + build)

- Release signing fixed (no more debug keys).
- Tokens now stored in **secure storage** (`flutter_secure_storage`), not plaintext SharedPreferences.
- API timeouts reduced (45s/60s → 10s/20s) for faster failure feedback.
- User-facing network/timeout error messages (removed dev "same WiFi" text).
- Remaining: `app-release.apk` is ~60 MB (universal APK). Use **App Bundle** + ABI splitting to trim per-device size:
```bash
flutter build appbundle --release --split-per-abi
```
- Tree-shake icons already active (build log shows Material/Cupertino icons shrunk).

---

## 9. Release checklist (final)

- [ ] Back up keystore + password (§2)
- [ ] Play developer account + app "Katisha"
- [ ] Shield/upload key in Play Console (from `katisha-release.jks`)
- [ ] Upload `app-release.aab`
- [ ] Content rating + target audience
- [ ] Data safety form (§6)
- [ ] Privacy policy URL hosted
- [ ] Store listing copy + screenshots (§5)
- [ ] Apple Developer account + App ID `rw.katisha.today`
- [ ] Distribution certificate + provisioning profile
- [ ] `flutter build ipa` + upload to App Store Connect
- [ ] App Privacy labels + privacy policy (§6)
- [ ] Final QA on a real device (both platforms)
