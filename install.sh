#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Claude Code Config Installer
# Symlinks config files from this repo into ~/.claude/
# Safe to re-run — backs up existing non-symlink files before replacing.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
BACKUP_DIR="$CLAUDE_DIR/backups/$(date +%Y%m%d_%H%M%S)"

echo "╔══════════════════════════════════════════════╗"
echo "║   Claude Code Config Installer               ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Repo:   $SCRIPT_DIR"
echo "Target: $CLAUDE_DIR"
echo ""

mkdir -p "$CLAUDE_DIR" "$CLAUDE_DIR/skills"

backup_if_exists() {
    local target="$1"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        mkdir -p "$BACKUP_DIR"
        echo "  ⚠ Backing up existing: $target → $BACKUP_DIR/"
        cp -r "$target" "$BACKUP_DIR/"
    fi
}

link_file() {
    local source="$1" target="$2"
    backup_if_exists "$target"
    if [ -e "$target" ] || [ -L "$target" ]; then
        rm -rf "$target"
    fi
    ln -sf "$source" "$target"
    echo "  ✓ Linked: $target → $source"
}

# --- Prune dangling symlinks left by previously-installed, now-removed items ---
prune_dangling() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    find "$dir" -maxdepth 1 -type l ! -exec test -e {} \; -exec sh -c '
        for l; do echo "  ✂ Pruned dangling: $l"; rm -f "$l"; done
    ' sh {} +
}

# settings.json is written LAST (see "Per-machine settings" below): it is a real
# file merged from the tracked settings.json and the gitignored settings.local.json.

echo "📄 Installing global CLAUDE.md..."
link_file "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

echo "🧠 Installing skills..."
prune_dangling "$CLAUDE_DIR/skills"
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    # tob-* bundles are plugin-layout (skills nested one level deep) and are
    # installed via the local plugin marketplace, not as personal skills.
    case "$(basename "$skill_dir")" in tob-*) continue ;; esac
    link_file "$skill_dir" "$CLAUDE_DIR/skills/$(basename "$skill_dir")"
done

