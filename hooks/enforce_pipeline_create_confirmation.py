#!/usr/bin/env python3
import json
import os
import shlex
import sys
import time
from pathlib import Path


MAX_CONFIRMATION_AGE_SECONDS = 60 * 60


def is_pipeline_create_command(command: str) -> bool:
    return "supaflow" in command and "pipelines" in command and "create" in command


def extract_flag(tokens: list[str], flag: str) -> str | None:
    for i, token in enumerate(tokens):
        if token == flag and i + 1 < len(tokens):
            return tokens[i + 1]
    return None


def deny(reason: str) -> None:
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(payload))


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
        deny(
            "Before running `supaflow pipelines create`, ask the user to confirm "
            "pipeline prefix and pipeline settings, then record that confirmation "
            "with `${CLAUDE_PLUGIN_ROOT}/scripts/record_pipeline_create_confirmation.py`."
        )
        return 0

    confirmation_path = Path(plugin_data) / "pipeline-create-confirmation.json"
    if not confirmation_path.exists():
        deny(
            "Blocked: before `supaflow pipelines create`, ask the user to explicitly "
            "confirm destination schema prefix, ingestion mode, load mode, and schema "
            "evolution mode. After the user replies, run "
            "`${CLAUDE_PLUGIN_ROOT}/scripts/record_pipeline_create_confirmation.py` "
            "with the confirmed values, then retry the create command."
        )
        return 0

    try:
        confirmation = json.loads(confirmation_path.read_text())
    except json.JSONDecodeError:
        deny(
            "Blocked: the pipeline confirmation record is unreadable. Re-confirm the "
            "pipeline settings with the user and recreate the confirmation record with "
            "`${CLAUDE_PLUGIN_ROOT}/scripts/record_pipeline_create_confirmation.py`."
        )
        return 0

    required_keys = [
        "pipeline_name",
        "source_identifier",
        "project_identifier",
        "pipeline_prefix",
        "ingestion_mode",
        "load_mode",
        "schema_evolution_mode",
        "user_confirmation",
    ]
    missing = [key for key in required_keys if not confirmation.get(key)]
    if missing:
        deny(
            "Blocked: the pipeline confirmation record is missing required fields: "
            + ", ".join(missing)
            + ". Re-confirm with the user and recreate the record."
        )
        return 0

    if time.time() - confirmation_path.stat().st_mtime > MAX_CONFIRMATION_AGE_SECONDS:
        deny(
            "Blocked: the saved pipeline confirmation is stale. Ask the user to "
            "confirm the pipeline settings again, then recreate the confirmation record."
        )
        return 0

    try:
        tokens = shlex.split(command)
    except ValueError:
        tokens = []

    expected = {
        "--name": confirmation["pipeline_name"],
        "--source": confirmation["source_identifier"],
        "--project": confirmation["project_identifier"],
    }
    mismatches = []
    for flag, expected_value in expected.items():
        actual_value = extract_flag(tokens, flag)
        if actual_value is not None and actual_value != expected_value:
            mismatches.append(f"{flag} expected `{expected_value}` but got `{actual_value}`")

    if mismatches:
        deny(
            "Blocked: the `pipelines create` command does not match the confirmed "
            "settings: " + "; ".join(mismatches)
        )
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
