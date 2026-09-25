# agent-bridge

Lets Claude Code and Cursor's agent see each other's replies without copy-paste.

When either agent finishes a turn, its final reply is appended to a per-project
log. The next time the *other* agent works, the entries it hasn't seen are
injected into its context automatically.

```
Cursor answers ──afterAgentResponse──▶ log ──UserPromptSubmit──▶ Claude's next prompt
Claude answers ──Stop────────────────▶ log ──sessionStart / postToolUse──▶ Cursor
```

- Only final replies travel: no reasoning, no tool output.
- Nothing auto-continues, so the agents never talk to each other without you.
- Each agent gets only the other's entries, and only once (a bookmark per reader).
- At most 5 entries per injection, 6000 chars each.
- Injected text is framed as a colleague's notes, not instructions from you.

## OpenSpec auto-setup

`bin/openspec-autoinit` runs at session start in both agents. If the session's
folder is a git repo without `openspec/`, it runs
`openspec init --tools claude,cursor` (core commands + `verify`) and tells the
agent to offer filling in `openspec/config.yaml`'s `context:` and committing.
It never commits. Until `context:` exists, each session gets a one-line reminder.

- Not a git repo (e.g. a plain chat from `~`), or `~` itself: does nothing.
- Skip a repo: add its toplevel path to `~/.config/agent-bridge/openspec-ignore`.
- New `/opsx` commands load on the *next* session start in that repo.

## Install / remove

```sh
./install.sh            # adds all hooks to ~/.claude/settings.json and ~/.cursor/hooks.json
./install.sh --remove   # takes them out again
```

Both are idempotent and back up the file they touch (`*.bak-agent-bridge-<time>`).
Afterwards restart Claude Code sessions and run *Developer: Reload Window* in Cursor.

## Where things live

- Log: `~/.local/state/agent-bridge/<project-path>/log.jsonl`
- Project = git toplevel of the agent's working dir (Claude: `$CLAUDE_PROJECT_DIR`,
  Cursor: first workspace root). Both agents must have the same project open.
- `bin/agent-bridge tail [dir]` prints the conversation so far.

## Known limits

- Cursor receives new entries at session start or after its first tool call in a
  turn. Its prompt-submit hook cannot add context, so a reply with no tool call
  won't see anything new until the next tool call.
- `last-cursor-input.json` in the state dir holds the last raw Cursor hook input,
  for checking the hook contract if Cursor changes it.
