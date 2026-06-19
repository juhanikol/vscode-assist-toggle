# Contributing

Thanks for helping make vassist safer and easier for beginners.

1. Keep runtime changes project-local. Never add access to VS Code User/Machine settings, extension state, caches, authentication, or sessions.
2. Keep ordinary usage based on `vassist`; `make` is only a developer convenience.
3. Add or update isolated tests under `/tmp`. Tests must never modify this repository's `.vscode/settings.json`.
4. Run `make check` and `make test` before opening a pull request.
5. Explain user-facing behavior and error messages in plain language.

Bug reports should include `vassist --version`, `vassist doctor` output with private paths redacted when necessary, the platform, and reproduction steps.
