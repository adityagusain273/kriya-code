# B Code — Privacy Policy (placeholder)

_Last updated: 2026-08-24 · App version 0.1.0_

**B Code** (`com.bcode.editor`) is a code editor. This placeholder summarizes current and
planned data handling and must be reviewed by counsel before Play Store submission.

## Data we store (on your device only)

- **Your code files** — stored in the app's private storage. Never uploaded by us.
- **GitHub OAuth token** — if you connect GitHub, the token is stored in the Android
  Keystore-backed secure storage (`flutter_secure_storage`). It is sent only to
  `api.github.com` and `github.com`. You can revoke it anytime via *Settings → Sign out*
  or on github.com.
- **App settings** — font size, theme, execution preference (local preferences storage).

## Third-party services used at your request

| Service | When | What is sent |
|---|---|---|
| **Piston API** (emkc.org) | When you press Run and no local runtime is installed, or cloud execution is preferred | The contents of the file being run, plus optional stdin |
| **GitHub API** | When you use the GitHub features | Your OAuth token; repo/file metadata you browse |

We do not collect analytics, ads identifiers, crash logs, or contacts. No account is
created inside B Code.

## Children's privacy

B Code does not knowingly collect personal data from anyone, including children under 13.

## Contact

`support@bcode.example` *(replace with a real address before submission)*

## Changes

Material changes to this policy will be reflected in app release notes and this document.
