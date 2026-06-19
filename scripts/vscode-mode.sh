#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
VERSION_FILE="$SCRIPT_DIR/../VERSION"
ISSUES_URL="https://github.com/juhanikol/vscode-assist-toggle/issues"
VERSION="unknown"
if [[ -r "$VERSION_FILE" ]]; then
  IFS= read -r VERSION < "$VERSION_FILE" || true
fi

usage() {
  cat <<'HELP'
Usage:
  vassist                         Apply learn mode here and open VS Code
  vassist .                       Apply learn mode here and open VS Code
  vassist /path/to/project        Apply learn mode there and open VS Code
  vassist learn [--open] [PATH]
  vassist strict [--open] [PATH]
  vassist assist [--open] [PATH]
  vassist status | doctor | backup | backups
  vassist restore [latest|history-backup-filename]
  vassist --version
  vassist --help

Use --force only to confirm an intentionally selected protected directory.
Only TARGET/.vscode/settings.json and project-local backup/state/lock paths are managed.
HELP
  echo "Report issues: $ISSUES_URL"
}

EXTRA_ARGS=()
OPEN_AFTER="false"
DRY_RUN="false"
FORCE="false"
TARGET_ARG="."
TARGET_SET="false"

if [[ $# -eq 0 ]]; then
  COMMAND="learn"
  OPEN_AFTER="true"
else
  case "$1" in
    learn|strict|assist|status|doctor|restore|backup|backups)
      COMMAND="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -V|--version)
      printf 'vassist %s\n' "$VERSION"
      exit 0
      ;;
    --force)
      COMMAND="learn"
      OPEN_AFTER="true"
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      COMMAND="learn"
      OPEN_AFTER="true"
      TARGET_ARG="$1"
      TARGET_SET="true"
      shift
      ;;
  esac
