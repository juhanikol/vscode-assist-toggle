#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d /tmp/vassist-test.XXXXXX)"
TEST_HOME="$TEST_DIR/home"
TEST_PROJECT="$TEST_DIR/project"
COMMENT_PROJECT="$TEST_DIR/comment-project"
FAKE_BIN="$TEST_DIR/bin"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_HOME" "$TEST_PROJECT" "$COMMENT_PROJECT/.vscode" "$FAKE_BIN"
cat > "$FAKE_BIN/code" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$TEST_DIR/code-args"
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
! grep -Fq "This comment should trigger" .vscode/settings.json
"$HOME/.local/bin/vassist" restore >/dev/null
grep -Fq "This comment should trigger" .vscode/settings.json

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

echo "Isolated install, JSONC warning, mode, open, restore, and guarded-uninstall tests passed."
