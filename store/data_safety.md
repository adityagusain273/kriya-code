# B Code — Play Console Data Safety

> Authoritative as of targetSdk 35 hardening. Every claim below is backed by a
> code path; if you change the network or storage behaviour of the app, update
> this file in the same commit. An inaccurate Data Safety form is a policy
> violation, not a documentation nit.

## Summary of actual network behaviour

B Code makes **exactly three** categories of outbound HTTPS request, all pinned:

| Destination | Purpose | Transport |
|---|---|---|
| `github.com/login/device/code`, `github.com/login/oauth/access_token` | OAuth device-flow token exchange | HTTPS, TLS certificate pinning |
| `api.github.com` | List repos / branches / commits, clone, push, pull | HTTPS, TLS certificate pinning |
| `packages.termux.dev` | Optional language-runtime downloads, user-initiated | HTTPS, TLS certificate pinning; every downloaded package is also verified against the published SHA-256 index (`lib/core/runtime_download_service.dart`) |

There is no analytics SDK, no crash-reporting SDK, no advertising SDK, no
Firebase, and no telemetry endpoint. `android/app/google-services.json` is not
present in the repository and the `google-services` / `crashlytics` Gradle
plugins are declared with `apply false` and never applied.

## Data collection declarations

### Crash logs — collected, NOT transmitted

`lib/core/crash_reporter.dart` writes stack traces and error text to a local
file at `app_flutter/crash.log` (capped at 100 KB with rotation). It is
**never** uploaded by the app.

- Data: exception type, message, stack trace, and a user-supplied description.
- Destination: a file in the app's private storage, on the device only.
- Automatically readable by the app; only leaves the device if the user opens
  Settings → report a bug and sends the pre-filled email themselves.
- Redaction: bearer tokens, `ghp_`/`gho_` prefixes, `client_secret=`, and
  `access_token=` are scrubbed from log lines before they are written.

### GitHub account — collected, transmitted to GitHub

Only if the user connects a GitHub account.

- Data: an OAuth access token with the scopes `repo,read:user`, plus the API
  calls that token authorises.
- Destination: `api.github.com` and `github.com`.
- Purpose: cloning, committing, pushing, and pulling the user's repositories.
- Opt-out: *Settings → Sign out* revokes the token via GitHub's token API and
  deletes the local copy.

### Files — collected, NOT transmitted

Projects are stored in app-private storage (`app_flutter/projects`). B Code
requests no storage permission and does not read shared storage. Files are never
uploaded anywhere except as part of a git push the user explicitly triggers.

## Security

- Network: cleartext traffic is disabled globally
  (`android:usesCleartextTraffic="false"`). The only cleartext exception is
  `127.0.0.1` / `localhost`, required by the built-in live-preview server.
- Trust anchors: the three pinned hosts (GitHub OAuth/API and the Termux
  package host) are validated **only** against the bundled issuing CA described
  below, not the system trust store. A user-installed proxy CA is therefore not
  trusted for them. The libgit2 transport used by clone/push/pull validates
  against the system CAs.
- Certificate pinning: `api.github.com`, `github.com`, and `packages.termux.dev`
  are trusted only to a pinned issuing CA (Sectigo Public Server Authentication
  Root E46 for GitHub, ISRG Root YR for Termux), verified during the TLS
  handshake on the same connection that carries the request
  (`lib/core/pinned_http.dart`). Pinning the CA rather than the leaf survives
  GitHub's ~90-day and Let's Encrypt's ~60-day certificate renewals; `dart run
  tool/check_cert_pins.dart` fails CI if a host moves to another authority.
  Git traffic from `git2dart`/libgit2 uses its own TLS stack and is **not**
  covered by these pins.
- Secrets at rest: the GitHub token is stored in `EncryptedSharedPreferences`
  (AES-256-GCM) with the key held in the Android Keystore.
- Backup: `android:allowBackup="false"`, `android:fullBackupContent="false"`, and
  `dataExtractionRules` that exclude every domain. The token store, the Keystore
  material, the crash log, and downloaded runtimes never leave the device via
  Google backup or device-to-device transfer.
- Code execution: user code and downloaded language runtimes execute as the app
  UID inside the app's private directory. B Code requests no permission to run
  another app's code, with the sole exception of the user's explicit opt-in to
  Termux's `RUN_COMMAND` permission for user-initiated commands.

## Permissions requested

| Permission | Why |
|---|---|
| `INTERNET` | GitHub API, git transport, runtime downloads, live preview |
| `com.termux.permission.RUN_COMMAND` | Only used if the user opts into Termux as an execution target. Termux enforces its own grant. |

No storage, camera, microphone, contacts, location, or phone permission is
requested. `MANAGE_EXTERNAL_STORAGE` and the legacy
`READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` permissions have been
removed.

## Play Console answers

- Does the app collect or share any of the required user data types?
  **Yes — Credentials** (GitHub OAuth token, user-initiated, linked to an
  account the user signs into).
- Is all of the collected user data encrypted in transit? **Yes.**
- Do you provide a way for users to request that their data is deleted?
  **Yes** — *Settings → Sign out* revokes and deletes the stored token.
- Does the app collect data from children? **No** — the app is not directed at
  children.
- Is this app a "news" app, "health", "finance", or other regulated category?
  **No.**
- Does the app contain ads? **No.**
- Is the app an "app-accessibility" tool or does it declare itself as one?
  **No.**

## Content rating

- Category: Developer Tools
- Violence / sexual content / language / controlled substances: None
- User interaction: the user writes and runs their own code locally. Nothing is
  published or shared publicly unless the user pushes to their own repository.