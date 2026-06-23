#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d /tmp/vassist-test.XXXXXX)"
TEST_HOME="$TEST_DIR/home"
TEST_PROJECT="$TEST_DIR/project"
COMMENT_PROJECT="$TEST_DIR/comment-project"
DEFAULT_PROJECT="$TEST_DIR/default-project"
DOCTOR_PROJECT="$TEST_DIR/doctor-project"
DOT_PROJECT="$TEST_DIR/dot-project"
ABSOLUTE_PROJECT="$TEST_DIR/absolute-project"
IDEMPOTENT_PROJECT="$TEST_DIR/idempotent-project"
LOCK_PROJECT="$TEST_DIR/lock-project"
SLOW_BIN="$TEST_DIR/slow-bin"
OLD_BIN="$TEST_DIR/old-bin"
FAKE_BIN="$TEST_DIR/bin"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

assert_assist_settings() {
  local settings_file="$1"
  test -f "$settings_file"
  python3 - "$settings_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    settings = json.load(handle)

assert settings["chat.disableAIFeatures"] is False
assert settings["github.copilot.enable"] == {"*": True}
assert settings["editor.tabCompletion"] == "on"
PY
}

mkdir -p "$TEST_HOME" "$TEST_PROJECT" "$COMMENT_PROJECT/.vscode" "$DEFAULT_PROJECT" "$DOCTOR_PROJECT" "$DOT_PROJECT" "$ABSOLUTE_PROJECT" "$IDEMPOTENT_PROJECT/.vscode" "$LOCK_PROJECT" "$SLOW_BIN" "$OLD_BIN" "$FAKE_BIN"
cat > "$FAKE_BIN/code" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$TEST_DIR/code-args"
pwd -P > "$TEST_DIR/code-pwd"
EOF
chmod +x "$FAKE_BIN/code"

cat > "$IDEMPOTENT_PROJECT/.vscode/settings.json" <<'JSON'
{
    "files.autoSave": "off",
    "editor.inlineSuggest.enabled": true
}
JSON

export HOME="$TEST_HOME"
export PATH="$FAKE_BIN:$PATH"

"$ROOT_DIR/install.sh"
test -x "$HOME/.local/bin/vassist"
"$HOME/.local/bin/vassist" --help >/dev/null
expected_version="vassist $(<"$ROOT_DIR/VERSION")"
test "$("$HOME/.local/bin/vassist" --version)" = "$expected_version"
test "$(<"$HOME/.local/share/vscode-assist-toggle/VERSION")" = "$(<"$ROOT_DIR/VERSION")"

cat > "$OLD_BIN/python3" <<'PYTHON'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
  echo "Python 3.8.0"
  exit 0
fi
exit 1
PYTHON
chmod +x "$OLD_BIN/python3"
if PATH="$OLD_BIN:$PATH" "$HOME/.local/bin/vassist" status >"$TEST_DIR/runtime-old-python-output" 2>&1; then
  echo "Expected runtime to reject Python 3.8." >&2
  exit 1
fi
grep -Fq "Python 3.9 or newer is required. Found: Python 3.8.0" "$TEST_DIR/runtime-old-python-output"

cat > "$COMMENT_PROJECT/.vscode/settings.json" <<'JSONC'
{
    // This comment should trigger a warning.
    "files.autoSave": "off",
}
JSONC
cp "$COMMENT_PROJECT/.vscode/settings.json" "$TEST_DIR/settings-before-dry-run.jsonc"
cd "$COMMENT_PROJECT"
"$HOME/.local/bin/vassist" learn --dry-run >"$TEST_DIR/comment-dry-output" 2>"$TEST_DIR/comment-dry-warning"
grep -Fq "contains JSONC comments" "$TEST_DIR/comment-dry-warning"
grep -Fq "A real mode change would rewrite" "$TEST_DIR/comment-dry-warning"
cmp "$TEST_DIR/settings-before-dry-run.jsonc" .vscode/settings.json
"$HOME/.local/bin/vassist" learn >"$TEST_DIR/comment-write-output" 2>"$TEST_DIR/comment-write-warning"
grep -Fq "Close all VS Code windows and reopen the project for changes to take effect." "$TEST_DIR/comment-write-output"
grep -Fq "This mode change will rewrite" "$TEST_DIR/comment-write-warning"
if grep -Fq "This comment should trigger" .vscode/settings.json; then
    echo "Comment was unexpectedly preserved"
    exit 1
fi
"$HOME/.local/bin/vassist" restore >/dev/null
grep -Fq "This comment should trigger" .vscode/settings.json

