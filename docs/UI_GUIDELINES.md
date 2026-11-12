# B Code UI rules

Learned from the icon-only toolbar that shipped in 1.0.0: seven unlabelled
icons, three of which pointed at something other than what they looked like.
A download arrow meant "install a language runtime", `< >` meant GitHub, and
the hamburger was fused with a magnifier. On a phone there is no hover, so a
tooltip is not a label.

## 1. Every action is either labelled or obvious

- An icon-only button is allowed only when its meaning is unambiguous at a
  glance AND a tooltip exists. Prefer a visible caption.
- Primary editor actions (Files, Save, Find, Run, Preview) live in the
  labelled `_ActionBar` under the app bar, with icon + caption.
- The app bar carries the file name and the overflow menu only.

## 2. One action, one entry point

Before adding a button, search for an existing path to the same command.
Past duplicates that were removed: save (app bar + key row), find (app bar +
key row + overflow), export (toolbar icon + menu item).

## 3. Icons must not lie

| Do not use | For | Because |
|---|---|---|
| `Icons.download` | installing runtimes | reads as "download a file" |
| `Icons.code` | Git | reads as "code/format/view source" |
| `Icons.content_copy` | new from template | reads as duplicate |
| `Icons.visibility_off` | "show hidden files" | reads as "hide something" |

## 4. Name things after what the user wants

- `Downloads` -> `Runtimes (Python, Java, C…)`
- `Dev Servers` -> `Ports & live URLs`
- `GitHub` -> `Git & GitHub`
- `Global Search` -> `Search in all files`

## 5. Settings is grouped, not one scroll

Four tabs: `Editor`, `Appearance`, `Git & runs`, `About`. A new setting goes
in the tab that matches what it changes, not appended to the end.

## 6. Colour comes from the theme

`colorScheme`, never a hardcoded `Color(0xFF…)` or `Colors.white70`. A
hardcoded dark colour stays dark in light theme and becomes unreadable.
