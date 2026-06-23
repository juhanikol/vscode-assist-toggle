# vassist — Settings reference

This document explains every VS Code setting that `vassist` manages, what the
VS Code factory default is for each one, and how the three modes apply and
restore them. `vassist assist` generally writes VS Code factory defaults, with
one intentional exception for `editor.tabCompletion`.

---

## Mode behaviour summary

| Mode | What it writes to `.vscode/settings.json` |
|---|---|
| `learn` | Writes `LEARN_VALUES` (AI off, IntelliSense untouched) |
| `strict` | Writes `LEARN_VALUES` + `STRICT_VALUES` (AI off + generic completion reduced) |
| `assist` | Writes `ASSIST_DEFAULTS` — VS Code factory defaults, except tab completion is intentionally on |
| `restore` | Restores the original snapshot taken before the first learn/strict run |

### Why `assist` writes explicit defaults instead of removing keys

Removing a key from `settings.json` leaves the workspace dependent on whatever
VS Code resolves from the settings hierarchy (default → user → remote →
workspace). In a Windows + WSL2 remote setup, that resolution involves both
the Windows-side user settings file and the WSL-side remote/machine settings
file. If either of those files contains a value for a managed key, or if VS
Code's internal workspace-state cache (`state.vscdb`) holds a stale value from
a previous learn session, the workspace will behave inconsistently after the
key is removed — the AI features may stay suppressed even though nothing in
the settings files says so.

Writing explicit assist defaults solves both problems at once:

- VS Code always has a concrete value to read at the workspace scope.
- The workspace-state cache is overwritten on the next reload.
- The user ends up in a clearly documented, well-known state.

`editor.tabCompletion` is the one deliberate exception: VS Code's factory
default is `"off"`, but `vassist assist` writes `"on"` because most beginner
users expect Tab to accept useful completions during normal work. Leaving it
off makes assist mode feel like completion is still partially reduced after a
practice session. If that value does not match a user's personal preference,
`vassist doctor` can detect the mismatch and propose or apply a correction.
The user makes one intentional decision; the tool documents it.

---

## ASSIST_DEFAULTS — the values written by `vassist assist`

These are the values written as a group whenever `vassist assist` runs. They
match VS Code factory defaults except for `editor.tabCompletion`, which is
intentionally set to `"on"` for a more helpful beginner assist mode.

```python
ASSIST_DEFAULTS: dict[str, Any] = {
    # AI master switch — default is off (feature exists but is not forced on)
    "chat.disableAIFeatures": False,

    # Copilot per-language toggle — default is all languages enabled
    "github.copilot.enable": {"*": True},

    # Ghost-text inline suggestions — default on
    "editor.inlineSuggest.enabled": True,

    # Auto-popup on trigger characters (. ( etc.) — default on
    "editor.suggestOnTriggerCharacters": True,

    # Accept suggestion with Enter — default "on"
    "editor.acceptSuggestionOnEnter": "on",

    # Accept suggestion on commit characters (; , etc.) — default on
    "editor.acceptSuggestionOnCommitCharacter": True,

    # Tab completion — VS Code default is "off"; vassist intentionally enables it
    "editor.tabCompletion": "on",

    # Snippet suggestions in dropdown — default "inline"
    "editor.snippetSuggestions": "inline",

    # Quick suggestion popup while typing
    "editor.quickSuggestions": {
        "other": "on",
        "comments": "off",
        "strings": "off",
    },
}
```

After running `vassist assist`, the user should close all VS Code windows and
reopen the project. This forces VS Code to re-read `settings.json` and flush
any cached state from the previous learn/strict session.

---

## LEARN_VALUES

```python
LEARN_VALUES: dict[str, Any] = {
    "chat.disableAIFeatures": True,
    "github.copilot.enable": {"*": False},
}
```

### `chat.disableAIFeatures`

| | |
|---|---|
| Type | boolean |
| VS Code default | `false` |
| Learn value | `true` |

The official VS Code master switch for all built-in AI. Setting it `true`
disables and hides the Chat view, all inline AI suggestions, Copilot chat,
and AI-powered editor actions. It signals the Copilot extension to
deactivate. This is the same setting used by VS Code's own "Learn How to Hide
AI Features" menu action and is the most stable key to use as VS Code evolves.

### `github.copilot.enable`

