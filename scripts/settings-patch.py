#!/usr/bin/env python3
"""Safely manage the small set of workspace settings owned by this tool."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any


LEARN_VALUES: dict[str, Any] = {
    "chat.disableAIFeatures": True,
    "github.copilot.enable": {"*": False},
}
STRICT_VALUES: dict[str, Any] = {
    "editor.inlineSuggest.enabled": False,
    "editor.suggestOnTriggerCharacters": False,
    "editor.acceptSuggestionOnEnter": "off",
    "editor.acceptSuggestionOnCommitCharacter": False,
    "editor.tabCompletion": "off",
    "editor.snippetSuggestions": "none",
}
ASSIST_DEFAULTS: dict[str, Any] = {
    "chat.disableAIFeatures": False,
    "github.copilot.enable": {"*": True},
    "editor.inlineSuggest.enabled": True,
    "editor.suggestOnTriggerCharacters": True,
    "editor.acceptSuggestionOnEnter": "on",
    "editor.acceptSuggestionOnCommitCharacter": True,
    "editor.tabCompletion": "off",
    "editor.snippetSuggestions": "inline",
    "editor.quickSuggestions": {
        "other": "on",
        "comments": "off",
        "strings": "off",
    },
}
QUICK_VALUES: dict[str, bool] = {
    "other": False,
    "comments": False,
    "strings": False,
}
STATE_NAME = "original-state.json"
ORIGINAL_JSON_NAME = "original.settings.json"
ORIGINAL_MISSING_NAME = "original.settings.missing"


def find_user_settings() -> Path | None:
    override = os.environ.get("VASSIST_USER_SETTINGS_OVERRIDE")
    if override:
        try:
            path = Path(override).expanduser()
            return path if path.exists() else None
        except OSError:
            return None

    candidates = [
        Path.home() / ".vscode-server" / "data" / "User" / "settings.json",
        Path.home() / ".config" / "Code" / "User" / "settings.json",
    ]
    for path in candidates:
        try:
            if path.exists():
                return path
        except OSError:
            continue

    usernames: list[str] = []
    for value in (os.environ.get("USERNAME"), _windows_username_from_proc_version(), os.environ.get("USER")):
        if value and value not in usernames:
            usernames.append(value)
    for username in usernames:
        path = Path("/mnt/c/Users") / username / "AppData" / "Roaming" / "Code" / "User" / "settings.json"
        try:
            if path.exists():
                return path
        except OSError:
            continue
    return None


def _windows_username_from_proc_version() -> str | None:
    try:
        text = Path("/proc/version").read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None
    marker = "Microsoft@"
    if marker not in text:
        return None
    username = text.split(marker, 1)[1].split(maxsplit=1)[0].split("-", 1)[0].strip()
    return username or None


def strip_jsonc(text: str) -> str:
    """Remove JSONC comments and trailing commas without changing strings."""
    out: list[str] = []
    i = 0
    in_string = False
    escape = False
    while i < len(text):
        char = text[i]
        if in_string:
            out.append(char)
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            i += 1
            continue
        if char == '"':
            in_string = True
            out.append(char)
            i += 1
            continue
        if char == "/" and i + 1 < len(text) and text[i + 1] == "/":
            i += 2
            while i < len(text) and text[i] not in "\r\n":
                i += 1
            continue
        if char == "/" and i + 1 < len(text) and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            if end < 0:
                raise ValueError("unterminated block comment")
            i = end + 2
            continue
        out.append(char)
        i += 1
    if in_string:
        raise ValueError("unterminated string")

    text = "".join(out)
    out = []
    i = 0
    in_string = False
    escape = False
    while i < len(text):
        char = text[i]
        if in_string:
            out.append(char)
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            i += 1
            continue
        if char == '"':
            in_string = True
            out.append(char)
            i += 1
            continue
        if char == ",":
            j = i + 1
            while j < len(text) and text[j].isspace():
                j += 1
            if j < len(text) and text[j] in "}]":
                i += 1
                continue
        out.append(char)
        i += 1
    return "".join(out)


def contains_jsonc_comments(path: Path) -> bool:
    """Return whether a settings file contains // or /* comments outside strings."""
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8")
    i = 0
    in_string = False
    escape = False
    while i < len(text):
        char = text[i]
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            i += 1
            continue
        if char == '"':
            in_string = True
            i += 1
            continue
        if char == "/" and i + 1 < len(text) and text[i + 1] in {"/", "*"}:
            return True
        i += 1
    return False


