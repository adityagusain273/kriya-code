# B Code vs Acode — and what to build next

Snapshot: November 2026. B Code `1.0.0+10`; Acode `v1.13.5` (September 2026),
marketplace data from `acode.app/api/plugins`.

Acode is the reference point, not the target. It is a mature Cordova/WebView
editor with a real plugin economy. B Code is a native Flutter editor with
first-party execution and a much smaller surface. The strategy should be to win
on the things Acode cannot easily copy — integrated run/build, safety, native
performance — not to out-count its plugin catalogue.

## Scoreboard

| Capability | B Code | Acode | Edge |
|---|---|---|---|
| On-device run: Python, C, C++, Java, JS | First-party Run button, on-demand runtimes, SHA-256 verified | Via plugins (Python, Code Runner) or Termux | **B Code** |
| GitHub | First-party: Device Flow, clone, commit, push, diff, history | Community plugin (≈202k downloads), Git SCM plugin | **B Code** |
| Terminal | PTY panel; Termux bash or bundled bash runtime | Built-in Alpine terminal; `apk` package manager | Acode (packages) |
| Git branch/stash/merge | Fast-forward pull; clone/commit/push | Plugin-dependent | Acode (via plugins) |
| Extension ecosystem | New: declarative `.bcext` packages, static indexes | 100+ marketplace plugins, paid plugins, verified authors | **Acode** |
| Extension capability | Languages, snippets, themes. No code execution | Full JS API: UI, commands, editor, files, terminal, LSP, webview, secrets, permissions | **Acode** |
| Extension distribution | File, HTTPS URL, any static JSON index. No account, no server | Central marketplace with accounts, reviews, purchases | Acode (reach), **B Code** (cost/control) |
| Language support | 10 packs (Python, Java, C, C++, JS, TS, HTML, CSS, JSON, MD) | CodeMirror modes + language plugins, effectively broader | **Acode** |
| Autocomplete / IDE intelligence | Keyword and symbol index, no language server | CodeMirror 6 LSP client; plugins add real LSP servers | **Acode** |
| Remote editing | — | SFTP/FTP/SSH plugins (paid) | **Acode** |
| Themes | 6 bundled + declarative extension themes | Large theme marketplace | Acode |
| Debugger | — | Python step-debugging via paid plugin | Acode (plugin) |
| Live preview | Built-in server with reload | Live Server plugin (≈62k downloads) | **B Code** |
| Global search / quick open / palette / snippets | Built in | Built in + plugins | Parity |
| Native UI | Flutter, Material 3, no WebView in the editor | Cordova WebView + CodeMirror | **B Code** (architecture) |
| iOS / desktop path | Flutter targets exist; Android first | Android-first Cordova | B Code (potential) |
| Safety of extensions | Declarative data only; cannot run code | Arbitrary JS with native bridges; they added tokens/permissions, still a large surface | **B Code** |
| Cost to operate | Static indexes, no backend | Marketplace backend, payments, review | **B Code** |
| Community / distribution | New, Play-only (planned) | Play + F-Droid, Telegram/Discord, years of reviews | **Acode** |

"Edge" means who is ahead today, not who is better positioned.

## Where Acode genuinely beats us

1. **Ecosystem and network effect.** 100+ plugins, top free plugins at 200k–420k
   downloads, paid plugins at ₹49–85, verified authors, reviews. Developers go
   where users are; users go where plugins are.
2. **Plugin API depth.** Acode plugins can add commands, sidebars, editor
   components, file handlers, terminal integrations, LSP clients and webviews.
   Our packages can only add languages, snippets and themes.
3. **Real language intelligence.** Acode ships a CodeMirror LSP client and
   plugins provide language servers. We have keyword/symbol completion, which is
   a different class of feature.
4. **Language breadth.** Ten bundled packs is a small number on a store listing
   where "supports 100+ languages" is a checkbox.
5. **Remote editing.** SFTP/FTP/SSH is a core workflow for the phone-as-a-thin-
   client audience, and we have nothing.
6. **Themes and customization.** A marketplace of themes and icon packs is cheap
   engagement that we only just started supporting.
7. **Maturity.** Acode has years of device coverage, translations, review
   history, and a community that answers questions. A 1.0 launch cannot fake
   that.
8. **Paid-plugin economy.** Acode lets developers earn, which attracts
   developers. We have no monetization path for extension authors yet.

## Where we beat Acode

1. **Execution is the product, not a plugin.** A Run button that installs a
   verified CPython/OpenJDK/clang/Node runtime, builds when needed, and streams
   output is a stronger promise than "install a plugin and hope". This is the
   single clearest reason to choose B Code.
2. **GitHub is first-party.** Device Flow, clone, commit, push and diff without
   a third-party plugin, with TLS pinning and token storage designed in.
3. **Native rendering.** No Cordova/WebView in the editing path means a lower
   ceiling on input latency and battery cost. Do not claim a benchmark until one
   is measured, but the architecture is on our side.
4. **Extensions cannot execute code.** A malicious `.bcext` can only add
   highlighting, snippets or colours. Acode's model is more powerful and
   correspondingly more dangerous; a bad plugin runs with the editor's access.
5. **Zero-cost, decentralized distribution.** Any developer can publish an index
   on GitHub Pages in minutes. No account, no review queue, no server bill, no
   platform tax. Private extensions are just unlisted links.
6. **Cross-platform headroom.** The same Flutter code can reach desktop and iOS.
   Acode is Android-first by construction.
7. **A clean slate.** No legacy Ace/CodeMirror split, no Cordova plugin
   compatibility burden, no paid tiers to defend.