| | |
|---|---|
| Type | object — language ID → boolean |
| VS Code default | `{"*": true}` |
| Learn value | `{"*": false}` |

Per-language Copilot inline completion toggle. The `"*"` wildcard applies to
all languages. Some Copilot versions check this key independently of
`chat.disableAIFeatures`; including both provides reliable coverage across
extension versions.

---

## STRICT_VALUES

Written in addition to `LEARN_VALUES` when `vassist strict` runs. These
settings control generic editor completion — not AI specifically. They are
separated from learn mode so that students who want to keep normal
language-server IntelliSense can use `vassist learn` without triggering these.

```python
STRICT_VALUES: dict[str, Any] = {
    "editor.inlineSuggest.enabled": False,
    "editor.suggestOnTriggerCharacters": False,
    "editor.acceptSuggestionOnEnter": "off",
    "editor.acceptSuggestionOnCommitCharacter": False,
    "editor.tabCompletion": "off",
    "editor.snippetSuggestions": "none",
}
```

### `editor.inlineSuggest.enabled`

| | |
|---|---|
| Type | boolean |
| VS Code default | `true` |
| Strict value | `false` |

Controls ghost-text inline suggestions that appear as you type. When Copilot
is installed this is the primary surface for AI completions, but the setting
also governs non-AI inline suggestions from language servers. Disabling it
removes the visual prompt that can invite accidental Tab-acceptance.

### `editor.suggestOnTriggerCharacters`

| | |
|---|---|
| Type | boolean |
| VS Code default | `true` |
| Strict value | `false` |

When `true`, typing a language trigger character (`.` in JavaScript, `(` in
Python, etc.) automatically opens the suggestion dropdown. Disabling this
reduces ambient suggestion noise in strict mode; the dropdown can still be
opened manually with `Ctrl+Space`.

### `editor.acceptSuggestionOnEnter`

| | |
|---|---|
| Type | `"on"` \| `"smart"` \| `"off"` |
| VS Code default | `"on"` |
| Strict value | `"off"` |

Controls whether Enter accepts the highlighted suggestion. This is a
well-known personal preference setting — some users deliberately set it to
`"off"` (Tab-only workflow) to avoid accepting completions when pressing Enter
to insert a newline. Others rely on Enter for acceptance.

Strict mode sets it to `"off"` for the practice session. `vassist assist`
restores it to the VS Code default `"on"`. If a user prefers `"off"` even in
normal work, `vassist doctor` can detect this and offer to write that
preference into the workspace settings.

### `editor.acceptSuggestionOnCommitCharacter`

| | |
|---|---|
| Type | boolean |
| VS Code default | `true` |
| Strict value | `false` |

When `true`, typing a commit character (`;`, `,`, etc.) while a suggestion is
highlighted accepts the suggestion and inserts the character. This can cause
surprising automatic completions during practice.

### `editor.tabCompletion`

| | |
|---|---|
| Type | `"on"` \| `"off"` \| `"onlySnippets"` |
| VS Code default | `"off"` |
| Strict value | `"off"` |

Tab completion is already off by default in VS Code — the default exists
because Tab is widely used and accidental acceptance is a known source of
confusion. This key is included in strict mode for explicitness and to
override any user setting that has enabled it.

Note that `vassist assist` intentionally writes `"on"` for this key even
though the VS Code factory default is `"off"`. This is a beginner-friendly
choice: after leaving a practice session, Tab should accept useful completions
again instead of making assist mode feel partially disabled. A user who
prefers the VS Code default can keep `"off"` globally, and `vassist doctor`
can detect the mismatch and propose restoring that preference in the
workspace.

### `editor.snippetSuggestions`

| | |
|---|---|
| Type | `"top"` \| `"bottom"` \| `"inline"` \| `"none"` |
| VS Code default | `"inline"` |
| Strict value | `"none"` |

Controls whether and where snippet completions appear in the dropdown.
`"none"` removes them entirely, reducing the suggestion surface to direct
language-server output only.

---

## QUICK_VALUES and `editor.quickSuggestions`

```python
# This must be written as a nested object under "editor.quickSuggestions"
QUICK_VALUES: dict[str, Any] = {
    "editor.quickSuggestions": {
        "other": False,
        "comments": False,
        "strings": False,
    }
}
```

**Important:** the three subkeys (`other`, `comments`, `strings`) must be
written as a nested object under `"editor.quickSuggestions"`. Writing them as
flat top-level keys has no effect in VS Code and is silently ignored.

