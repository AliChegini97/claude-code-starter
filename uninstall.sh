#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Claude Code Config Uninstaller
# Removes only the symlinks this repo created; leaves backups untouched.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "🗑  Removing Claude Code config symlinks..."

remove_if_symlink() {
    local target="$1"
    if [ -L "$target" ]; then
        rm "$target"
        echo "  ✓ Removed: $target"
    fi
}

remove_if_symlink "$CLAUDE_DIR/settings.json"
remove_if_symlink "$CLAUDE_DIR/CLAUDE.md"

# Remove a symlink for every skill this repo ships.
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    remove_if_symlink "$CLAUDE_DIR/skills/$(basename "$skill_dir")"
done

# Hook symlinks under ~/.claude/hooks are not ours: settings.json only registers
# them; ~/phd/agent-hooks/install.sh creates them and its uninstall.sh removes them.

# Remove a symlink for every agent this repo ships (if any).
if compgen -G "$SCRIPT_DIR/agents/*.md" > /dev/null; then
    for agent_file in "$SCRIPT_DIR/agents"/*.md; do
        remove_if_symlink "$CLAUDE_DIR/agents/$(basename "$agent_file")"
    done
fi

echo ""
echo "✅ Uninstall complete. Backups (if any) remain in $CLAUDE_DIR/backups/"