def warn_about_comment_loss(settings: Path, *, dry_run: bool) -> None:
    if not contains_jsonc_comments(settings):
        return
    prefix = "A real mode change would rewrite" if dry_run else "This mode change will rewrite"
    print(
        f"Warning: {settings} contains JSONC comments. {prefix} the file as JSON and remove those comments.",
        file=sys.stderr,
    )


def read_object(path: Path, *, missing_ok: bool = True) -> dict[str, Any]:
    if not path.exists():
        if missing_ok:
            return {}
        raise ValueError(f"file not found: {path}")
    raw = path.read_text(encoding="utf-8")
    if not raw.strip():
        return {}
    value = json.loads(strip_jsonc(raw))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def atomic_write(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=4, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def atomic_restore(source: Path, destination: Path) -> None:
    """Validate a backup and restore its exact bytes atomically."""
    read_object(source, missing_ok=False)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as handle, source.open("rb") as source_handle:
            shutil.copyfileobj(source_handle, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def backup(settings: Path, backup_dir: Path) -> Path:
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    suffix = "json" if settings.exists() else "missing"
    destination = backup_dir / f"settings.{stamp}.{suffix}"
    if settings.exists():
        read_object(settings)  # Validate before accepting it as a backup source.
        shutil.copy2(settings, destination)
    else:
        destination.touch(exist_ok=False)
    return destination


def history_backups(backup_dir: Path) -> list[Path]:
    return sorted(
        list(backup_dir.glob("settings.*.json")) + list(backup_dir.glob("settings.*.missing")),
        reverse=True,
    )


def capture_state(settings_existed: bool, current: dict[str, Any], mode: str) -> dict[str, Any]:
    state: dict[str, Any] = {
        "version": 3,
        "settings_file_existed": settings_existed,
        "active_mode": mode,
        "simple": {},
    }
    for key in LEARN_VALUES | STRICT_VALUES:
        state["simple"][key] = (
            {"present": True, "value": current[key]}
            if key in current
            else {"present": False}
        )
    quick = current.get("editor.quickSuggestions")
    if isinstance(quick, dict):
        state["quick"] = {
            "kind": "object",
            "container_present": "editor.quickSuggestions" in current,
            "values": {
                key: ({"present": True, "value": quick[key]} if key in quick else {"present": False})
                for key in QUICK_VALUES
            },
        }
    else:
        state["quick"] = {
            "kind": "whole",
            "present": "editor.quickSuggestions" in current,
            **({"value": quick} if "editor.quickSuggestions" in current else {}),
        }
    return state


def save_original(
    settings: Path, backup_dir: Path, current: dict[str, Any], mode: str
) -> tuple[dict[str, Any], Path]:
    """Create the named pre-learning snapshot exactly once."""
    backup_dir.mkdir(parents=True, exist_ok=True)
    original_json = backup_dir / ORIGINAL_JSON_NAME
    original_missing = backup_dir / ORIGINAL_MISSING_NAME

    if original_json.exists() or original_missing.exists():
        raise ValueError(
            "an original/pre-learning backup already exists but its state file is missing; "
            "refusing to overwrite the original backup"
        )

    state = capture_state(settings.exists(), current, mode)
    if settings.exists():
        atomic_restore(settings, original_json)
        original_missing.unlink(missing_ok=True)
        original_path = original_json
    else:
        atomic_write(original_missing, {"settings_file_existed": False})
        original_json.unlink(missing_ok=True)
        original_path = original_missing
    state["original_path"] = str(original_path)
    atomic_write(backup_dir / STATE_NAME, state)
    return state, original_path


def original_source(backup_dir: Path, state: dict[str, Any]) -> Path:
    allowed = {
        backup_dir / ORIGINAL_JSON_NAME,
        backup_dir / ORIGINAL_MISSING_NAME,
    }
    raw_path = state.get("original_path")
    if not isinstance(raw_path, str):
        raise ValueError("the original/pre-learning state is missing its backup path")
    source = Path(raw_path)
    if source not in allowed or not source.exists():
        raise ValueError(f"original/pre-learning backup not found: {source}")
    return source


def restore_source(source: Path, settings: Path) -> None:
    if source.suffix == ".missing":
        settings.unlink(missing_ok=True)
    else:
        atomic_restore(source, settings)


def source_matches_settings(source: Path, settings: Path) -> bool:
    if source.suffix == ".missing":
        return not settings.exists()
    return settings.exists() and source.read_bytes() == settings.read_bytes()


def restore_saved(
    current: dict[str, Any], state: dict[str, Any] | None, keys: set[str], restore_quick: bool
) -> dict[str, Any]:
    result = dict(current)
    if state is None:
        for key in keys:
            result.pop(key, None)
        if restore_quick:
            quick = result.get("editor.quickSuggestions")
            if isinstance(quick, dict):
                quick_result = dict(quick)
                for key in QUICK_VALUES:
                    quick_result.pop(key, None)
                if quick_result:
                    result["editor.quickSuggestions"] = quick_result
                else:
                    result.pop("editor.quickSuggestions", None)
        return result

    for key in keys:
        saved = state.get("simple", {}).get(key, {"present": False})
        if saved.get("present"):
            result[key] = saved.get("value")
        else:
            result.pop(key, None)

    if not restore_quick:
        return result
    saved_quick = state.get("quick", {})
    if saved_quick.get("kind") == "whole":
        if saved_quick.get("present"):
            result["editor.quickSuggestions"] = saved_quick.get("value")
        else:
            result.pop("editor.quickSuggestions", None)
    else:
        quick = result.get("editor.quickSuggestions")
        quick_result = dict(quick) if isinstance(quick, dict) else {}
        for key, saved in saved_quick.get("values", {}).items():
            if saved.get("present"):
                quick_result[key] = saved.get("value")
            else:
                quick_result.pop(key, None)
        if quick_result or saved_quick.get("container_present"):
            result["editor.quickSuggestions"] = quick_result
        else:
            result.pop("editor.quickSuggestions", None)
    return result


def apply_mode(current: dict[str, Any], mode: str, state: dict[str, Any]) -> dict[str, Any]:
    if mode == "assist":
        result = dict(current)
        for key in LEARN_VALUES | STRICT_VALUES:
            result.pop(key, None)
        result.update(ASSIST_DEFAULTS)
        return result
    result = dict(current)
    result.update(LEARN_VALUES)
    if mode == "learn":
        return restore_saved(result, state, set(STRICT_VALUES), True)
    result.update(STRICT_VALUES)
    quick = current.get("editor.quickSuggestions")
    quick_result = dict(quick) if isinstance(quick, dict) else {}
    quick_result.update(QUICK_VALUES)
    result["editor.quickSuggestions"] = quick_result
    return result


def mode_matches(current: dict[str, Any], mode: str, state: dict[str, Any]) -> bool:
    expected = apply_mode(current, mode, state)
    keys = set(LEARN_VALUES) if mode == "learn" else set(LEARN_VALUES | STRICT_VALUES)
    if any(current.get(key) != expected.get(key) or (key in current) != (key in expected) for key in keys):
        return False
    if mode == "strict":
        quick = current.get("editor.quickSuggestions")
        return isinstance(quick, dict) and all(quick.get(key) == value for key, value in QUICK_VALUES.items())
    for key in STRICT_VALUES:
        if current.get(key) != expected.get(key) or (key in current) != (key in expected):
            return False
    return current.get("editor.quickSuggestions") == expected.get("editor.quickSuggestions")


def upgrade_state(state: dict[str, Any], backup_dir: Path, current: dict[str, Any]) -> dict[str, Any]:
    if state.get("version") == 3:
        return state
    source = original_source(backup_dir, state)
    original = {} if source.suffix == ".missing" else read_object(source, missing_ok=False)
    legacy_active = bool(state.get("learning_active"))
    upgraded = capture_state(bool(state.get("settings_file_existed")), original, "strict" if legacy_active else "assist")
    upgraded["active_mode"] = "strict" if legacy_active else None
    upgraded["original_path"] = str(source)
    return upgraded


def select_history_backup(backup_dir: Path, requested: str) -> Path:
    candidates = history_backups(backup_dir)
    if not candidates:
        raise ValueError(f"no safety/history backups found in {backup_dir}")
    if requested == "latest":
        return candidates[0]
    if Path(requested).name != requested:
        raise ValueError("history backup must be a filename shown by the backups command")
    selected = backup_dir / requested
    if selected not in candidates:
        raise ValueError(f"safety/history backup not found: {requested}")
    return selected


def display_path(path: Path) -> str:
    try:
        resolved = path.expanduser().resolve()
        home = Path.home().resolve()
        if resolved == home:
            return "~"
        if resolved.is_relative_to(home):
            return "~/" + str(resolved.relative_to(home))
        return str(resolved)
    except OSError:
        return str(path)


def json_value(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False)


def doctor_settings(settings: Path, backup_dir: Path, *, fix: bool) -> int:
    current = read_object(settings)
    state_path = backup_dir / STATE_NAME
    state = read_object(state_path, missing_ok=False) if state_path.exists() else None
    if state is not None:
        state = upgrade_state(state, backup_dir, current)
    if fix and state is not None and state.get("active_mode") in {"learn", "strict"}:
        print("Error: run vassist assist first before applying preference fixes.", file=sys.stderr)
        return 1

    user_settings_path = find_user_settings()
    if user_settings_path is None:
        print("User settings: none found")
        print("[OK] Workspace settings match your global preferences for all managed keys.")
        return 0

    user_settings = read_object(user_settings_path)
    user_path_label = display_path(user_settings_path)
    print(f"User settings: {user_path_label}")
    mismatches: list[tuple[str, Any, Any]] = []
    for key in ASSIST_DEFAULTS:
        if key in current and key in user_settings and current[key] != user_settings[key]:
            mismatches.append((key, current[key], user_settings[key]))

    if not mismatches:
        print("[OK] Workspace settings match your global preferences for all managed keys.")
        return 0

    for key, workspace_value, user_value in mismatches:
        print(f"  [MISMATCH] {key}")
        print(f"    workspace:       {json_value(workspace_value)}    (vassist default)")
        print(f"    your preference: {json_value(user_value)}   (from {user_path_label})")
        print(f"    Suggested fix:   set {json_value(key)}: {json_value(user_value)} in workspace settings")

    if not fix:
        return 0

    applied = 0
    updated = dict(current)
    for key, _workspace_value, user_value in mismatches:
        print(f"Fix: {key}")
        answer = input("Apply fix? [y/N] ")
        if answer.lower() == "y":
            updated[key] = user_value
            applied += 1
    if applied:
        atomic_write(settings, updated)
    print(f"Applied {applied} preference fix(es).")
    print("Run Developer: Reload Window if changes do not apply.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Manage project-local VS Code learning settings.")
    parser.add_argument("command", choices=("learn", "strict", "assist", "status", "doctor", "backup", "backups", "restore"))
    parser.add_argument("settings_file", type=Path)
    parser.add_argument("backup_dir", type=Path)
    parser.add_argument("history_backup", nargs="?")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--fix", action="store_true")
    args = parser.parse_args()
    state_path = args.backup_dir / STATE_NAME

    try:
        expected_settings = Path.cwd().absolute() / ".vscode" / "settings.json"
        expected_backups = Path.cwd().absolute() / ".vscode" / ".assist-toggle-backups"
        if args.settings_file.absolute() != expected_settings or args.backup_dir.absolute() != expected_backups:
            raise ValueError("this helper may only manage the current project's .vscode/settings.json")
        vscode_dir = expected_settings.parent
        if vscode_dir.is_symlink() or args.settings_file.is_symlink() or args.backup_dir.is_symlink():
            raise ValueError("refusing to use symlinked VS Code settings or backup paths")

        if args.command == "backups":
            state = read_object(state_path, missing_ok=False) if state_path.exists() else None
            print("Original/pre-learning backup:")
            if state is None:
                print("  none")
            else:
                source = original_source(args.backup_dir, state)
                original_kind = "present" if state.get("settings_file_existed") else "missing"
                print(f"  settings file was {original_kind}")
                print(f"  {source}")
            candidates = history_backups(args.backup_dir)
            print("Safety/history backups (restore explicitly by filename):")
            if not candidates:
                print("  none")
            else:
                for path in candidates:
                    print(f"  {path}")
            return 0

        current = read_object(args.settings_file)
        if args.command == "doctor":
            return doctor_settings(args.settings_file, args.backup_dir, fix=args.fix)

        if args.command == "status":
            state = read_object(state_path, missing_ok=False) if state_path.exists() else None
            if state is not None:
                state = upgrade_state(state, args.backup_dir, current)
            active_mode = state.get("active_mode") if state else None
            if active_mode in {"learn", "strict"} and mode_matches(current, active_mode, state):
                mode_label = active_mode.capitalize()
            elif active_mode in {"learn", "strict"}:
                mode_label = f"Modified/unknown (expected {active_mode})"
            else:
                mode_label = "Assist/default"
            print(f"Current mode: {mode_label}")
            if mode_label == "Learn":
                print("Effect: AI assistance is disabled; normal language-server IntelliSense is preserved.")
            elif mode_label == "Strict":
                print("Effect: AI is disabled and normal editor completion assistance is reduced.")
            elif mode_label == "Assist/default":
                print("Effect: no vassist learning mode is active; managed settings are restored/defaulted; AI assistance defaults are written to settings.json")
            else:
                print("Effect: managed settings no longer match the saved active mode.")
            settings_kind = "present" if args.settings_file.exists() else "missing"
            print(f"Workspace settings file: {settings_kind} ({args.settings_file})")
            print(f"Original/pre-learning state exists: {'yes' if state is not None else 'no'}")
            if state is None:
                print("Original settings file: unknown")
                print("Original/pre-learning path: none")
            else:
                source = original_source(args.backup_dir, state)
                original_kind = "present" if state.get("settings_file_existed") else "missing"
                print(f"Original settings file: {original_kind}")
                print(f"Original/pre-learning path: {source}")
            print(f"Safety/history backups: {len(history_backups(args.backup_dir))} ({args.backup_dir})")
            return 0

        if args.command == "backup":
            print(f"Backup created: {backup(args.settings_file, args.backup_dir)}")
            return 0

        if args.command == "restore":
            state = read_object(state_path, missing_ok=False) if state_path.exists() else None
            if state is not None:
                state = upgrade_state(state, args.backup_dir, current)
            if args.history_backup:
                source = select_history_backup(args.backup_dir, args.history_backup)
            else:
                if state is None:
                    raise ValueError("no original/pre-learning state exists; use backups to inspect history")
                source = original_source(args.backup_dir, state)
            if source_matches_settings(source, args.settings_file):
                if state is not None:
                    if args.history_backup and mode_matches(current, "strict", state):
                        state["active_mode"] = "strict"
                    elif args.history_backup and mode_matches(current, "learn", state):
                        state["active_mode"] = "learn"
                    else:
                        state["active_mode"] = None
                    atomic_write(state_path, state)
                if args.history_backup:
                    print(f"History backup already active: {source.name}")
                else:
                    print("Already restored to original/pre-learning state")
                return 0
            safety = backup(args.settings_file, args.backup_dir)
            restore_source(source, args.settings_file)
            if state is not None:
                restored = read_object(args.settings_file)
                if args.history_backup and mode_matches(restored, "strict", state):
                    state["active_mode"] = "strict"
                elif args.history_backup and mode_matches(restored, "learn", state):
                    state["active_mode"] = "learn"
                else:
                    state["active_mode"] = None
                atomic_write(state_path, state)
            print(f"Safety backup created: {safety}")
            label = "history" if args.history_backup else "original/pre-learning state"
            print(f"Restored {label}: {source}")
            return 0

        if args.command in {"learn", "strict"}:
            requested_mode = args.command
            state = read_object(state_path, missing_ok=False) if state_path.exists() else None
            if state is not None:
                state = upgrade_state(state, args.backup_dir, current)
            preview_state = state or capture_state(args.settings_file.exists(), current, requested_mode)
            updated = apply_mode(current, requested_mode, preview_state)
            if args.dry_run:
                warn_about_comment_loss(args.settings_file, dry_run=True)
                print(json.dumps(updated, indent=4, ensure_ascii=False))
                return 0
            if state is None:
                state, original_path = save_original(
                    args.settings_file, args.backup_dir, current, requested_mode
                )
                saved_message = f"Original/pre-learning state saved: {original_path}"
                updated = apply_mode(current, requested_mode, state)
                if updated == current:
                    print(saved_message)
                    print(f"Mode already active: {requested_mode}")
                    return 0
            elif updated == current:
                if state.get("active_mode") != requested_mode:
                    state["active_mode"] = requested_mode
                    atomic_write(state_path, state)
                print(f"Mode already active: {requested_mode}")
                return 0
            else:
                saved = backup(args.settings_file, args.backup_dir)
                saved_message = f"Safety/history backup created: {saved}"
                state["active_mode"] = requested_mode
                atomic_write(state_path, state)
            warn_about_comment_loss(args.settings_file, dry_run=False)
            updated = apply_mode(current, requested_mode, state)
            atomic_write(args.settings_file, updated)
            print(saved_message)
            print(f"Updated: {args.settings_file}")
            return 0

        state = read_object(state_path, missing_ok=False) if state_path.exists() else None
        if state is not None:
            state = upgrade_state(state, args.backup_dir, current)
        updated = apply_mode(current, "assist", state or capture_state(args.settings_file.exists(), current, "assist"))
        if args.dry_run:
            warn_about_comment_loss(args.settings_file, dry_run=True)
            print(json.dumps(updated, indent=4, ensure_ascii=False))
            return 0
        if updated == current:
            if state is not None and state.get("active_mode") is not None:
                state["active_mode"] = None
                atomic_write(state_path, state)
            print("Already restored to original/pre-learning state")
            return 0
        warn_about_comment_loss(args.settings_file, dry_run=False)
        saved = backup(args.settings_file, args.backup_dir)
        if state is not None:
            if updated or state.get("settings_file_existed"):
                atomic_write(args.settings_file, updated)
            else:
                args.settings_file.unlink(missing_ok=True)
            state["active_mode"] = None
            atomic_write(state_path, state)
            print("Restored managed settings from the original/pre-learning state.")
        else:
            if updated:
                atomic_write(args.settings_file, updated)
            else:
                args.settings_file.unlink(missing_ok=True)
            print("No original state existed; removed only settings managed by this tool.")
        print(f"Safety/history backup created: {saved}")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