## Extension strategy

The new package system is deliberately narrower than Acode's. That is the right
trade for launch:

- **Now:** declarative languages, snippets, themes; install from file, URL or a
  static index; no code execution. This is enough for the most common requests
  ("add Rust/Go/Kotlin highlighting", "add my theme") and cannot compromise the
  device.
- **After real usage (target: a few thousand active users):** add a sandboxed
  JavaScript host for commands and UI, with a permission manifest (`fs:read`,
  `network`, `editor:write`) reviewed at install time. Reuse the same
  `extension.json` so existing packages keep working.
- **Only with moderation capacity:** a hosted marketplace, verified authors,
  reviews, paid extensions. Acode shows the demand, but a marketplace without
  review is a malware distribution channel, and a marketplace with review is an
  operations cost. Do not start there.
- **Monetization for authors:** a static index can carry a `homepage` and a
  payment link; B Code does not need to process payments to let a developer
  charge. Add revenue share only when there is enough volume to justify the
  compliance work.

## Before you deploy

These are the gaps that will cost reviews or uninstalls in the first month.
[PRE_DEPLOY.md](PRE_DEPLOY.md) turns them into ordered work with acceptance
tests and a copy-paste session prompt; it also records why the app is not
rewritten in Rust.

### P0 — ship blockers

1. **Finish the extension loop.** Show what a package contributes before
   installing; rebuild the language registry on removal so "restart to unload"
   is unnecessary; publish the official `bcode-extensions` index and ship its
   URL as a default source. Version comparison and one-tap **Update** already
   work against any source.
2. **First-run path to a successful Run.** Onboarding should end with a working
   file and a runtime download that is explained, cancellable and resumable.
   A code editor that fails at "Run" on first launch loses the user immediately.
3. **Store compliance.** Real privacy policy URL, support email, data-safety
   form, screenshots that show editing → running → GitHub, and a content rating
   that matches the GitHub/terminal capabilities.
4. **Crash and startup budget.** Test on a 3 GB RAM device. Measure cold start
   and time-to-first-keystroke. Report crashes with a redacted log (already
   scaffolded) before reviews do it for you.
5. **Backup/export of the workspace.** Users will uninstall, change phones, or
   clear data. One obvious "Export project" path (zip) prevents angry reviews.

### P1 — close the most visible Acode gaps

6. **LSP-lite for Python and JavaScript.** Symbol outline, go-to-definition and
   inline diagnostics. Full LSP can wait; these three cover most of the felt
   difference.
7. **Git safety.** Branch switch/create, stash, and a pull that explains
   conflicts instead of refusing. The current fast-forward-only behaviour is
   correct but will read as broken to anyone with a real repository.
8. **Extension polish.** Show the package README and contribution list before
   install, and a changelog when updating. The version check and Update button
   are already in place.
9. **More built-in languages.** Rust, Go, PHP, Ruby, Kotlin, SQL and YAML are
   the common asks. Grammar-only packs are cheap; runtimes can come later.
10. **Search and replace across files.** Global search exists; replace-all is
    the missing half for real refactors.
11. **SFTP/FTP.** High effort, but it is Acode's most defensible paid-plugin
    use case and the phone-as-thin-client audience expects it. Consider it
    after the launch metrics, not before.
12. **Multi-cursor / column selection.** Check what the current editor supports;
    if absent, this is a "real editor" checkbox that costs less than a debugger.

### Do not build before launch

- A debugger. High effort, low initial usage, and it delays the store.
- Live collaboration. No audience yet to collaborate with.
- A full marketplace backend. Static indexes are enough for the first hundred
  extensions.
- iOS. Apple's rules make on-device compilation of downloaded code a policy
  problem; solve Android first.

## After you have an audience

Ordered by leverage, not novelty.

1. **AI coding assistant (the monetization engine).** Acode already has an AI
   Agent plugin and paid AI plugins. A first-party assistant that can read the
   open file, explain an error, and propose a patch — with the user's own API key
   or a free-tier provider — is the feature people will pay for. Keep the
   zero-cost default (user-supplied key) and add a paid hosted tier later.
2. **Marketplace v2.** Accounts, reviews, verified authors, update channels,
   paid extensions. This is Acode's moat; compete only after you have
   distribution, otherwise you are building a store with no shoppers.
3. **Cloud build/run for heavy stacks.** PHP/MySQL, Android builds, Rust/Go
   toolchains that are too large for a phone. Charge for compute; keep local
   execution free.
4. **Sync and multi-device.** Settings, snippets, extensions and workspaces
   through GitHub Gist (free) or Supabase (free tier), then a paid tier.
5. **Deeper IDE features.** Real LSP servers, debugger, test runner, refactors.
   These retain professional users and justify a Pro tier.
6. **Collaboration.** CRDT editing and shared terminals. Expensive; only after
   a team/education segment appears.
7. **Content and community.** Docs site, extension author guide, template
   gallery, Discord/Telegram. Acode's community is a real advantage; it is built
   by shipping consistently, not by a single feature.
8. **Desktop and iOS.** Reuse the Flutter code, keep execution Android-first.
   Desktop is the natural home for the "same project, bigger screen" story.
9. **Theme and icon marketplace.** Cheap engagement once the package format has
   themes; bundle it with marketplace v2.
10. **Education/classroom mode.** Shared workspaces, assignment templates,
    offline runtimes. A niche Acode does not own.

## Positioning in one line

Acode is the extensible editor you assemble from plugins. B Code is the editor
that already runs your code — safely extensible, no account, no server, no
surprise bills.
