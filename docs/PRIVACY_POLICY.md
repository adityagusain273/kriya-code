# B Code — Privacy Policy

_Last updated: 2026-10-03 · App version 1.0.0_

**B Code** (`com.bcode.editor`) is a mobile code editor. It executes your code
locally on your device and, at your request, synchronizes with your GitHub
account.

## Data we store (on your device only)

- **Your code files** — stored in the app's private storage. Never uploaded by us.
- **GitHub OAuth token** — if you connect GitHub, the token is stored in
  EncryptedSharedPreferences with its key held in the Android Keystore. It is
  sent only to `api.github.com` and `github.com`. You can revoke it anytime via
  *GitHub → Sign out* (which also revokes the grant on github.com) or directly at
  github.com/settings/tokens.
- **Crash log** — stack traces and errors are written to a local file. They are
  never transmitted anywhere. Redaction of bearer tokens and API secrets is
  applied before they are written.
- **App settings** — font size, theme, autosave, and extension-install flags
  (local preferences storage).

## Data sent over the network

Code execution is local. There is **no cloud execution** in this version:

- **GitHub API** (`api.github.com`, `github.com`) — only when you use the GitHub
  features. The app sends your OAuth token and requests repo/file metadata you
  browse. OAuth uses the Device Flow; the token is created only after you
  authorize it on github.com.
- **Termux package repository** (`packages.termux.dev`, HTTPS with pinned
  integrity checks) — only when you choose to download a runtime. The app
  verifies the SHA-256 of every package against the published index before
  installing it.

## What we do not do

- We do not collect analytics or advertising identifiers.
- We do not transmit crash logs, files, or terminal output.
- We do not request any permission beyond `INTERNET` and, optionally, Termux's
  `RUN_COMMAND` (only used if you install and authorize Termux).
- We do not access shared storage. The workspace is app-private.

## Children's privacy

B Code does not knowingly collect personal data from anyone, including children under 13.

## Changes

Material changes to this policy will be reflected in app release notes and this document.

The authoritative copy served at the store listing URL is
`privacy_policy.html`. Contact:
[adityagusain273@gmail.com](mailto:adityagusain273@gmail.com)
