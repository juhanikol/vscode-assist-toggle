# vassist — VS Code learning mode for students and self-learners

## Quick start

Supported platform: Bash on Linux or WSL, with Python 3.9 or newer.

```bash
git clone github.com/juhanikol/vscode-assist-to.git
cd vscode-assist-toggle
./install.sh
cd /path/to/your/project
vassist
```

Check an installation with `vassist --version` and `vassist doctor`.

Learning to code is already hard enough.

You are trying to understand the language, the editor, the terminal, Git, project structure, error messages, and your own code at the same time. AI coding assistants can be useful, but when you are practising, they can also quietly change the whole learning experience. One moment you planned to solve the problem yourself, and a few suggestions later the rest of the day has been coded with another brain.

Many students also struggle with VS Code settings. You disable something, an extension update changes the behavior, a setting comes back, or different projects suddenly behave differently. While experimenting, it is easy to accidentally change editor settings globally and end up with an inconsistent or broken setup.

`vassist` exists to make this simpler.

The only VS Code settings file it modifies is the current project's `.vscode/settings.json`; it also creates project-local backup/state/lock files.

It does not touch your global VS Code settings, WSL settings, extension storage, authentication, caches, or other projects. It creates backups, keeps the change local to the project, and lets you switch between learning mode and normal assist mode from the terminal.

If you already start VS Code from the terminal with:

```
code .
```

then using this tool should feel just as simple:

```
vassist
```

No more hunting through settings. No more wondering which project has AI assistance enabled. No more accidentally changing your whole editor setup just because you wanted one focused learning session.

Let the tool worry about the settings, so you can focus on learning

## vassist explained

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

This is a practice aid, not an enforcement or exam-proctoring system. Workspace settings can be changed by anyone who can edit the repository. The point is psychological, not technical enforcement.

When you run vassist the project opens in learning mode. AI assistance is off before the coding session begins. After that, turning it back on is still possible, but it now requires a conscious interruption: change the mode, reload or reopen the editor, and restart the flow. That small amount of friction matters. For a tired or overloaded student, it is often enough to stay with the original decision and keep practising independently.

The goal is not to prevent anyone from using AI. The goal is to help the learner make one clear decision at the beginning of the session — and then stay inside that decision long enough to actually learn.

## Install

Clone this repository once and run its installer:

```bash
git clone github.com/juhanikol/vscode-assist-toggle.git
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
vassist
```

The beginner-friendly comparison is:

```bash
code .      # Normal VS Code start
vassist     # Apply learn mode here, then open VS Code here
```

You can also select the project explicitly:

```bash
vassist .
vassist /path/to/project
vassist assist
vassist status
```

With no arguments or with a directory argument, `vassist` applies learn mode and runs `code .` from the selected directory. Explicit commands such as `vassist learn`, `vassist assist`, and `vassist status` do not open VS Code unless `--open` is supplied.

Mode commands are idempotent: requesting an already-active mode does not rewrite `settings.json` or create another history backup. Bare `vassist` still opens VS Code when Learn mode is already active. The original/pre-learning snapshot is created once and is never replaced by Learn or Strict settings.

`vassist doctor` is read-only. It checks Python, the installed command, PATH, optional `code`/`make` availability, and whether the current workspace settings and saved state are valid.

Ordinary empty folders are allowed. When no common project marker is present, `vassist` prints: “Using this folder as the project because you ran vassist here.” Known system, home, Windows-system, and installed-tool directories are refused unless explicitly confirmed with `--force`. `vassist` always refuses to run as root or through sudo.

Real modifying commands use an atomic project-local lock at `.vscode/.assist-toggle.lockdir`. A concurrent command exits instead of racing backups or writes. The lock records a PID and UTC timestamp and is removed automatically on normal exit.