cd "$DEFAULT_PROJECT"
"$HOME/.local/bin/vassist" >/dev/null
test -f .vscode/settings.json
grep -Fxq "." "$TEST_DIR/code-args"
grep -Fxq "$DEFAULT_PROJECT" "$TEST_DIR/code-pwd"
"$HOME/.local/bin/vassist" assist >/dev/null

cd "$DOT_PROJECT"
"$HOME/.local/bin/vassist" . >/dev/null
test -f .vscode/settings.json
grep -Fxq "." "$TEST_DIR/code-args"
grep -Fxq "$DOT_PROJECT" "$TEST_DIR/code-pwd"
"$HOME/.local/bin/vassist" assist >/dev/null

cd "$TEST_DIR"
"$HOME/.local/bin/vassist" "$ABSOLUTE_PROJECT" >/dev/null
test -f "$ABSOLUTE_PROJECT/.vscode/settings.json"
grep -Fxq "." "$TEST_DIR/code-args"
grep -Fxq "$ABSOLUTE_PROJECT" "$TEST_DIR/code-pwd"
"$HOME/.local/bin/vassist" assist "$ABSOLUTE_PROJECT" >/dev/null

if "$HOME/.local/bin/vassist" "$HOME" >"$TEST_DIR/danger-output" 2>&1; then
  echo "Expected dangerous HOME target to be refused." >&2
  exit 1
fi
grep -Fq "refusing potentially dangerous project directory" "$TEST_DIR/danger-output"
test ! -e "$HOME/.vscode/settings.json"
"$HOME/.local/bin/vassist" "$HOME" --force >/dev/null
test -f "$HOME/.vscode/settings.json"
grep -Fxq "$HOME" "$TEST_DIR/code-pwd"
"$HOME/.local/bin/vassist" assist "$HOME" --force >/dev/null
assert_assist_settings "$HOME/.vscode/settings.json"

if SUDO_USER=test-user "$HOME/.local/bin/vassist" status >"$TEST_DIR/sudo-output" 2>&1; then
  echo "Expected sudo-style execution to be refused." >&2
  exit 1
fi
grep -Fq "refuses to run as root or through sudo" "$TEST_DIR/sudo-output"

cd "$IDEMPOTENT_PROJECT"
"$HOME/.local/bin/vassist" learn >/dev/null
cp .vscode/.assist-toggle-backups/original.settings.json "$TEST_DIR/original-backup-copy"
learn_inode="$(stat -c '%i' .vscode/settings.json)"
learn_history_count="$(find .vscode/.assist-toggle-backups -maxdepth 1 -name 'settings.*' -type f | wc -l)"
"$HOME/.local/bin/vassist" learn >"$TEST_DIR/learn-again-output"
grep -Fq "Mode already active: learn" "$TEST_DIR/learn-again-output"
test "$learn_inode" = "$(stat -c '%i' .vscode/settings.json)"
test "$learn_history_count" = "$(find .vscode/.assist-toggle-backups -maxdepth 1 -name 'settings.*' -type f | wc -l)"
cmp "$TEST_DIR/original-backup-copy" .vscode/.assist-toggle-backups/original.settings.json

"$HOME/.local/bin/vassist" >"$TEST_DIR/default-again-output"
grep -Fq "Mode already active: learn" "$TEST_DIR/default-again-output"
grep -Fxq "." "$TEST_DIR/code-args"
grep -Fxq "$IDEMPOTENT_PROJECT" "$TEST_DIR/code-pwd"
test "$learn_inode" = "$(stat -c '%i' .vscode/settings.json)"
test "$learn_history_count" = "$(find .vscode/.assist-toggle-backups -maxdepth 1 -name 'settings.*' -type f | wc -l)"

"$HOME/.local/bin/vassist" strict >"$TEST_DIR/strict-output"
grep -Fq "Close all VS Code windows and reopen the project for changes to take effect." "$TEST_DIR/strict-output"
strict_inode="$(stat -c '%i' .vscode/settings.json)"
strict_history_count="$(find .vscode/.assist-toggle-backups -maxdepth 1 -name 'settings.*' -type f | wc -l)"
"$HOME/.local/bin/vassist" strict >"$TEST_DIR/strict-again-output"
grep -Fq "Mode already active: strict" "$TEST_DIR/strict-again-output"
test "$strict_inode" = "$(stat -c '%i' .vscode/settings.json)"
test "$strict_history_count" = "$(find .vscode/.assist-toggle-backups -maxdepth 1 -name 'settings.*' -type f | wc -l)"
cmp "$TEST_DIR/original-backup-copy" .vscode/.assist-toggle-backups/original.settings.json

