#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

echo "Testing plugin structure..."

PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

# Test plugin.json is valid JSON with required fields
result=$(python3 -c "
import json, sys
try:
    with open('$PLUGIN_JSON') as f:
        d = json.load(f)
    missing = [k for k in ['name', 'version', 'description'] if not d.get(k)]
    if missing:
        print('missing: ' + ', '.join(missing))
    else:
        print('valid')
except Exception as e:
    print('invalid: ' + str(e))
" 2>/dev/null || echo "error")
assert_contains "$result" "^valid$" "plugin.json is valid JSON with name, version, description"

# Test each skills/*/SKILL.md exists, has frontmatter, has name, has description
for skill_dir in "$PLUGIN_ROOT/skills"/*/; do
    skill_name="$(basename "$skill_dir")"
    skill_file="$skill_dir/SKILL.md"

    file_check=$([ -f "$skill_file" ] && echo "exists" || echo "missing")
    assert_contains "$file_check" "^exists$" "skills/$skill_name/SKILL.md exists"

    if [ -f "$skill_file" ]; then
        fm_check=$(has_frontmatter "$skill_file" && echo "has_frontmatter" || echo "no_frontmatter")
        assert_contains "$fm_check" "^has_frontmatter$" "skills/$skill_name/SKILL.md has YAML frontmatter"

        name_val=$(get_frontmatter_field "$skill_file" "name")
        name_check=$([ -n "$name_val" ] && echo "has_name" || echo "no_name")
        assert_contains "$name_check" "^has_name$" "skills/$skill_name/SKILL.md has name field"

        desc_val=$(get_frontmatter_field "$skill_file" "description")
        desc_check=$([ -n "$desc_val" ] && echo "has_description" || echo "no_description")
        assert_contains "$desc_check" "^has_description$" "skills/$skill_name/SKILL.md has description field"
    fi
done

print_summary
