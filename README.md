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

## Folder chats

Separate conversations, one brain. A chat can be scoped to a folder of the
project (say `terraform/`): its own history, the project's shared context.

| Open a folder chat | |
|---|---|
| Claude Code | `cd terraform && claude` -- `claude --continue` there resumes it |
| Cursor | new chat tab whose first message @-mentions the folder (`@terraform why ...`), or `/scope terraform` (`/scope main` to undo; a bare name like `/scope eks` is searched for) |

What a chat's final reply reaches:

| Same folder | Parent folder (e.g. main) | Sibling folder |
|---|---|---|
| full | 600-char summary | nothing |

Long-lived knowledge goes in `<folder>/AGENTS.md` (created on first use, with a
`CLAUDE.md` importing it). Claude Code loads CLAUDE.md files from the start folder
upward, so a folder chat always sees the root context, and the main chat picks up
a folder's notes when it works there. Folder chats are told to edit only inside
their folder, since every chat shares one checkout.

## OpenSpec auto-setup

`bin/openspec-autoinit` runs at session start in both agents. If the session's
folder is a git repo without `openspec/`, it runs
`openspec init --tools claude,cursor` (core commands + `verify`) and tells the
agent to offer filling in `openspec/config.yaml`'s `context:` and committing.
It never commits. Until `context:` exists, each session gets a one-line reminder.

- Not a git repo (e.g. a plain chat from `~`), or `~` itself: does nothing.
- Skip a repo: add its toplevel path to `~/.config/agent-bridge/openspec-ignore`.
- New `/opsx` commands load on the *next* session start in that repo.

## MCP guard (Cursor)

`bin/mcp-guard` runs before every MCP tool call in Cursor and denies the
destructive Graphiti tools -- `clear_graph`, `delete_episode`,
`delete_entity_edge` -- whatever server prefix they carry. Anything else gets
no decision, so Cursor's normal approval applies; it never auto-approves.
It's Cursor's stand-in for Claude Code's `permissions.deny`, which covers the
same tools on the Claude side.

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
