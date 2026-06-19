#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd -- "$ROOT_DIR"

fail() {
  echo "Release check failed: $*" >&2
  exit 1
}

[[ -f VERSION ]] || fail "VERSION is missing"
version="$(<VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || fail "VERSION is not SemVer-like: $version"
[[ "$(bash scripts/vscode-mode.sh --version)" == "vassist $version" ]] || fail "CLI version differs from VERSION"

[[ ! -e .vscode/settings.json ]] || fail "repository-local .vscode/settings.json must not ship"
[[ ! -d .vscode/.assist-toggle-backups ]] || fail "repository-local backup artifacts must not ship"
[[ ! -d .vscode/.assist-toggle.lockdir ]] || fail "repository-local lock artifacts must not ship"

help_output="$(bash scripts/vscode-mode.sh --help)"
for command_name in learn strict assist status doctor backups restore --version; do
  grep -Fq -- "$command_name" <<<"$help_output" || fail "help is missing $command_name"
done
grep -Fq "Report issues:" <<<"$help_output" || fail "help is missing issue-reporting guidance"

for text in "vassist --version" "vassist doctor" "github.com/juhanikol/vscode-assist-toggle.git" "Python 3.9" "Linux/WSL"; do
  grep -Fq "$text" README.md || fail "README is missing: $text"
done

if grep -R -E 'code[[:space:]]+\.\.|code[[:space:]]+--remote' scripts install.sh; then
  fail "runtime contains a forbidden VS Code invocation"
fi

echo "Release artifact, version, help, README, and runtime-scope checks passed."
