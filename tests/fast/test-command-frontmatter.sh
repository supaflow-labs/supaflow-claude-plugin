#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

echo "Testing command frontmatter..."

FORBIDDEN_TOOLS=("Agent" "WebFetch" "WebSearch")

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
done

print_summary
