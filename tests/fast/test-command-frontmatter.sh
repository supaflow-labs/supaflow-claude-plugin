#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

echo "Testing command frontmatter..."

FORBIDDEN_TOOLS=("Agent" "WebFetch" "WebSearch")

# Real YAML-parse guard. The get_frontmatter_field extractor below is lax and
# does NOT catch YAML errors -- e.g. an unquoted "[a] [b]" parses as a broken
# flow sequence and silently drops ALL frontmatter at runtime. Best-effort:
# only assert when PyYAML is available so CI without it doesn't hard-fail.
HAS_PYYAML=$(python3 -c "import yaml" 2>/dev/null && echo yes || echo no)

for cmd_file in "$PLUGIN_ROOT/commands"/*.md; do
    cmd_name="$(basename "$cmd_file")"

    fm_check=$(has_frontmatter "$cmd_file" && echo "has_frontmatter" || echo "no_frontmatter")
    assert_contains "$fm_check" "^has_frontmatter$" "$cmd_name has YAML frontmatter"

    desc_val=$(get_frontmatter_field "$cmd_file" "description")
    desc_check=$([ -n "$desc_val" ] && echo "has_description" || echo "no_description")
    assert_contains "$desc_check" "^has_description$" "$cmd_name has description field"

    tools_val=$(get_frontmatter_field "$cmd_file" "allowed-tools")
    tools_check=$([ -n "$tools_val" ] && echo "has_allowed_tools" || echo "no_allowed_tools")
    assert_contains "$tools_check" "^has_allowed_tools$" "$cmd_name has allowed-tools field"

    hint_val=$(get_frontmatter_field "$cmd_file" "argument-hint")
    hint_check=$([ -n "$hint_val" ] && echo "has_argument_hint" || echo "no_argument_hint")
    assert_contains "$hint_check" "^has_argument_hint$" "$cmd_name has argument-hint field"

    assert_contains "$tools_val" "Bash(supaflow" "$cmd_name allowed-tools includes Bash(supaflow"

    for forbidden in "${FORBIDDEN_TOOLS[@]}"; do
        assert_not_contains "$tools_val" "$forbidden" "$cmd_name allowed-tools does not include $forbidden"
    done

    # Safe-channel guardrail: a command must never instruct pasting an API key
    # into chat. The user runs `supaflow auth login` in their own terminal.
    assert_file_not_contains "$cmd_file" "auth login --key" "$cmd_name does not leak 'auth login --key' (no API key in chat)"

    if [ "$HAS_PYYAML" = "yes" ]; then
        yaml_status=$(python3 -c "
import sys, yaml
parts = open('$cmd_file', encoding='utf-8').read().split('---', 2)
if len(parts) < 3:
    print('no_frontmatter'); sys.exit(0)
try:
    yaml.safe_load(parts[1]); print('valid_yaml')
except Exception:
    print('invalid_yaml')
" 2>/dev/null || echo 'error')
        assert_contains "$yaml_status" "^valid_yaml$" "$cmd_name frontmatter parses as valid YAML"
    fi
done

print_summary