"$HOME/.local/bin/vassist" assist >"$TEST_DIR/assist-output"
grep -Fq "Close all VS Code windows and reopen the project for changes to take effect." "$TEST_DIR/assist-output"
assist_inode="$(stat -c '%i' .vscode/settings.json)"
assist_history_count="$(find .vscode/.assist-toggle-backups -maxdepth 1 -name 'settings.*' -type f | wc -l)"
"$HOME/.local/bin/vassist" assist >"$TEST_DIR/assist-again-output"
grep -Fq "Already restored to original/pre-learning state" "$TEST_DIR/assist-again-output"
test "$assist_inode" = "$(stat -c '%i' .vscode/settings.json)"
test "$assist_history_count" = "$(find .vscode/.assist-toggle-backups -maxdepth 1 -name 'settings.*' -type f | wc -l)"
cmp "$TEST_DIR/original-backup-copy" .vscode/.assist-toggle-backups/original.settings.json

restore_history_count="$assist_history_count"
"$HOME/.local/bin/vassist" restore >"$TEST_DIR/restore-again-output"
grep -Fq "Restored original/pre-learning state" "$TEST_DIR/restore-again-output"
test "$((restore_history_count + 1))" = "$(find .vscode/.assist-toggle-backups -maxdepth 1 -name 'settings.*' -type f | wc -l)"
cmp "$TEST_DIR/original-backup-copy" .vscode/settings.json
"$HOME/.local/bin/vassist" learn >/dev/null
cmp "$TEST_DIR/original-backup-copy" .vscode/.assist-toggle-backups/original.settings.json

real_python="$(command -v python3)"
cat > "$SLOW_BIN/python3" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *settings-patch.py* ]]; then
  sleep 2
fi
exec "$real_python" "\$@"
EOF
chmod +x "$SLOW_BIN/python3"
cd "$LOCK_PROJECT"
PATH="$SLOW_BIN:$PATH" "$HOME/.local/bin/vassist" learn >"$TEST_DIR/first-lock-output" 2>&1 &
first_vassist_pid=$!
# Wait for the first vassist to acquire the lock.
wait_count=0
while [[ ! -d .vscode/.assist-toggle.lockdir && "$wait_count" -lt 100 ]]; do
  sleep 0.02
  wait_count=$((wait_count + 1))
done
test -d .vscode/.assist-toggle.lockdir
test -f .vscode/.assist-toggle.lockdir/pid
test -f .vscode/.assist-toggle.lockdir/timestamp
if "$HOME/.local/bin/vassist" assist >"$TEST_DIR/second-lock-output" 2>&1; then
  echo "Expected concurrent vassist command to fail." >&2
  exit 1
fi
grep -Fq "Another vassist process is already modifying this project. Try again in a moment." "$TEST_DIR/second-lock-output"
wait "$first_vassist_pid"
test ! -e .vscode/.assist-toggle.lockdir

cd "$TEST_PROJECT"
VASSIST_USER_SETTINGS_OVERRIDE="$TEST_DIR/missing-user-settings.json" "$HOME/.local/bin/vassist" doctor | grep -Fq "Doctor result: healthy"
mkdir -p .vscode/.assist-toggle.lockdir
printf '%s\n' 99999999 > .vscode/.assist-toggle.lockdir/pid
printf '%s\n' 2026-01-01T00:00:00Z > .vscode/.assist-toggle.lockdir/timestamp
if "$HOME/.local/bin/vassist" doctor >"$TEST_DIR/stale-lock-output" 2>&1; then
  echo "Expected doctor to reject a stale project lock." >&2
  exit 1
fi
grep -Fq "Stale project lock detected" "$TEST_DIR/stale-lock-output"
grep -Fq "After confirming no vassist process is running, remove it manually" "$TEST_DIR/stale-lock-output"
test -d .vscode/.assist-toggle.lockdir
rm -rf .vscode/.assist-toggle.lockdir

