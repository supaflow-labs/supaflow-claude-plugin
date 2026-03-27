#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path


def is_pipeline_create_command(command: str) -> bool:
    return "supaflow" in command and "pipelines" in command and "create" in command


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0

    command = (
        event.get("tool_input", {}).get("command", "")
        if isinstance(event.get("tool_input"), dict)
        else ""
    )
    if not command or not is_pipeline_create_command(command):
        return 0

    plugin_data = os.environ.get("CLAUDE_PLUGIN_DATA")
    if not plugin_data:
        return 0

    confirmation_path = Path(plugin_data) / "pipeline-create-confirmation.json"
    if confirmation_path.exists():
        confirmation_path.unlink()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