| Subkey | Controls automatic suggestions while typing in… | VS Code default |
|---|---|---|
| `other` | Normal code — statements, expressions | `"on"` |
| `comments` | Inside comments | `"off"` |
| `strings` | Inside string literals | `"off"` |

Setting all three to `false` disables automatic suggestion popups entirely.
The dropdown can still be triggered manually with `Ctrl+Space`. This is an
aggressive reduction appropriate for strict mode. The assist default restores
`other` to `"on"` and leaves `comments` and `strings` at `"off"`, matching
VS Code factory behaviour.

---

## `vassist doctor` — reading and proposing settings

`vassist doctor` is the right place to handle the gap between the factory
defaults that `vassist assist` writes and the user's personal preferences.

### What doctor should check

After `vassist assist` has run and the user has reloaded the window, doctor
can read the current workspace `settings.json` and compare it against the
user's own global settings files. On a WSL2 + Windows Remote setup, those
files are:

```
# Windows-side user settings (most personal editor preferences)
/mnt/c/Users/<WIN_USER>/AppData/Roaming/Code/User/settings.json

# WSL-side remote/machine settings (server-side, language servers)
~/.vscode-server/data/Machine/settings.json

# WSL-side user settings (if native Linux VS Code is also installed)
~/.config/Code/User/settings.json
```

For each key in `ASSIST_DEFAULTS`, doctor reads the user's global value (if
any) and compares it to what is currently in `.vscode/settings.json`. If they
differ, doctor reports the mismatch and offers two options:

1. **Propose** — print the corrected key/value and ask the user to confirm.
2. **Apply** — write the user's global preference directly into
   `.vscode/settings.json`.

### Example doctor output

```
vassist doctor — checking workspace settings against your user preferences

  editor.acceptSuggestionOnEnter
    workspace (current):  "on"   ← vassist default
    your user setting:    "off"
    → Propose fix: set "editor.acceptSuggestionOnEnter": "off" in this workspace?
      [y] apply  [n] skip  [?] explain

  editor.tabCompletion
    workspace (current):  "on"   ← vassist assist default
    your user setting:    "off"
    → Propose fix: set "editor.tabCompletion": "off" in this workspace?
      [y] apply  [n] skip  [?] explain

All other managed settings match your preferences or use VS Code defaults.
```

This makes `vassist assist` a clean, predictable reset and `vassist doctor`
the interactive personalisation step — without the tool ever silently
overwriting preferences during the restore itself.

---

## Settings vassist deliberately does not touch

| Setting | Why excluded |
|---|---|
| `editor.wordBasedSuggestions` | Word completion from open files — useful IntelliSense, not AI |
| `editor.parameterHints.enabled` | Function parameter hints — useful IntelliSense, not AI |
| `github.copilot.editor.enableAutoCompletions` | Redundant when `chat.disableAIFeatures` is set |
| `github.copilot.editor.enableCodeActions` | Redundant when `chat.disableAIFeatures` is set |
| `chat.agent.enabled` | Redundant when `chat.disableAIFeatures` is set |

---

## WSL2 + Windows: the hidden workspace-state cache

When VS Code is installed on Windows and connects to WSL2 via Remote - WSL,
the VS Code client (running on Windows) maintains a per-workspace storage
directory:

```
C:\Users\<username>\AppData\Roaming\Code\User\workspaceStorage\<hash>\
    state.vscdb      ← SQLite database (extension-cached state)
    workspace.json   ← path and identity of this workspace
```

From inside WSL this is visible at:
```
/mnt/c/Users/<username>/AppData/Roaming/Code/User/workspaceStorage/
```

Extensions store their own per-workspace state (including enabled/disabled
flags) in `state.vscdb` via `context.workspaceState`. This file is never
read or written by `vassist`. By writing explicit values to `settings.json`
during `vassist assist`, VS Code re-reads and overwrites the extension's
cached state on the next **Developer: Reload Window**, making direct database
access unnecessary.

To locate the database for a specific project from WSL (for manual inspection
only):

```bash
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
grep -rl "$(basename "$PWD")" \
  "/mnt/c/Users/$WIN_USER/AppData/Roaming/Code/User/workspaceStorage/"*/workspace.json \
  2>/dev/null
```

The database files exist only after the workspace has been opened at least
once in VS Code.
