#!/usr/bin/env bash
set -euo pipefail

# Package every shared persona as one Claude Desktop plugin.
# Usage: ./scripts/package_claude_desktop_personas.sh [--check]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
readonly REPO_ROOT
readonly PERSONAS_DIR="$REPO_ROOT/shared/personas"
readonly RESPONSE_FORMAT_FILE="$REPO_ROOT/shared/steering/response-format.md"
readonly BUNDLE_PATH="$REPO_ROOT/bundles/macols-personas-claude-plugin.zip"
readonly PLUGIN_NAME="macols-personas"

PACKAGE_TEMP_DIR=""
GENERATED_BUNDLE=""

cleanup() {
    if [[ -n "$PACKAGE_TEMP_DIR" && -d "$PACKAGE_TEMP_DIR" ]]; then
        rm -rf "$PACKAGE_TEMP_DIR"
    fi
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

package_personas() {
    command -v zip >/dev/null || die "zip is required to package Claude personas"
    command -v unzip >/dev/null || die "unzip is required to verify the Claude plugin"
    [[ -f "$RESPONSE_FORMAT_FILE" ]] || die "missing response format source: $RESPONSE_FORMAT_FILE"

    PACKAGE_TEMP_DIR="$(mktemp -d)"
    local plugin_root="$PACKAGE_TEMP_DIR/$PLUGIN_NAME"
    local persona_dir persona_count=0 archived_skill_count bundle_revision

    mkdir -p "$plugin_root/.claude-plugin" "$plugin_root/skills"
    for persona_dir in "$PERSONAS_DIR"/*; do
        [[ -d "$persona_dir" ]] || continue
        # "_"-prefixed dirs hold shared partials, not personas.
        [[ "$(basename "$persona_dir")" == _* ]] && continue
        [[ -f "$persona_dir/SKILL.md" ]] || die "missing SKILL.md in $persona_dir"
        local dest
        dest="$plugin_root/skills/$(basename "$persona_dir")"
        cp -R "$persona_dir" "$dest"
        # Mirror generate_personas: inline {{include: ...}} partials so the
        # bundled skill is self-contained, then append the shared response
        # format so Claude Desktop matches every other surface.
        PERSONAS_PARTIALS_ROOT="$PERSONAS_DIR" perl -0pi -e '
            s!\{\{include:\s*([^}\s]+)\s*\}\}!{
                local $/;
                open my $fh, "<", "$ENV{PERSONAS_PARTIALS_ROOT}/$1" or die "include not found: $1\n";
                my $c = <$fh>; $c =~ s/\s+\z//; $c
            }!ge' "$dest/SKILL.md"
        printf '\n' >> "$dest/SKILL.md"
        cat "$RESPONSE_FORMAT_FILE" >> "$dest/SKILL.md"
        ((persona_count += 1))
    done
    ((persona_count > 0)) || die "no personas found in $PERSONAS_DIR"

    find "$plugin_root" -name .DS_Store -delete
    bundle_revision=$(
        cd "$plugin_root"
        find skills -type f -exec cksum {} \; | LC_ALL=C sort | cksum | awk '{print $1}'
    )
    printf '{\n  "name": "macols-personas",\n  "displayName": "macols personas",\n  "version": "0.0.0-personas.%s",\n  "description": "Matt Coles personal specialist personas and workflows",\n  "author": {\n    "name": "Matt Coles"\n  }\n}\n' \
        "$bundle_revision" > "$plugin_root/.claude-plugin/plugin.json"
    find "$plugin_root" -exec touch -t 198001010000 {} +

    GENERATED_BUNDLE="$PACKAGE_TEMP_DIR/$PLUGIN_NAME.zip"
    (
        cd "$PACKAGE_TEMP_DIR"
        find "$PLUGIN_NAME" -print | LC_ALL=C sort | zip -X -q "$GENERATED_BUNDLE" -@
    )

    unzip -tq "$GENERATED_BUNDLE" >/dev/null
    unzip -Z1 "$GENERATED_BUNDLE" | grep -x "$PLUGIN_NAME/.claude-plugin/plugin.json" >/dev/null ||
        die "generated bundle is missing its plugin manifest"
    archived_skill_count=$(unzip -Z1 "$GENERATED_BUNDLE" |
        grep -c "^$PLUGIN_NAME/skills/[^/]*/SKILL.md$")
    [[ "$archived_skill_count" -eq "$persona_count" ]] ||
        die "generated bundle contains $archived_skill_count of $persona_count personas"
}

main() {
    local check_only=false

    if [[ ${1:-} == "--check" ]]; then
        check_only=true
        shift
    fi
    [[ $# -eq 0 ]] || die "usage: $0 [--check]"

    trap cleanup EXIT
    package_personas

    if [[ "$check_only" == true ]]; then
        [[ -f "$BUNDLE_PATH" ]] ||
            die "bundle is missing; run ./scripts/package_claude_desktop_personas.sh"
        cmp -s "$GENERATED_BUNDLE" "$BUNDLE_PATH" ||
            die "bundle is stale; run ./scripts/package_claude_desktop_personas.sh and commit it"
        printf '✓ Claude Desktop persona bundle is current\n'
        return
    fi

    mkdir -p "$(dirname "$BUNDLE_PATH")"
    mv "$GENERATED_BUNDLE" "$BUNDLE_PATH"
    printf '✓ Packaged personas in %s\n' "$BUNDLE_PATH"
}

main "$@"
