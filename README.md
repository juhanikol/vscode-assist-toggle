# VS Code Assist Toggle

## Learning without losing IntelliSense

`vassist` creates a project-local no-AI practice mode for VS Code. Students can keep normal IntelliSense, compiler diagnostics, language-server feedback, parameter hints, hover, and definition navigation while AI generation is disabled for an exercise repository.

- **Learn mode** disables AI assistance, not normal IntelliSense.
- **Strict mode** disables AI and reduces more generic editor assistance for distraction-free practice.
- **Project-local only:** runtime changes stay in the current project's `.vscode/settings.json` and local backup directory.
- **Bootcamp and school friendly:** instructors can use the same small terminal workflow per exercise repository without changing each student's global VS Code configuration.

Typical users include:

- coding bootcamp students
- teachers and schools using VS Code
- self-learners
- developers who want temporary no-AI practice
- WSL/Linux users who prefer a simple terminal workflow

This is a practice aid, not an enforcement or exam-proctoring system. Workspace settings can be changed by anyone who can edit the repository.

## Install

Clone this repository once and run its installer:

```bash
git clone <REPOSITORY_URL> vscode-assist-toggle  # Replace with the actual repository URL.
cd vscode-assist-toggle
./install.sh
```

The default installer does not use `sudo`. It copies the runtime to `~/.local/share/vscode-assist-toggle/`, creates `~/.local/bin/vassist`, adds a small PATH block to `.bashrc` only if needed, and verifies the wrapper.

Open a new terminal after installation, or run:

```bash
source ~/.bashrc
vassist --help
```

## Use from any project

Run `vassist` from the root of the project you want to change:

```bash
cd /path/to/project
vassist doctor
vassist status
vassist learn
```

The current directory is always the workspace boundary. Normal commands do not require `make` or the VS Code `code` command.

`vassist doctor` is read-only. It checks Python, the installed command, PATH, optional `code`/`make` availability, and whether the current workspace settings and saved state are valid.

## Modes: `learn`, `strict`, `assist`

```bash
vassist learn
vassist strict
vassist assist
vassist status
```

- `learn` disables built-in VS Code AI and GitHub Copilot while preserving normal language-server IntelliSense.
- `strict` also reduces generic editor completion assistance for distraction-free practice.
- `assist` restores or removes only settings managed by this tool.

Learn mode disables VS Code built-in AI and Copilot-style features that respect workspace settings. Some third-party AI extensions may ignore these settings; disable those extensions manually for the workspace when necessary. `vassist` never modifies extension storage, caches, authentication, or sessions.

Preview without changing settings or creating backups:

```bash
vassist learn --dry-run
vassist strict --dry-run
```

## Open VS Code with a mode

```bash
vassist learn --open
vassist strict --open
vassist assist --open
```

`--open` applies the mode and then runs `code .`. The `code` command is required only for this option. Run **Developer: Reload Window** if changes do not apply.

## Restore

```bash
vassist backups
vassist restore
```

`restore` restores the named original/pre-learning state and first creates a safety/history backup. Explicit history recovery is also available:

```bash
vassist restore latest
vassist restore settings.20260619-120000-000000.json
```

VS Code accepts JSONC comments in `settings.json`, but this tool uses Python's standard JSON writer and does not preserve those comments during mode changes. Both dry runs and normal writes warn when comments are detected. The exact original snapshot retained for `restore` preserves its original bytes and comments.

## Uninstall

```bash
~/.local/share/vscode-assist-toggle/install.sh --uninstall
```

Uninstall removes only the installer-owned runtime, wrapper, and `.bashrc` PATH block. It leaves every project-local `.vscode/.assist-toggle-backups/` directory untouched.

## Dependency notes

- `python3` is required for safe JSON/JSONC validation and patching.
- `make` is optional and used only for developer convenience.
- `code` is optional and needed only for `vassist --open`.
- Ordinary `vassist` commands require neither `make` nor `code`.
- The default installer never runs `sudo`.
- PATH setup currently targets Bash on Linux/WSL by updating `.bashrc` only when needed. zsh and fish are not configured automatically.

On Ubuntu/WSL, dependencies can optionally be installed before the normal installation:

```bash
./install.sh --install-deps
```

The installer prints the exact commands, asks for confirmation with `[y/N]`, then runs `sudo apt update` and `sudo apt install -y python3 make`. Use `./install.sh --install-deps --yes` only when you intentionally want to skip that confirmation. It never runs `apt upgrade`. You can instead install Python manually and run ordinary `./install.sh` without sudo.

## What the tool does not touch

At runtime, the tool changes only the current project's `.vscode/settings.json` and `.vscode/.assist-toggle-backups/`. It does not touch:

- Windows VS Code User settings
- WSL VS Code User or Machine settings
- VS Code profiles or `globalStorage`
- Codex, Gemini, or OpenAI caches
- authentication or session files
- Gemini settings

Workspace and state writes are atomic. Unrelated project settings are preserved. The tool never uses `code --remote`.

## Comparison with other approaches

| Approach | Scope and tradeoff |
|---|---|
| `vassist` | One terminal command per project, original-state backup, and separate learn/strict modes. No VS Code extension is required. |
| Manual workspace settings | Built into VS Code and equally project-local, but repetitive and easier to restore incorrectly across many exercises. |
| VS Code profiles | Useful for broad editor setups, extension sets, and UI preferences, but profile state is wider than one exercise repository. |
| Settings-toggle extensions | Can provide convenient UI toggles, but require installing and trusting another extension and may use extension-managed state. |

For one-off use, editing workspace settings manually is perfectly reasonable. `vassist` mainly adds repeatability, mode names, validation, and clear restoration.
