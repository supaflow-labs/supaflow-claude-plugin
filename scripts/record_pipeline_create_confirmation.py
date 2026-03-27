#!/usr/bin/env python3
import argparse
import json
import os
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Record user-confirmed pipeline create settings for Claude hook enforcement."
    )
    parser.add_argument("--name", required=True, help="Pipeline name")
    parser.add_argument("--source", required=True, help="Source identifier used in --source")
    parser.add_argument("--project", required=True, help="Project identifier used in --project")
    parser.add_argument("--prefix", required=True, help="Destination schema prefix")
    parser.add_argument("--ingestion-mode", required=True, help="Confirmed ingestion_mode")
    parser.add_argument("--load-mode", required=True, help="Confirmed load_mode")
    parser.add_argument(
        "--schema-evolution-mode", required=True, help="Confirmed schema_evolution_mode"
    )
    parser.add_argument(
        "--duplicate-approved",
        choices=["true", "false"],
        default="false",
        help="Whether the user explicitly approved creating a separate pipeline despite duplicates",
    )
    parser.add_argument(
        "--confirmation-text",
        required=True,
        help="Short note capturing the user's confirmation, e.g. 'defaults are fine'",
    )
    args = parser.parse_args()

    plugin_data = os.environ.get("CLAUDE_PLUGIN_DATA")
    if not plugin_data:
        raise SystemExit("CLAUDE_PLUGIN_DATA is not set")

    data_dir = Path(plugin_data)
    data_dir.mkdir(parents=True, exist_ok=True)
    path = data_dir / "pipeline-create-confirmation.json"
    payload = {
        "confirmation_version": 1,
        "created_at_epoch": int(time.time()),
        "pipeline_name": args.name,
        "source_identifier": args.source,
        "project_identifier": args.project,
        "pipeline_prefix": args.prefix,
        "ingestion_mode": args.ingestion_mode,
        "load_mode": args.load_mode,
        "schema_evolution_mode": args.schema_evolution_mode,
        "duplicate_pipeline_approved": args.duplicate_approved == "true",
        "user_confirmation": args.confirmation_text,
    }
    path.write_text(json.dumps(payload, indent=2))
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
