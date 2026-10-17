"""Install one project-local Maie hook without changing unrelated settings."""
import argparse
import copy
import json
import os
from pathlib import Path
import shlex
import tempfile

HELPER = Path(__file__).resolve().parent / ".build" / "maie-hook"
MAX_SETTINGS_BYTES = 1_000_000


def configure(project, helper=HELPER, apply=False):
    project = Path(project).expanduser().resolve()
    helper = Path(helper).resolve()
    if not project.is_dir():
        raise ValueError("The target project must be an existing directory.")
    if not helper.is_file() or not os.access(helper, os.X_OK):
        raise ValueError("Build Maie first; the executable hook helper is missing.")
    folder = project / ".claude"
    settings = folder / "settings.local.json"
    if folder.is_symlink() or settings.is_symlink():
        raise ValueError("Refusing to replace linked Claude settings.")
    if settings.exists() and not settings.is_file():
        raise ValueError("Claude settings must be a regular JSON file.")
    original = None
    if settings.exists():
        with settings.open("rb") as handle:
            original = handle.read(MAX_SETTINGS_BYTES + 1)
        if len(original) > MAX_SETTINGS_BYTES:
            raise ValueError("Claude settings exceed the setup size limit.")
    data = {} if original is None else json.loads(original)
    if not isinstance(data, dict):
        raise ValueError("Claude settings must contain a JSON object.")
    before = copy.deepcopy(data)
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("The hooks setting must be an object.")
    handlers = hooks.setdefault("PreToolUse", [])
    if not isinstance(handlers, list):
        raise ValueError("PreToolUse must be a list.")
    command = shlex.quote(str(helper))
    matches = []
    for handler in handlers:
        if not isinstance(handler, dict) or not isinstance(handler.get("hooks", []), list):
            raise ValueError("Unexpected hook structure; settings were not changed.")
        for hook in handler.get("hooks", []):
            if not isinstance(hook, dict):
                raise ValueError("Unexpected hook structure; settings were not changed.")
            candidate = hook.get("command", "")
            if not isinstance(candidate, str):
                raise ValueError("Unexpected hook command; settings were not changed.")
            if candidate in (str(helper), command):
                if handler.get("matcher") != "AskUserQuestion":
                    raise ValueError("An existing Maie helper has a different matcher. Review it manually.")
                matches.append(hook)
            else:
                try:
                    words = shlex.split(candidate)
                except ValueError:
                    words = []
                if words and Path(words[0]).name == "maie-hook":
                    raise ValueError("Another Maie installation is configured. Review that hook before installing.")
    if len(matches) > 1:
        raise ValueError("Duplicate Maie hooks found. Review them before installing.")
    desired = {"type": "command", "command": command, "timeout": 1830, "onFailure": "block"}
    if matches:
        if matches[0].get("async") or matches[0].get("asyncRewake") or matches[0].get("if") or matches[0].get("once"):
            raise ValueError("Maie needs a synchronous hook for every matching question. Review the existing hook.")
        matches[0].update(desired)
    else:
        handlers.append({"matcher": "AskUserQuestion", "hooks": [desired]})
    if data == before:
        return False
    if len((json.dumps(data, indent=2, ensure_ascii=True) + "\n").encode()) > MAX_SETTINGS_BYTES:
        raise ValueError("The updated settings would exceed the setup size limit.")
    if apply:
        folder.mkdir(mode=0o700, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=folder,
                                             prefix=".maie-settings-", delete=False) as handle:
                temporary = Path(handle.name)
                json.dump(data, handle, indent=2, ensure_ascii=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            if folder.is_symlink() or settings.is_symlink():
                raise ValueError("Claude settings changed during setup; retry after reviewing them.")
            current = settings.read_bytes() if settings.exists() else None
            if current != original:
                raise ValueError("Claude settings changed during setup; retry after reviewing them.")
            temporary.replace(settings)
        finally:
            if temporary is not None and temporary.exists():
                temporary.unlink()
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, type=Path, help="The Claude Code project directory")
    parser.add_argument("--apply", action="store_true", help="Write settings; otherwise preview only")
    args = parser.parse_args()
    try:
        changed = configure(args.project, apply=args.apply)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Setup stopped: {error}\n")
    if not changed:
        print("This Maie hook is already configured.")
    elif args.apply:
        print("Maie hook installed. Keep Maie open and start a fresh local Claude Code session.")
    else:
        print("Would install one AskUserQuestion hook with a 1,830-second timeout and onFailure=block.")
        print("Unrelated settings are preserved. Add --apply to write the project-local configuration.")


if __name__ == "__main__":
    main()
