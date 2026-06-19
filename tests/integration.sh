#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d /tmp/vassist-test.XXXXXX)"
TEST_HOME="$TEST_DIR/home"
TEST_PROJECT="$TEST_DIR/project"
COMMENT_PROJECT="$TEST_DIR/comment-project"
DEFAULT_PROJECT="$TEST_DIR/default-project"
DOT_PROJECT="$TEST_DIR/dot-project"
ABSOLUTE_PROJECT="$TEST_DIR/absolute-project"
FAKE_BIN="$TEST_DIR/bin"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_HOME" "$TEST_PROJECT" "$COMMENT_PROJECT/.vscode" "$DEFAULT_PROJECT" "$DOT_PROJECT" "$ABSOLUTE_PROJECT" "$FAKE_BIN"
cat > "$FAKE_BIN/code" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$TEST_DIR/code-args"
pwd -P > "$TEST_DIR/code-pwd"
EOF
chmod +x "$FAKE_BIN/code"

export HOME="$TEST_HOME"
export PATH="$FAKE_BIN:$PATH"

"$ROOT_DIR/install.sh"
test -x "$HOME/.local/bin/vassist"
"$HOME/.local/bin/vassist" --help >/dev/null

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
test ! -e "$HOME/.vscode/settings.json"

if SUDO_USER=test-user "$HOME/.local/bin/vassist" status >"$TEST_DIR/sudo-output" 2>&1; then
  echo "Expected sudo-style execution to be refused." >&2
  exit 1
fi
grep -Fq "refuses to run as root or through sudo" "$TEST_DIR/sudo-output"

cd "$TEST_PROJECT"
"$HOME/.local/bin/vassist" doctor | grep -Fq "Doctor result: healthy"
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
test ! -e .vscode/settings.json
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

echo "Isolated install, default/path dispatch, safety, JSONC, mode, open, restore, and guarded-uninstall tests passed."
