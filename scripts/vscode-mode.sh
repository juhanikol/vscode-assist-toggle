#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Usage:
  ./scripts/vscode-mode.sh learn [--dry-run]
  ./scripts/vscode-mode.sh learn [--open]
  ./scripts/vscode-mode.sh strict [--dry-run]
  ./scripts/vscode-mode.sh strict [--open]
  ./scripts/vscode-mode.sh assist [--dry-run]
  ./scripts/vscode-mode.sh assist [--open]
  ./scripts/vscode-mode.sh status
  ./scripts/vscode-mode.sh doctor
  ./scripts/vscode-mode.sh restore
  ./scripts/vscode-mode.sh restore latest
  ./scripts/vscode-mode.sh restore <history-backup-filename>
  ./scripts/vscode-mode.sh backup
  ./scripts/vscode-mode.sh backups

Only .vscode/settings.json under the current working directory is managed.
HELP
}

COMMAND="${1:-}"
case "$COMMAND" in
  learn|strict|assist|status|doctor|restore|backup|backups) shift ;;
  -h|--help|"") usage; exit 0 ;;
  *) echo "Unknown command: $COMMAND" >&2; usage >&2; exit 1 ;;
esac

EXTRA_ARGS=()
OPEN_AFTER="false"
DRY_RUN="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      if [[ "$COMMAND" != "learn" && "$COMMAND" != "strict" && "$COMMAND" != "assist" ]]; then
        echo "--dry-run is not supported for $COMMAND" >&2
        exit 1
      fi
      EXTRA_ARGS+=("--dry-run")
      DRY_RUN="true"
      ;;
    --open)
      if [[ "$COMMAND" != "learn" && "$COMMAND" != "strict" && "$COMMAND" != "assist" ]]; then
        echo "--open is not supported for $COMMAND" >&2
        exit 1
      fi
      OPEN_AFTER="true"
      ;;
    *)
      if [[ "$COMMAND" == "restore" && ${#EXTRA_ARGS[@]} -eq 0 ]]; then
        EXTRA_ARGS+=("$1")
      else
        echo "Unknown option for $COMMAND: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ "$OPEN_AFTER" == "true" && "$DRY_RUN" == "true" ]]; then
  echo "Error: --open and --dry-run cannot be used together." >&2
  exit 1
fi

if [[ "$OPEN_AFTER" == "true" ]] && ! command -v code >/dev/null 2>&1; then
  echo "Error: VS Code command 'code' was not found in PATH; mode was not changed." >&2
  exit 1
fi

PROJECT_ROOT="$(pwd -P)"
SETTINGS_FILE="$PROJECT_ROOT/.vscode/settings.json"
BACKUP_DIR="$PROJECT_ROOT/.vscode/.assist-toggle-backups"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ "$COMMAND" == "doctor" ]]; then
  failures=0
  echo "vassist doctor"
  echo "Workspace: $PROJECT_ROOT"
  echo "Settings:  $SETTINGS_FILE"

  if command -v python3 >/dev/null 2>&1; then
    echo "[OK] Python: $(python3 --version 2>&1)"
    if validation_output="$(python3 "$SCRIPT_DIR/settings-patch.py" status "$SETTINGS_FILE" "$BACKUP_DIR" 2>&1)"; then
      echo "[OK] Workspace settings and saved state are valid."
    else
      echo "[ERROR] Workspace validation failed:"
      printf '%s\n' "$validation_output" | sed 's/^/  /'
      failures=$((failures + 1))
    fi
  else
    echo "[ERROR] Python 3 is required."
    echo "        Ubuntu/WSL: sudo apt update"
    echo "        Ubuntu/WSL: sudo apt install -y python3"
    failures=$((failures + 1))
  fi

  if command -v vassist >/dev/null 2>&1; then
    echo "[OK] vassist command: $(command -v vassist)"
  else
    echo "[INFO] vassist is not on PATH; this script can still be run directly."
  fi
  if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    echo "[OK] ~/.local/bin is on PATH."
  else
    echo "[INFO] ~/.local/bin is not on the current PATH."
  fi
  if command -v code >/dev/null 2>&1; then
    echo "[OK] VS Code code command: $(command -v code)"
  else
    echo "[INFO] VS Code code command is missing; only --open requires it."
  fi
  if command -v make >/dev/null 2>&1; then
    echo "[OK] make is available (optional)."
  else
    echo "[INFO] make is not installed; it is optional."
  fi

  if [[ "$failures" -eq 0 ]]; then
    echo "Doctor result: healthy"
  else
    echo "Doctor result: $failures required issue(s) found"
    exit 1
  fi
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  cat >&2 <<'ERROR'
Error: Python 3 is required to update VS Code settings safely.
Python lets this tool validate settings.json files that contain VS Code comments.
Install Python 3, then run the command again.
On Ubuntu/WSL: sudo apt install python3
ERROR
  exit 1
fi

python3 "$SCRIPT_DIR/settings-patch.py" \
  "$COMMAND" "$SETTINGS_FILE" "$BACKUP_DIR" "${EXTRA_ARGS[@]}"

if [[ "$COMMAND" == "learn" || "$COMMAND" == "strict" || "$COMMAND" == "assist" || "$COMMAND" == "restore" ]]; then
  echo "Run Developer: Reload Window if changes do not apply."
fi

if [[ "$OPEN_AFTER" == "true" ]]; then
  code .
fi
