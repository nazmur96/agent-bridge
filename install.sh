#!/usr/bin/env bash
# Register agent-bridge hooks in Claude Code (user settings) and Cursor (user
# hooks). Idempotent: entries already pointing at agent-bridge are replaced,
# everything else in both files is left untouched. Backs up before writing.
#
#   ./install.sh            install
#   ./install.sh --remove   remove the hooks again
set -euo pipefail

BIN="$(cd "$(dirname "$0")" && pwd)/bin/agent-bridge"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CURSOR_HOOKS="$HOME/.cursor/hooks.json"
STAMP=$(date +%Y%m%d-%H%M%S)
REMOVE=false; [ "${1:-}" = "--remove" ] && REMOVE=true

chmod +x "$BIN"

# write_json <file> <jq filter> [jq args...]: backup, transform, validate, swap.
write_json() {
  local file=$1 filter=$2; shift 2
  local tmp="$file.tmp.$$"
  [ -f "$file" ] || echo '{}' >"$file"
  cp "$file" "$file.bak-agent-bridge-$STAMP"
  jq "$@" "$filter" "$file" >"$tmp"
  jq empty "$tmp"
  mv "$tmp" "$file"
}

# --- Claude Code -------------------------------------------------------------
write_json "$CLAUDE_SETTINGS" '
  def strip: map(select(any(.hooks[]?; .command | contains("agent-bridge")) | not));
  def entry($sub): {hooks: [{type: "command", command: "\($bin) \($sub)", timeout: 10}]};
  .hooks //= {} |
  .hooks.Stop = ((.hooks.Stop // []) | strip) |
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | strip) |
  if $remove then . else
    .hooks.Stop += [entry("claude-stop")] |
    .hooks.UserPromptSubmit += [entry("claude-prompt")]
  end' --arg bin "$BIN" --argjson remove "$REMOVE"

# --- Cursor ------------------------------------------------------------------
mkdir -p "$(dirname "$CURSOR_HOOKS")"
write_json "$CURSOR_HOOKS" '
  def strip: map(select(.command | contains("agent-bridge") | not));
  def entry($sub): {command: "\($bin) \($sub)", timeout: 10};
  .version //= 1 | .hooks //= {} |
  reduce ("afterAgentResponse", "sessionStart", "postToolUse") as $h
    (.; .hooks[$h] = ((.hooks[$h] // []) | strip)) |
  if $remove then . else
    .hooks.afterAgentResponse += [entry("cursor-response")] |
    .hooks.sessionStart += [entry("cursor-inject")] |
    .hooks.postToolUse += [entry("cursor-inject")]
  end' --arg bin "$BIN" --argjson remove "$REMOVE"

if $REMOVE; then echo "agent-bridge hooks removed."; else
  echo "agent-bridge hooks installed:"
  echo "  Claude Code: $CLAUDE_SETTINGS (Stop, UserPromptSubmit)"
  echo "  Cursor:      $CURSOR_HOOKS (afterAgentResponse, sessionStart, postToolUse)"
  echo "Restart Claude Code sessions and reload the Cursor window to pick them up."
fi