If a crash or forced shutdown leaves that lock behind, `vassist doctor` reports it as stale but does not delete it. First confirm that no vassist process is running, then follow the exact manual removal command printed by `doctor`.

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
vassist
vassist learn --open
vassist strict --open
vassist assist --open
```

The default command and `--open` apply the mode and then run `code .` from the target project. Run **Developer: Reload Window** if changes do not apply.

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

- Python 3.9 or newer is required for safe JSON/JSONC validation and patching.
- `make` is optional and used only for developer convenience.
- `code` is required for bare `vassist`, directory shortcuts such as `vassist .`, and explicit `--open` commands.
- Explicit non-opening commands such as `vassist learn`, `vassist assist`, and `vassist status` require neither `make` nor `code`.
- The default installer never runs `sudo`.
- PATH setup currently targets Bash on Linux/WSL by updating `.bashrc` only when needed. zsh and fish are not configured automatically.

On Ubuntu/WSL, dependencies can optionally be installed before the normal installation:

```bash
./install.sh --install-deps
```

The installer prints the exact commands, asks for confirmation with `[y/N]`, then runs `sudo apt update` and `sudo apt install -y python3 make`. Use `./install.sh --install-deps --yes` only when you intentionally want to skip that confirmation. It never runs `apt upgrade`. You can instead install Python manually and run ordinary `./install.sh` without sudo.

## Support and security

Report bugs or request help at `github.com/juhanikol/vscode-assist-toggle/issues` . Include `vassist --version`, your Linux/WSL version, and redacted `vassist doctor` output. See [SECURITY.md](SECURITY.md) for private vulnerability-reporting guidance.

## What the tool does not touch

At runtime, the tool manages only the current project's `.vscode/settings.json`, `.vscode/.assist-toggle-backups/`, and temporary `.vscode/.assist-toggle.lockdir/`. It does not touch:

- Windows VS Code User settings
- WSL VS Code User or Machine settings
- VS Code profiles or `globalStorage`
- Codex, Gemini, or OpenAI caches
- authentication or session files
- Gemini settings

Workspace and state writes are atomic. Unrelated project settings are preserved. The tool never uses `code --remote`.

## Comparison with other approaches


| Approach                   | Scope and tradeoff                                                                                                            |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `vassist`                  | One terminal command per project, original-state backup, and separate learn/strict modes. No VS Code extension is required.   |
| Manual workspace settings  | Built into VS Code and equally project-local, but repetitive and easier to restore incorrectly across many exercises.         |
| VS Code profiles           | Useful for broad editor setups, extension sets, and UI preferences, but profile state is wider than one exercise repository.  |
| Settings-toggle extensions | Can provide convenient UI toggles, but require installing and trusting another extension and may use extension-managed state. |

For one-off use, editing workspace settings manually is perfectly reasonable. `vassist` mainly adds repeatability, mode names, validation, and clear restoration.

## Note for educators

`vassist` is not designed as an enforcement mechanism. It is a instructional design tool that changes the learner’s starting condition. Instead of relying on students to repeatedly remember to disable AI assistance, the learning session begins with independent work as the default state. From that point on, re-enabling assistance requires an intentional context switch, which uses ordinary decision inertia in favor of practice rather than against it.

Pedagogically, the tool aims to preserve useful scaffolding while protecting productive cognitive effort. In learning mode, students can still use normal editor feedback, compiler messages, language-server support, and documentation, but generative assistance is moved out of the immediate problem-solving loop. This supports self-regulation, retrieval, debugging, hypothesis testing, and the kind of desirable difficulty where the learner must actively construct part of the solution instead of merely accepting it.

The goal is not to reject AI as a learning tool. The goal is to make the boundary between practice and assisted production explicit, repeatable, and easy to manage at the level of a single project.

https://pmc.ncbi.nlm.nih.gov/articles/PMC5408091/

https://www.cambridge.org/core/journals/behavioural-public-policy/article/when-and-why-defaults-influence-decisions-a-metaanalysis-of-default-effects/67AF6972CFB52698A60B6BD94B70C2C0

https://www.whz.de/fileadmin/lehre/hochschuldidaktik/docs/dunloskiimprovingstudentlearning.pdf
