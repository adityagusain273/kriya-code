# B Code — Play Console Data Safety

> Authoritative as of targetSdk 35 hardening. Every claim below is backed by a
> code path; if you change the network or storage behaviour of the app, update
> this file in the same commit. An inaccurate Data Safety form is a policy
> violation, not a documentation nit.

## Summary of actual network behaviour

B Code makes **exactly two** categories of outbound request, both to GitHub, both
only after the user explicitly connects their account:

| Destination | Purpose | Transport |
|---|---|---|
| `github.com/login/device/code`, `github.com/login/oauth/access_token` | OAuth device-flow token exchange | HTTPS, TLS certificate pinning |
| `api.github.com` | List repos / branches / commits, clone, push, pull | HTTPS, TLS certificate pinning |

There is no analytics SDK, no crash-reporting SDK, no advertising SDK, no
Firebase, and no telemetry endpoint. `android/app/google-services.json` is not
present in the repository and the `google-services` / `crashlytics` Gradle
plugins are declared with `apply false` and never applied.

The app makes **no** request at app start. The only non-GitHub network call is a
platform reachability check that resolves a hostname via the OS resolver.

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
- Trust anchors: system certificate authorities only. A user-installed proxy CA
  is not trusted, so a TLS interception proxy cannot silently read traffic.
- Certificate pinning: `api.github.com` and `github.com` are pinned to the
  GitHub leaf and Sectigo intermediate SPKI hashes, verified during the TLS
  handshake on the same connection that carries the request.
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