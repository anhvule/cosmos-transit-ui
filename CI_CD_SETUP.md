# CI/CD setup — CosmicTransit

CosmicTransit is **iOS-only** (there's no `android/` directory), so there's a
single GitHub Actions workflow that ships the app to TestFlight and the App Store:

| Workflow | Lanes | Target |
|---|---|---|
| `.github/workflows/ios-testflight.yml` | `beta` (default), `release` | TestFlight → App Store |

The workflow is **manually triggered** (`workflow_dispatch`) to start. Once the
first runs are green you can flip on the `push: branches: [main]` block at the top
of the workflow to ship automatically on every merge to `main`.

Unlike the panda app, the Flutter project lives at the **repo root** (not under
`./app`), and there's a single `Runner` target with **no widget/app extension** —
so only one distribution certificate and one App Store provisioning profile are
needed.

---

## 1. One-time prerequisites

### Apple side (Developer Program membership required)

You need **three things** in App Store Connect:

1. **App registered** in App Store Connect with bundle id `com.anhvule.cosmostransit`.
   Go to appstoreconnect.apple.com → Apps → "+" → New App. Pick iOS, paste the
   bundle id, give it a name ("CosmicTransit"), SKU = any unique string, primary
   language English.

2. **App Store Connect API key** — for non-interactive uploads.
   - App Store Connect → Users and Access → **Keys** (Integrations) tab
   - Click **"+"**, name it "GitHub CI", role: **App Manager** (or Admin if your team is small)
   - Download the `.p8` file **immediately** (you can only download once)
   - Note the **Key ID** (10-char string) and **Issuer ID** (uuid at top of the page)

3. **Apple Team ID** — find it at developer.apple.com/account → Membership. 10 chars.

---

## 2. GitHub secrets to set

Repo → Settings → Secrets and variables → Actions → **New repository secret** for each:

| Secret name | What it is |
|---|---|
| `APPLE_TEAM_ID` | Your 10-char team id |
| `APP_STORE_CONNECT_KEY_ID` | 10-char key id from the .p8 file's metadata |
| `APP_STORE_CONNECT_ISSUER_ID` | UUID from the Keys page |
| `APP_STORE_CONNECT_PRIVATE_KEY` | The .p8 file contents as **raw PEM text** (`cat AuthKey_XXX.p8 \| pbcopy` — include the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines) |
| `IOS_DIST_CERTIFICATE_BASE64` | Distribution certificate exported from Keychain as .p12, **base64-encoded** |
| `IOS_DIST_CERTIFICATE_PASSWORD` | Password you set when exporting the .p12 |
| `IOS_PROVISIONING_PROFILE_BASE64` | App Store provisioning profile (.mobileprovision) for the `Runner` target (`com.anhvule.cosmostransit`), **base64-encoded** |
| `IOS_PROVISIONING_PROFILE_NAME` | Exact profile name as shown in developer.apple.com (e.g. "CosmicTransit App Store CI") |

### How to generate the cert + profile secrets

The `cert` / `sigh` actions can create these via API key, but storing a known cert
+ profile as secrets is faster and avoids CI keychain ACL issues. One-time setup:

1. **Open the Xcode project locally** (`open ios/Runner.xcworkspace`), select the
   Runner target → Signing & Capabilities → check "Automatically manage signing"
   and pick your team. Hit Product → Archive once; this triggers Xcode to create a
   distribution certificate if you don't already have one.

2. **Export the distribution cert as .p12** — open Keychain Access → My Certificates
   → find `Apple Distribution: <your team>` → right-click → Export → save as
   `distribution.p12`, set a password. Encode:
   ```bash
   base64 -i distribution.p12 | pbcopy
   ```
   Paste into `IOS_DIST_CERTIFICATE_BASE64`. Put the password into `IOS_DIST_CERTIFICATE_PASSWORD`.

3. **Create + download an App Store provisioning profile** — go to
   developer.apple.com/account → Certificates, Identifiers & Profiles → Profiles →
   "+" → App Store → pick the `com.anhvule.cosmostransit` App ID → pick your
   distribution certificate → name it (e.g. `CosmicTransit App Store CI`) →
   download the `.mobileprovision`. Encode:
   ```bash
   base64 -i CosmicTransit_App_Store_CI.mobileprovision | pbcopy
   ```
   Paste into `IOS_PROVISIONING_PROFILE_BASE64`. Put the exact profile name into
   `IOS_PROVISIONING_PROFILE_NAME` (must match what you typed in the portal).

---

## 3. First run

### TestFlight
1. Manually upload **one** build of the app via Xcode Organizer (Product → Archive
   → Distribute App). This is needed because App Store Connect rejects API uploads
   until the app's first build exists.
2. Go to GitHub → Actions → "iOS — TestFlight" → "Run workflow" → leave `beta`
   selected → run.
3. ~15-20 min later, the build appears in TestFlight. Add internal testers in App
   Store Connect, install via the TestFlight app on your phone.

---

## 4. Day-to-day

- **TestFlight build**: manual trigger of `iOS — TestFlight` (lane `beta`). Or
  uncomment the `push: branches: [main]` trigger to ship automatically on every
  merge to main.
- **App Store submission**: manual trigger with lane `release` after you're happy
  with the latest TestFlight build. The workflow uploads the binary; metadata,
  screenshots, and the submit-for-review click stay in the App Store Connect UI.
  Apple review = 1–3 days.
- **Versioning is automatic**: build number = `${{ github.run_number }}`, strictly
  increasing per repo, so TestFlight never rejects a duplicate.

---

## 5. Local Fastlane runs (optional)

Useful for debugging signing without burning a CI minute. You must export the
same env vars the workflow sets (`APPLE_TEAM_ID`, the three `APP_STORE_CONNECT_*`
values, and `IOS_PROVISIONING_PROFILE_NAME`) and have the distribution cert +
profile installed in your local keychain / Provisioning Profiles folder first:

```bash
cd ios
bundle install
bundle exec fastlane beta
```

---

## 6. Troubleshooting

| Symptom | Fix |
|---|---|
| `No provider was found.` on iOS install | Open Xcode > Settings > Accounts, sign in, click "Download Manual Profiles". Or run `flutter clean && cd ios && pod install`. |
| `Invalid bundle id` on TestFlight upload | The app isn't registered in App Store Connect. Create it manually first with bundle id `com.anhvule.cosmostransit`. |
| iOS lane fails at `gym`/`build_app` with provisioning errors | Confirm `IOS_PROVISIONING_PROFILE_NAME` matches the name *inside* the `.mobileprovision` exactly, and that the profile's App ID is `com.anhvule.cosmostransit`. Regenerate/re-download the profile if the App ID's capabilities changed after it was created. |
| `security find-identity` shows no identities in CI | The `.p12` in `IOS_DIST_CERTIFICATE_BASE64` doesn't contain both the cert *and* its private key. Re-export from Keychain via **My Certificates** (not the Certificates category), which bundles the key. |
| Upload rejected: build number already used | Shouldn't happen — build number is the CI run number. If you ran a manual Xcode upload with a higher number, bump past it once. |
