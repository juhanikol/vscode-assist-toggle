#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/share/vscode-assist-toggle"
BIN_DIR="$HOME/.local/bin"
WRAPPER="$BIN_DIR/vassist"
BASHRC="$HOME/.bashrc"
PATH_BEGIN="# >>> vassist PATH >>>"
PATH_END="# <<< vassist PATH <<<"
WRAPPER_MARKER="# Managed by vscode-assist-toggle installer"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  cat <<'HELP'
Usage:
  ./install.sh
  ./install.sh --install-deps [--yes]
  ./install.sh --uninstall
HELP
}

remove_path_block() {
  [[ -f "$BASHRC" ]] || return 0
  local begin_count end_count temporary
  begin_count="$(grep -Fxc "$PATH_BEGIN" "$BASHRC" || true)"
  end_count="$(grep -Fxc "$PATH_END" "$BASHRC" || true)"
  if [[ "$begin_count" == "0" && "$end_count" == "0" ]]; then
    return 0
  fi
  if [[ "$begin_count" != "1" || "$end_count" != "1" ]]; then
    echo "Warning: PATH markers in $BASHRC are incomplete or duplicated; .bashrc was not changed." >&2
    return 0
  fi
  temporary="$(mktemp "$HOME/.bashrc.vassist.XXXXXX")"
  awk -v begin="$PATH_BEGIN" -v end="$PATH_END" '
    $0 == begin { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$BASHRC" > "$temporary"
  chmod --reference="$BASHRC" "$temporary" 2>/dev/null || true
  mv "$temporary" "$BASHRC"
}

uninstall_tool() {
  if [[ -e "$WRAPPER" ]]; then
    if [[ -f "$WRAPPER" ]] && grep -Fqx "$WRAPPER_MARKER" "$WRAPPER"; then
      rm -f "$WRAPPER"
    else
      echo "Warning: $WRAPPER is not the installer-owned wrapper; it was not removed." >&2
    fi
  fi
  rm -rf "$INSTALL_DIR"
  remove_path_block
  echo "Removed installed vassist files and the installer-owned PATH block."
  echo "Project-local .vscode/.assist-toggle-backups directories were not removed."
}

install_dependencies() {
  local assume_yes="$1" reply
  cat <<'NOTICE'
--install-deps is intended only for Ubuntu/WSL systems.
It will use sudo to run exactly:
  sudo apt update
  sudo apt install -y python3 make
It will not run apt upgrade.
NOTICE
  if ! command -v sudo >/dev/null 2>&1 || ! command -v apt >/dev/null 2>&1; then
    echo "Error: --install-deps requires Ubuntu/WSL with sudo and apt available." >&2
    exit 1
  fi
  if [[ "$assume_yes" != "true" ]]; then
    read -r -p "Continue? [y/N] " reply || true
    case "${reply:-}" in
      y|Y|yes|YES) ;;
      *) echo "Dependency installation cancelled."; exit 0 ;;
    esac
  fi
  sudo apt update
  sudo apt install -y python3 make
}

case "${1:-}" in
  "") ;;
  --install-deps)
    if [[ $# -eq 1 ]]; then
      install_dependencies "false"
    elif [[ $# -eq 2 && "$2" == "--yes" ]]; then
      install_dependencies "true"
    else
      usage >&2
      exit 1
    fi
    ;;
  --uninstall)
    [[ $# -eq 1 ]] || { usage >&2; exit 1; }
    uninstall_tool
    exit 0
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  cat >&2 <<'ERROR'
Python 3 is required.
Ubuntu/WSL: sudo apt update
Ubuntu/WSL: sudo apt install -y python3
ERROR
  exit 1
fi

if ! command -v make >/dev/null 2>&1; then
  cat <<'NOTICE'
make is optional. It is only used for developer convenience.
Ubuntu/WSL: sudo apt update
Ubuntu/WSL: sudo apt install -y make
NOTICE
fi

if ! command -v code >/dev/null 2>&1; then
  echo "VS Code code command is optional. It is only needed for vassist --open."
fi

mkdir -p "$INSTALL_DIR/scripts" "$BIN_DIR"
cp "$SOURCE_DIR/scripts/vscode-mode.sh" "$INSTALL_DIR/scripts/vscode-mode.sh"
cp "$SOURCE_DIR/scripts/settings-patch.py" "$INSTALL_DIR/scripts/settings-patch.py"
cp "$SOURCE_DIR/README.md" "$INSTALL_DIR/README.md"
cp "$SOURCE_DIR/LICENSE" "$INSTALL_DIR/LICENSE"
cp "$SOURCE_DIR/install.sh" "$INSTALL_DIR/install.sh"
chmod +x "$INSTALL_DIR/scripts/vscode-mode.sh" "$INSTALL_DIR/scripts/settings-patch.py"
chmod +x "$INSTALL_DIR/install.sh"

temporary_wrapper="$(mktemp "$BIN_DIR/.vassist.XXXXXX")"
cat > "$temporary_wrapper" <<'WRAPPER'
#!/usr/bin/env bash
# Managed by vscode-assist-toggle installer
set -euo pipefail
exec "$HOME/.local/share/vscode-assist-toggle/scripts/vscode-mode.sh" "$@"
WRAPPER
chmod +x "$temporary_wrapper"
mv "$temporary_wrapper" "$WRAPPER"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  touch "$BASHRC"
  if grep -Eq '(\$HOME|~)/\.local/bin' "$BASHRC"; then
    echo "$BIN_DIR is already configured in $BASHRC; open a new terminal if needed."
  elif ! grep -Fq "$PATH_BEGIN" "$BASHRC"; then
    temporary="$(mktemp "$HOME/.bashrc.vassist.XXXXXX")"
    cp "$BASHRC" "$temporary"
    cat >> "$temporary" <<'PATH_BLOCK'

# >>> vassist PATH >>>
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
# <<< vassist PATH <<<
PATH_BLOCK
    chmod --reference="$BASHRC" "$temporary" 2>/dev/null || true
    mv "$temporary" "$BASHRC"
    echo "Added $BIN_DIR to PATH in $BASHRC."
    echo "Open a new terminal or run: source ~/.bashrc"
  fi
fi

if [[ ! -x "$WRAPPER" ]] || ! "$WRAPPER" --help >/dev/null 2>&1; then
  echo "Error: installation verification failed for $WRAPPER" >&2
  exit 1
fi

echo "Installed and verified vassist: $WRAPPER"
echo "Tool files: $INSTALL_DIR"