mkdir -p "$TEST_DIR/fake-user-settings"
cat > "$TEST_DIR/fake-user-settings/settings.json" <<'JSON'
{
    "editor.acceptSuggestionOnEnter": "off"
}
JSON
cd "$DOCTOR_PROJECT"
"$HOME/.local/bin/vassist" assist >/dev/null
VASSIST_USER_SETTINGS_OVERRIDE="$TEST_DIR/fake-user-settings/settings.json" "$HOME/.local/bin/vassist" doctor >"$TEST_DIR/doctor-mismatch-output"
grep -Fq "User settings: $TEST_DIR/fake-user-settings/settings.json" "$TEST_DIR/doctor-mismatch-output"
grep -Fq "[MISMATCH]" "$TEST_DIR/doctor-mismatch-output"
grep -Fq "editor.acceptSuggestionOnEnter" "$TEST_DIR/doctor-mismatch-output"
grep -Fq "workspace:       \"on\"    (vassist default)" "$TEST_DIR/doctor-mismatch-output"
grep -Fq "your preference: \"off\"   (from $TEST_DIR/fake-user-settings/settings.json)" "$TEST_DIR/doctor-mismatch-output"
"$HOME/.local/bin/vassist" learn >/dev/null
VASSIST_USER_SETTINGS_OVERRIDE="$TEST_DIR/fake-user-settings/settings.json" "$HOME/.local/bin/vassist" doctor >"$TEST_DIR/doctor-learn-output"
grep -Fq "[MISMATCH]" "$TEST_DIR/doctor-learn-output"
grep -Fq "editor.acceptSuggestionOnEnter" "$TEST_DIR/doctor-learn-output"
if VASSIST_USER_SETTINGS_OVERRIDE="$TEST_DIR/fake-user-settings/settings.json" "$HOME/.local/bin/vassist" doctor --fix >"$TEST_DIR/doctor-learn-fix-output" 2>&1; then
  echo "Expected doctor --fix to be refused in learn mode." >&2
  exit 1
fi
grep -Fq "Error: run vassist assist first before applying preference fixes." "$TEST_DIR/doctor-learn-fix-output"
"$HOME/.local/bin/vassist" assist >/dev/null
printf 'y\n' | VASSIST_USER_SETTINGS_OVERRIDE="$TEST_DIR/fake-user-settings/settings.json" "$HOME/.local/bin/vassist" doctor --fix >"$TEST_DIR/doctor-fix-output"
python3 - .vscode/settings.json <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    settings = json.load(handle)

assert settings["editor.acceptSuggestionOnEnter"] == "off"
PY

cd "$TEST_PROJECT"
test ! -e .vscode/settings.json
"$HOME/.local/bin/vassist" learn --dry-run >/dev/null
test ! -e .vscode/settings.json
"$HOME/.local/bin/vassist" learn >/dev/null
"$HOME/.local/bin/vassist" status | grep -Fq "Current mode: Learn"
"$HOME/.local/bin/vassist" status | grep -Fq "normal language-server IntelliSense is preserved"
"$HOME/.local/bin/vassist" strict >/dev/null
"$HOME/.local/bin/vassist" status | grep -Fq "Current mode: Strict"
"$HOME/.local/bin/vassist" status | grep -Fq "normal editor completion assistance is reduced"
"$HOME/.local/bin/vassist" assist >/dev/null
assert_assist_settings .vscode/settings.json
"$HOME/.local/bin/vassist" learn --open >/dev/null
grep -Fxq "." "$TEST_DIR/code-args"
"$HOME/.local/bin/vassist" assist >/dev/null
"$HOME/.local/bin/vassist" restore >/dev/null
test ! -e .vscode/settings.json
test -d .vscode/.assist-toggle-backups

"$HOME/.local/share/vscode-assist-toggle/install.sh" --uninstall >/dev/null
test ! -e "$HOME/.local/bin/vassist"
test ! -d "$HOME/.local/share/vscode-assist-toggle"
test -d .vscode/.assist-toggle-backups

cd "$ROOT_DIR"
"$ROOT_DIR/install.sh" >/dev/null
cat > "$HOME/.local/bin/vassist" <<'CUSTOM_WRAPPER'
#!/usr/bin/env bash
echo "user-owned replacement"
CUSTOM_WRAPPER
chmod +x "$HOME/.local/bin/vassist"
grep -Fv '# <<< vassist PATH <<<' "$HOME/.bashrc" > "$TEST_DIR/bashrc-without-end"
mv "$TEST_DIR/bashrc-without-end" "$HOME/.bashrc"
cp "$HOME/.bashrc" "$TEST_DIR/bashrc-before-uninstall"
"$HOME/.local/share/vscode-assist-toggle/install.sh" --uninstall >"$TEST_DIR/uninstall-output" 2>&1
test -e "$HOME/.local/bin/vassist"
cmp "$TEST_DIR/bashrc-before-uninstall" "$HOME/.bashrc"
grep -Fq "not the installer-owned wrapper" "$TEST_DIR/uninstall-output"
grep -Fq "incomplete or duplicated" "$TEST_DIR/uninstall-output"

echo "Isolated install/version, idempotency, locking/stale-lock, path safety, JSONC, mode, open, restore, and guarded-uninstall tests passed."
