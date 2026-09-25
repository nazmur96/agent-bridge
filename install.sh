#!/usr/bin/env bash
# Register agent-bridge hooks in Claude Code (user settings) and Cursor (user
# hooks). Idempotent: entries already pointing at agent-bridge are replaced,
# everything else in both files is left untouched. Backs up before writing.
#
#   ./install.sh            install
#   ./install.sh --remove   remove the hooks again
set -euo pipefail

BINDIR="$(cd "$(dirname "$0")" && pwd)/bin"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CURSOR_HOOKS="$HOME/.cursor/hooks.json"
STAMP=$(date +%Y%m%d-%H%M%S)
REMOVE=false; [ "${1:-}" = "--remove" ] && REMOVE=true

chmod +x "$BINDIR"/*

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
  def entry($cmd): {hooks: [{type: "command", command: "\($bin)/\($cmd)", timeout: 30}]};
  .hooks //= {} |
  reduce ("Stop", "UserPromptSubmit", "SessionStart") as $h
    (.; .hooks[$h] = ((.hooks[$h] // []) | strip)) |
  if $remove then . else
    .hooks.Stop += [entry("agent-bridge claude-stop")] |
    .hooks.UserPromptSubmit += [entry("agent-bridge claude-prompt")] |
    .hooks.SessionStart += [entry("openspec-autoinit claude")]
  end' --arg bin "$BINDIR" --argjson remove "$REMOVE"

# --- Cursor ------------------------------------------------------------------
mkdir -p "$(dirname "$CURSOR_HOOKS")"
write_json "$CURSOR_HOOKS" '
  def strip: map(select(.command | contains("agent-bridge") | not));
  def entry($cmd): {command: "\($bin)/\($cmd)", timeout: 30};
  .version //= 1 | .hooks //= {} |
  reduce ("afterAgentResponse", "sessionStart", "postToolUse") as $h
    (.; .hooks[$h] = ((.hooks[$h] // []) | strip)) |
  if $remove then . else
    .hooks.afterAgentResponse += [entry("agent-bridge cursor-response")] |
    .hooks.sessionStart += [entry("openspec-autoinit cursor"), entry("agent-bridge cursor-inject")] |
    .hooks.postToolUse += [entry("agent-bridge cursor-inject")]
  end' --arg bin "$BINDIR" --argjson remove "$REMOVE"

if $REMOVE; then echo "agent-bridge hooks removed."; else
  echo "agent-bridge hooks installed:"
  echo "  Claude Code: $CLAUDE_SETTINGS (Stop, UserPromptSubmit, SessionStart)"
  echo "  Cursor:      $CURSOR_HOOKS (afterAgentResponse, sessionStart, postToolUse)"
  echo "Restart Claude Code sessions and reload the Cursor window to pick them up."
fi
