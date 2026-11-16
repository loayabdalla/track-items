# track-items

A Claude Code skill that keeps an "Active Items" board current.

The board shows the work that waits on you:

- PRs to review, and your own open PRs (GitHub)
- Slack threads and DMs that you did not answer
- Linear issues assigned to you, and Linear mentions that you did not answer
- Follow-ups from your Claude chats

The skill also writes a daily brief and a weekly progress log.

## Files

- `SKILL.md`: the skill instructions.
- `page/active-items.html`: the board page. It is a claude.ai Artifact with a database.
- `page/progress-chart.jsx`: the chart template for the progress log.
- `scripts/`: the GitHub scripts. They need `gh` (logged in) and `jq`.
- `config.example.json`: the fields for your private config.

## Set up

1. Copy this folder to `~/.claude/skills/track-items`.
2. Copy `config.example.json` to `config.local.json`.
3. Put your board link, Linear team, and progress log values in `config.local.json`. Git ignores this file.
4. Connect Slack and Linear in claude.ai. The skill uses only their read tools.
5. Run `/track-items sync` in Claude Code.

To sync in the background, see "Run it in the background" in `SKILL.md`.
