# B Code — Play Console Data Safety

Every answer below was checked against the code in this tree (targetSdk 36,
version 1.0.0+10). If you change network or storage behaviour, update this file
in the same commit: an inaccurate Data Safety form is a policy violation, not a
documentation nit.

## Does the app collect or share user data? — **No**

B Code has no backend and no SDK that phones home. The developer receives
nothing from the app: no analytics, no crash upload, no account database.

Data does leave the device, but only as a direct consequence of an action the
user took, and only to the service that action targets:

| Data | Destination | When | Encryption in transit |
|---|---|---|---|
| GitHub OAuth token | `github.com`, `api.github.com` | Device-flow sign-in, then every GitHub API call | TLS, issuing-CA pinned |
| Repository contents | `github.com` (libgit2 clone/push/fetch) | Clone, push, pull, commit | TLS (system trust store) |
| Nothing else | — | — | — |

Files, terminal output, run output and crash logs are never uploaded. There is
no telemetry endpoint in the app or in any dependency.

## Network destinations — the complete list

Five HTTPS hosts, each reachable only through a user action:

| Host | Purpose | Trigger | Pinning |
|---|---|---|---|
| `github.com` | OAuth device flow (code + token exchange), verification page | *GitHub → Continue with GitHub* | `lib/core/pinned_http.dart` (issuing CA) |
| `api.github.com` | List repos/branches/commits, revoke token | Sign-in, repo browsing, sign-out | same |
| `github.com` via libgit2 | clone / push / fetch | *Clone to Workspace*, *Push*, *Pull* | system CAs (git2dart's own TLS stack) |
| `packages.termux.dev` | Runtime `.deb` packages + SHA-256 index | *Runtimes → Download* | same (`PinnedHttpClient`) |
| `raw.githubusercontent.com` | Official extension index (`extensions-index/index.json`) | Opening *Extensions → Community* | system CAs |
| `<any https host the user types>` | Third-party extension index or `.bcext` package | User adds a source or installs from URL | none by design (user's choice of host) |

Two more are local only and never leave the device:

- `127.0.0.1` — the preview and live-reload servers bind loopback with an
  ephemeral port and a per-session token
  (`lib/editor/preview/live_server.dart`, `preview_server.dart`).
- `127.0.0.1` — the terminal's own PTY, and the `ServerMonitor` port probe.

`NetworkHelper.isOnline` resolves `github.com` for a reachability check; it
sends no request body and no identifier.

## Per-question answers (Play form)

**Does your app collect or share any of the required user data types?**
No.

**Is all of the collected user data encrypted in transit?**
Yes — but the honest scope is: everything the app itself sends over HTTPS is
TLS, and the trust-relevant channels (GitHub OAuth/API, the Termux package
host) additionally pin the issuing CA. Two exceptions worth knowing, both
outside the app's control:

- `libgit2` (clone/push/fetch) uses its own TLS stack and the system trust
  store. It is encrypted, but not pinned.
- Extension sources and `.bcext` downloads use plain `http.Client` with default
  validation, because the host is whatever the user typed.

**Do you provide a way for users to request that their data is deleted?**
Yes, and it is mostly moot because nothing is held server-side. *GitHub → Sign
out* revokes the OAuth grant at GitHub (`GitHubApiClient.revokeToken`) and
deletes the local token. *Settings → Report a Bug → clear log* deletes the
local crash log. Uninstalling removes everything.

**Does the app collect data from children?**
No, and it is not directed at children.

## What is stored on the device

| Data | Location | Lifetime |
|---|---|---|
| Code files | `app_flutter/projects` (app-private) | Until the user deletes them |
| GitHub OAuth token | `EncryptedSharedPreferences` (AES-256-GCM, key in Android Keystore) | Until sign-out |
| Crash log | `app_flutter/crash.log`, capped 100 KB with rotation | Until cleared or uninstalled |
| Settings, extension sources | `shared_prefs/FlutterSharedPreferences.xml` | Until uninstalled |
| Downloaded runtimes | `files/runtimes/<id>` | Until removed in *Runtimes* |

`android:allowBackup="false"`, `fullBackupContent="false"`, and
`dataExtractionRules` that exclude every domain, so none of the above leaves the
device through Google backup or device-to-device transfer.

## Crash log — local only

`lib/core/crash_reporter.dart` writes exception type, message and stack to
`app_flutter/crash.log`. It is never uploaded by the app.

- The *Settings → Report a Bug* dialog builds a `mailto:` draft containing the
  device model, Android version, app version and the last 4 KB of that log.
  Nothing is sent until the user presses send in their own mail app.
- Redaction before writing: `ghp_`/`gho_`/`ghs_`/`ghu_`/`ghr_` tokens,
  `github_pat_` tokens, `Bearer …`, `Basic …`, JWTs, `client_secret=` and
  `access_token=` (see `test/crash_reporter_redaction_test.dart`).
- *Settings → Write crash log* turns writing off. It previously did nothing
  (`setCollectionEnabled` was an empty method); it now actually gates `_log`.
  Turning it off leaves the existing file untouched and readable.

## Permissions

| Permission | Why |
|---|---|
| `INTERNET` | GitHub, git transport, runtime downloads, extension index, live preview |
| `com.termux.permission.RUN_COMMAND` | Only if the user installs Termux and opts in; Termux enforces its own grant |

No storage, camera, microphone, contacts, location, phone or notification
permission. There is no `READ_MEDIA_IMAGES`; the bug-report attachment picker
uses the Android photo picker, which grants a single chosen image and needs no
permission. `MANAGE_EXTERNAL_STORAGE` was removed deliberately.

No advertising ID is requested and no ad SDK is present. There are no
`play-services-ads`, Firebase or Crashlytics dependencies: the
`google-services` and `crashlytics` Gradle plugins were dropped from
`android/settings.gradle.kts`, there is no `google-services.json`, and the
`firebase_crashlytics_collection_enabled` manifest meta-data was removed.

## Ads

**Does the app contain ads?** No. There is no ad SDK and no ad unit.

## App access

All functionality is available without signing in. GitHub features require a
GitHub account; the code runs offline with no account at all. Play Console
*App access* answer: **All functionality is available without special access**,
with a note that GitHub sign-in uses GitHub's own device flow.

## Content rating questionnaire

Category: **Tools / Developer tools** (not a game).

| Question | Answer |
|---|---|
| Violence (cartoon, realistic, sexual, references to) | None |
| Sexual content (suggestive, nudity, explicit) | None |
| Profanity or crude humour | None |
| Drugs, alcohol, tobacco, gambling | None |
| Horror, fear, scary content | None |
| User-generated content shared with other users | No. There is no feed, chat, comment or public profile. The only "sharing" is a git push to the user's own repository, under their own credentials. |
| User interaction between users | No |
| Sharing of user-generated content | No (see above) |
| Location, personal data, or ID sharing | No |
| In-app purchases | No. *Support Developer* shows a static UPI QR code — there is no billing flow and nothing is unlocked. |
| Unrestricted web access / in-app browser | No. The preview WebView is confined to `127.0.0.1` (see below). |
| Ads | No |

The one item a reviewer will notice is arbitrary code execution: the terminal
and the Run button execute code the user wrote or downloaded. That is the
product, not incidental content — it does not change any answer above, but it
is the reason the listing should keep saying "developer tools" rather than
"learn to code". No rating authority asks about code execution directly, and
none of the answers above should be softened to hide it.

Expected result: **Rated for 3+ / PEGI 3 / ESRB EVERYONE** in every territory.

## WebView hardening (why "unrestricted web access" is No)

`lib/editor/preview/preview_page.dart` blocks `file`, `content`, `data`,
`intent`, `javascript`, `ftp`, `ws` and `wss` navigation, allows only the
loopback origin, and disables `allowFileAccess` / `allowContentAccess`.

## Financial features

- In-app purchases: none.
- Subscriptions: none.
- Real-money gambling, loot boxes, contests: none.
- The *Support Developer* dialog shows a UPI QR image and a "Scan with any UPI
  app" line. No payment SDK is bundled, no transaction is initiated by the app,
  and no feature is gated behind it. If Play's reviewer treats this as a
  payment feature, the safe answer is "No — external donation link only, not
  processed by the app"; do not enable Play's payments declaration for it.

## Target audience and content

- Target age groups: **18+ only** is the honest minimum given unrestricted
  terminal access and the ability to clone and run arbitrary code from the
  internet. Do not select any under-18 group: it would pull the app into the
  Families policy and require ad and data-safety attestations the app is not
  built for.
- Appeals to children: no.
- News / health / finance / government / regulated category: none.