# Security policy

## Supported version

Security fixes currently target the latest release listed in `VERSION`.

## Reporting a vulnerability

Please do not publish credentials, tokens, private settings, or exploit details in a public issue. Use GitHub's private security-advisory feature when it is available for this repository; otherwise contact the maintainer through their GitHub profile and ask for a private reporting channel.

Include the vassist version, operating system, command used, and the smallest safe reproduction you can provide.

## Security boundaries

At runtime, vassist manages only the selected project's `.vscode/settings.json` plus its project-local backup/state and lock directories. It must not access VS Code User or Machine settings, extension storage, caches, authentication, or sessions.

The installer may add its own marked PATH block to `.bashrc`. The default installer does not use `sudo`; the optional `--install-deps` flow prints its exact `apt` commands and asks before running `sudo apt update` and package installation.