echo "🪝 Installing hooks..."
if compgen -G "$SCRIPT_DIR/hooks/*.sh" > /dev/null; then
    mkdir -p "$CLAUDE_DIR/hooks"
    prune_dangling "$CLAUDE_DIR/hooks"
    for hook_file in "$SCRIPT_DIR/hooks"/*.sh; do
        link_file "$hook_file" "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
    done
fi

# --- Agents (optional — only if the repo ships any) ---
if compgen -G "$SCRIPT_DIR/agents/*.md" > /dev/null; then
    echo "🤖 Installing agents..."
    mkdir -p "$CLAUDE_DIR/agents"
    prune_dangling "$CLAUDE_DIR/agents"
    for agent_file in "$SCRIPT_DIR/agents"/*.md; do
        link_file "$agent_file" "$CLAUDE_DIR/agents/$(basename "$agent_file")"
    done
fi

# --- Per-machine settings + the merged ~/.claude/settings.json ----------------
# settings.json (tracked) is the portable contract: permissions, hooks, plugins,
# env, attribution. Anything machine-specific lives in settings.local.json NEXT
# TO IT in this repo — gitignored, never committed:
#   • machine-absolute paths (settings files do NOT expand $HOME/~ — env-var
#     expansion is unsupported, anthropics/claude-code#4276):
#       - the plugin-marketplace path — wherever THIS clone lives ($SCRIPT_DIR)
#       - the home-dir access grant   — this machine's ~/.claude ($CLAUDE_DIR)
#   • machine taste — model, theme, tui, outputStyle, ultracode, voiceEnabled,
#     agentPushNotifEnabled, switchModelsOnFlag, remoteControlAtStartup, … —
#     seeded with defaults ONLY where the key is absent; an existing local
#     value always wins.
# Claude Code reads exactly five settings levels: managed, --settings,
# <project>/.claude/settings.local.json, <project>/.claude/settings.json, and
# ~/.claude/settings.json. A user-level ~/.claude/settings.local.json is NOT one
# of them (earlier versions of this installer wrote taste keys there, and they
# never took effect). So ~/.claude/settings.json is a REAL FILE, regenerated on
# every install as deepmerge(settings.json, settings.local.json): objects merge
# recursively, ARRAYS UNION (concat + unique), and local scalars win. Edit the
# two source files and re-run install.sh; do not hand-edit ~/.claude/settings.json
# (it is overwritten) — note that `/config` changes also land there and are
# lost on the next install unless you copy them into settings.local.json.
# Idempotent on re-run.
echo "🔧 Writing per-machine settings.local.json (in this repo, gitignored)..."
LOCAL_SETTINGS="$SCRIPT_DIR/settings.local.json"
LEGACY_LOCAL="$CLAUDE_DIR/settings.local.json"
if [ ! -f "$LOCAL_SETTINGS" ] && [ -f "$LEGACY_LOCAL" ]; then
    cp "$LEGACY_LOCAL" "$LOCAL_SETTINGS"
    echo "  ↪ Migrated legacy $LEGACY_LOCAL → $LOCAL_SETTINGS (the old location is not read by Claude Code)"
fi
MERGED_SETTINGS="$CLAUDE_DIR/settings.json"
write_local_settings() {
    if command -v jq > /dev/null 2>&1; then
        local fragment tmp existing
        fragment="$(jq -n --arg mp "$SCRIPT_DIR" --arg home "$CLAUDE_DIR" '{
            permissions: { additionalDirectories: [$home] },
            extraKnownMarketplaces: { "claude-code-config": { source: { source: "directory", path: $mp } } }
        }')"
        existing='{}'
        if [ -f "$LOCAL_SETTINGS" ]; then
            existing="$(cat "$LOCAL_SETTINGS")"
        fi
        tmp="$(mktemp)"
        if jq -n --argjson a "$existing" --argjson b "$fragment" '
            def deepmerge(x; y):
                if (x | type) == "object" and (y | type) == "object" then
                    reduce (y | keys_unsorted[]) as $k (x; .[$k] = deepmerge(x[$k]; y[$k]))
                elif (x | type) == "array" and (y | type) == "array" then
                    (x + y) | unique
                else y end;
            def seed($k; $v): if has($k) then . else . + {($k): $v} end;
            deepmerge($a; $b)
            | seed("model"; "opus[1m]")
            | seed("theme"; "dark")
            | seed("tui"; "fullscreen")
            | seed("voiceEnabled"; true)
            | seed("agentPushNotifEnabled"; true)
        ' > "$tmp" 2> /dev/null; then
            mv "$tmp" "$LOCAL_SETTINGS"
        else
            rm -f "$tmp"
            echo "  ⚠ $LOCAL_SETTINGS is not valid JSON — left untouched. Fix it and re-run." >&2
            return 1
        fi
        return 0
    fi
    if command -v python3 > /dev/null 2>&1; then
        MP="$SCRIPT_DIR" HOME_DIR="$CLAUDE_DIR" LOCAL="$LOCAL_SETTINGS" python3 - <<'PY'
import json, os
local = os.environ["LOCAL"]
frag = {
    "permissions": {"additionalDirectories": [os.environ["HOME_DIR"]]},
    "extraKnownMarketplaces": {
        "claude-code-config": {"source": {"source": "directory", "path": os.environ["MP"]}}
    },
}
data = {}
if os.path.exists(local):
    try:
        with open(local) as f:
            data = json.load(f)
    except Exception:
        data = {}
def deep_merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            deep_merge(a[k], v)
        elif isinstance(v, list) and isinstance(a.get(k), list):
            # Arrays union: extend + dedupe, preserving existing order.
            for item in v:
                if item not in a[k]:
                    a[k].append(item)
        else:
            a[k] = v
    return a
deep_merge(data, frag)
taste = {
    "model": "opus[1m]",
    "theme": "dark",
    "tui": "fullscreen",
    "voiceEnabled": True,
    "agentPushNotifEnabled": True,
}
for k, v in taste.items():
    data.setdefault(k, v)
with open(local, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
        return 0
    fi
    echo "  ⚠ Neither jq nor python3 found — skipping settings.local.json." >&2
    echo "    Add manually: extraKnownMarketplaces.claude-code-config.source.path = $SCRIPT_DIR" >&2
    return 1
}
# Merge tracked + local into the real ~/.claude/settings.json.
write_merged_settings() {
    local tmp
    tmp="$(mktemp)"
    if command -v jq > /dev/null 2>&1; then
        jq -s '
            def deepmerge(x; y):
                if (x | type) == "object" and (y | type) == "object" then
                    reduce (y | keys_unsorted[]) as $k (x; .[$k] = deepmerge(x[$k]; y[$k]))
                elif (x | type) == "array" and (y | type) == "array" then
                    (x + y) | unique
                else y end;
            deepmerge(.[0]; .[1])
        ' "$SCRIPT_DIR/settings.json" "$LOCAL_SETTINGS" > "$tmp" 2> /dev/null || { rm -f "$tmp"; return 1; }
    elif command -v python3 > /dev/null 2>&1; then
        TRACKED="$SCRIPT_DIR/settings.json" LOCAL="$LOCAL_SETTINGS" OUT="$tmp" python3 - <<'PY' || { rm -f "$tmp"; exit 1; }
import json, os
with open(os.environ["TRACKED"]) as f:
    data = json.load(f)
with open(os.environ["LOCAL"]) as f:
    local = json.load(f)
def deep_merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            deep_merge(a[k], v)
        elif isinstance(v, list) and isinstance(a.get(k), list):
            for item in v:
                if item not in a[k]:
                    a[k].append(item)
        else:
            a[k] = v
    return a
deep_merge(data, local)
with open(os.environ["OUT"], "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
    else
        rm -f "$tmp"; return 1
    fi
    # Replace whatever is at ~/.claude/settings.json: a symlink from older
    # installs is dropped; a hand-made real file is backed up first.
    if [ -L "$MERGED_SETTINGS" ]; then
        rm -f "$MERGED_SETTINGS"
    else
        backup_if_exists "$MERGED_SETTINGS"
    fi
    mv "$tmp" "$MERGED_SETTINGS"
    return 0
}
if write_local_settings; then
    echo "  ✓ Wrote: $LOCAL_SETTINGS (marketplace path + home-dir access + taste-key seeds)"
    echo "📋 Writing merged ~/.claude/settings.json (tracked settings.json + settings.local.json)..."
    if write_merged_settings; then
        echo "  ✓ Wrote: $MERGED_SETTINGS"
    else
        echo "  ⚠ Could not merge settings — falling back to a symlink of the tracked settings.json (machine-local keys inactive)." >&2
        link_file "$SCRIPT_DIR/settings.json" "$MERGED_SETTINGS"
    fi
else
    echo "  ⚠ Falling back to a symlink of the tracked settings.json (machine-local keys inactive)." >&2
    link_file "$SCRIPT_DIR/settings.json" "$MERGED_SETTINGS"
fi

echo ""
echo "════════════════════════════════════════════════"
echo "✅ Installation complete!"
echo ""
echo "Installed:"
echo "  • ~/.claude/settings.json"
echo "  • ~/.claude/CLAUDE.md"
echo ""
echo "  Skills (auto-invoked by Claude based on context):"
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    case "$(basename "$skill_dir")" in tob-*) continue ;; esac
    echo "  • $(basename "$skill_dir")"
done
echo ""
echo "  Security-audit toolkit (tob-*) installs as plugins — see README."
echo ""
echo "Skills activate automatically when Claude detects a relevant task."
echo "Quick reference:"
echo "  • scope out <epic>            → epic-planning"
echo "  • start <ISSUE-ID>            → ship-issue (gates at plan and ship)"
echo "  • cross-review this diff      → cross-review (standalone second opinion)"
echo ""
echo "To verify: claude --debug  then ask 'What skills are available?'"
echo "════════════════════════════════════════════════"
