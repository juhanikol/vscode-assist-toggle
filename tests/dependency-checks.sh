#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d /tmp/vassist-deps.XXXXXX)"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

grep -Fq 'Continue? [y/N]' "$ROOT_DIR/install.sh"
grep -Fq 'sudo apt update' "$ROOT_DIR/install.sh"
grep -Fq 'sudo apt install -y python3 make' "$ROOT_DIR/install.sh"
if grep -Eq 'sudo apt( |-)upgrade' "$ROOT_DIR/install.sh"; then
  echo "install.sh must never run sudo apt upgrade." >&2
  exit 1
fi

mkdir -p "$TEST_DIR/no-python" "$TEST_DIR/old-python" "$TEST_DIR/optional-only" "$TEST_DIR/home-required" "$TEST_DIR/home-old" "$TEST_DIR/home-optional"
ln -s "$(command -v dirname)" "$TEST_DIR/no-python/dirname"
ln -s "$(command -v cat)" "$TEST_DIR/no-python/cat"

if HOME="$TEST_DIR/home-required" PATH="$TEST_DIR/no-python" /bin/bash "$ROOT_DIR/install.sh" >"$TEST_DIR/required-output" 2>&1; then
  echo "Expected installation without python3 to fail." >&2
  exit 1
fi
grep -Fq "Python 3.9 or newer is required." "$TEST_DIR/required-output"
grep -Fq "Ubuntu/WSL: sudo apt update" "$TEST_DIR/required-output"
grep -Fq "Ubuntu/WSL: sudo apt install -y python3" "$TEST_DIR/required-output"

ln -s "$(command -v dirname)" "$TEST_DIR/old-python/dirname"
ln -s "$(command -v cat)" "$TEST_DIR/old-python/cat"
cat > "$TEST_DIR/old-python/python3" <<'PYTHON'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
  echo "Python 3.8.0"
  exit 0
fi
exit 1
PYTHON
chmod +x "$TEST_DIR/old-python/python3"
if HOME="$TEST_DIR/home-old" PATH="$TEST_DIR/old-python" /bin/bash "$ROOT_DIR/install.sh" >"$TEST_DIR/old-output" 2>&1; then
  echo "Expected installation with Python 3.8 to fail." >&2
  exit 1
fi
grep -Fq "Python 3.9 or newer is required. Found: Python 3.8.0" "$TEST_DIR/old-output"

for command_name in dirname cat mkdir cp chmod mktemp mv touch grep env bash python3; do
  command_path="$(command -v "$command_name")"
  ln -s "$command_path" "$TEST_DIR/optional-only/$command_name"
done

HOME="$TEST_DIR/home-optional" PATH="$TEST_DIR/optional-only" /bin/bash "$ROOT_DIR/install.sh" >"$TEST_DIR/optional-output" 2>&1
grep -Fq "make is optional. It is only used for developer convenience." "$TEST_DIR/optional-output"
grep -Fq "Ubuntu/WSL: sudo apt install -y make" "$TEST_DIR/optional-output"
grep -Fq "VS Code code command is optional. It is only needed for vassist --open." "$TEST_DIR/optional-output"
test -x "$TEST_DIR/home-optional/.local/bin/vassist"

echo "Required/minimum-version and optional dependency-message tests passed."