fi

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
    --force)
      FORCE="true"
      ;;
    *)
      if [[ "$COMMAND" == "restore" && ${#EXTRA_ARGS[@]} -eq 0 && "$1" != -* ]]; then
        EXTRA_ARGS+=("$1")
      elif [[ ( "$COMMAND" == "learn" || "$COMMAND" == "strict" || "$COMMAND" == "assist" ) && "$TARGET_SET" == "false" && "$1" != -* ]]; then
        TARGET_ARG="$1"
        TARGET_SET="true"
      else
        echo "Unknown option for $COMMAND: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ "${EUID:-$(id -u)}" -eq 0 || -n "${SUDO_USER:-}" || -n "${SUDO_UID:-}" ]]; then
  echo "Error: vassist refuses to run as root or through sudo." >&2
  exit 1
fi

if [[ "$OPEN_AFTER" == "true" && "$DRY_RUN" == "true" ]]; then
  echo "Error: --open and --dry-run cannot be used together." >&2
  exit 1
fi

if [[ "$COMMAND" == "learn" || "$COMMAND" == "strict" || "$COMMAND" == "assist" ]]; then
  if [[ ! -d "$TARGET_ARG" ]]; then
    echo "Error: project directory does not exist: $TARGET_ARG" >&2
    exit 1
  fi
  PROJECT_ROOT="$(cd -- "$TARGET_ARG" && pwd -P)"
else
  PROJECT_ROOT="$(pwd -P)"
fi

HOME_ROOT="$(cd -- "$HOME" && pwd -P)"
INSTALLED_TOOL="$HOME_ROOT/.local/share/vscode-assist-toggle"
WINDOWS_USER_ROOT=""
if [[ -n "${USERNAME:-}" ]]; then
  WINDOWS_USER_ROOT="/mnt/c/Users/$USERNAME"
fi

is_dangerous_directory() {
  local path="$1"
  [[ "$path" == "/" || "$path" == "$HOME_ROOT" ]] && return 0
  [[ "$path" == "$INSTALLED_TOOL" || "$path" == "$INSTALLED_TOOL/"* ]] && return 0
  [[ -n "$WINDOWS_USER_ROOT" && "$path" == "$WINDOWS_USER_ROOT" ]] && return 0
  case "$path" in
    /etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/var|/var/*|/opt|/opt/*|/boot|/boot/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*)
      return 0
      ;;
    /mnt/c|/mnt/c/Windows|/mnt/c/Windows/*|"/mnt/c/Program Files"|"/mnt/c/Program Files/"*|"/mnt/c/Program Files (x86)"|"/mnt/c/Program Files (x86)/"*)
      return 0
      ;;
  esac
  return 1
}

if is_dangerous_directory "$PROJECT_ROOT" && [[ "$FORCE" != "true" ]]; then
  echo "Error: refusing potentially dangerous project directory: $PROJECT_ROOT" >&2
  echo "Run again with --force only if this directory is intentional." >&2
  exit 1
fi

if [[ "$COMMAND" == "learn" || "$COMMAND" == "strict" || "$COMMAND" == "assist" ]]; then
  if [[ ! -e "$PROJECT_ROOT/.git" && ! -e "$PROJECT_ROOT/.vscode" && ! -e "$PROJECT_ROOT/go.mod" && ! -e "$PROJECT_ROOT/package.json" && ! -e "$PROJECT_ROOT/pyproject.toml" && ! -e "$PROJECT_ROOT/Cargo.toml" && ! -e "$PROJECT_ROOT/Makefile" ]]; then
    echo "Using this folder as the project because you ran vassist here."
  fi
fi

cd -- "$PROJECT_ROOT"
SETTINGS_FILE="$PROJECT_ROOT/.vscode/settings.json"
BACKUP_DIR="$PROJECT_ROOT/.vscode/.assist-toggle-backups"

if [[ "$OPEN_AFTER" == "true" ]] && ! command -v code >/dev/null 2>&1; then
  echo "Error: VS Code command 'code' was not found in PATH; mode was not changed." >&2
  exit 1
fi

LOCK_DIR="$PROJECT_ROOT/.vscode/.assist-toggle.lockdir"
LOCK_HELD="false"

release_lock() {
  if [[ "$LOCK_HELD" == "true" ]]; then
    rm -f "$LOCK_DIR/pid" "$LOCK_DIR/timestamp"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    LOCK_HELD="false"
  fi
}

if [[ "$DRY_RUN" != "true" && ( "$COMMAND" == "learn" || "$COMMAND" == "strict" || "$COMMAND" == "assist" || "$COMMAND" == "restore" || "$COMMAND" == "backup" ) ]]; then
  mkdir -p "$PROJECT_ROOT/.vscode"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Another vassist process is already modifying this project. Try again in a moment." >&2
    exit 1
  fi
  LOCK_HELD="true"
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  date -u +'%Y-%m-%dT%H:%M:%SZ' > "$LOCK_DIR/timestamp"
  trap release_lock EXIT
fi

if [[ "$COMMAND" == "doctor" ]]; then
  failures=0
  echo "vassist doctor"
  echo "Workspace: $PROJECT_ROOT"
  echo "Settings:  $SETTINGS_FILE"

  if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)'; then
    echo "[OK] Python 3.9+: $(python3 --version 2>&1)"
    if validation_output="$(python3 "$SCRIPT_DIR/settings-patch.py" status "$SETTINGS_FILE" "$BACKUP_DIR" 2>&1)"; then
      echo "[OK] Workspace settings and saved state are valid."
    else
      echo "[ERROR] Workspace validation failed:"
      printf '%s\n' "$validation_output" | sed 's/^/  /'
      failures=$((failures + 1))
    fi
  elif command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] Python 3.9 or newer is required. Found: $(python3 --version 2>&1)"
    failures=$((failures + 1))
  else
    echo "[ERROR] Python 3.9 or newer is required."
    echo "        Ubuntu/WSL: sudo apt update"
    echo "        Ubuntu/WSL: sudo apt install -y python3"
    failures=$((failures + 1))
  fi

  if [[ -d "$LOCK_DIR" ]]; then
    lock_pid=""
    lock_timestamp=""
    if [[ -r "$LOCK_DIR/pid" ]]; then
      IFS= read -r lock_pid < "$LOCK_DIR/pid" || true
    fi
    if [[ -r "$LOCK_DIR/timestamp" ]]; then
      IFS= read -r lock_timestamp < "$LOCK_DIR/timestamp" || true
    fi
    if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
      echo "[INFO] Active project lock: $LOCK_DIR (PID $lock_pid, ${lock_timestamp:-timestamp unknown})"
    else
      echo "[ERROR] Stale project lock detected: $LOCK_DIR"
      echo "        PID: ${lock_pid:-unknown}; timestamp: ${lock_timestamp:-unknown}"
      echo "        After confirming no vassist process is running, remove it manually:"
      echo "        rm -rf -- '$LOCK_DIR'"
      failures=$((failures + 1))
    fi
  else
    echo "[OK] No project lock is present."
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
  echo "Report issues: $ISSUES_URL"

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
Error: Python 3.9 or newer is required to update VS Code settings safely.
Python lets this tool validate settings.json files that contain VS Code comments.
Install Python 3, then run the command again.
On Ubuntu/WSL: sudo apt install python3
ERROR
  exit 1
fi

if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)'; then
  echo "Error: Python 3.9 or newer is required. Found: $(python3 --version 2>&1)" >&2
  exit 1
fi

python3 "$SCRIPT_DIR/settings-patch.py" \
  "$COMMAND" "$SETTINGS_FILE" "$BACKUP_DIR" "${EXTRA_ARGS[@]}"

release_lock
trap - EXIT

if [[ "$COMMAND" == "learn" || "$COMMAND" == "strict" || "$COMMAND" == "assist" || "$COMMAND" == "restore" ]]; then
  echo "Run Developer: Reload Window if changes do not apply."
fi

if [[ "$OPEN_AFTER" == "true" ]]; then
  code .
fi
