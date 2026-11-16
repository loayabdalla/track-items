# track-items

A Claude Code skill that keeps an "Active Items" board current.

The board shows the work that waits on you:

- PRs to review, and your own open PRs (GitHub)
- Slack threads and DMs that you did not answer
- Linear issues assigned to you, and Linear mentions that you did not answer
- Follow-ups from your Claude chats

The skill also writes a daily brief on the board and a weekly progress log in a private Claude Doc.

## What you need

- Claude Code, signed in with a claude.ai account
- The Slack and Linear connectors, connected in claude.ai. The skill uses only their read tools.
- `gh` (logged in to GitHub) and `jq`

## Set up

1. Clone this repo to `~/.claude/skills/track-items`:

   ```bash
   git clone https://github.com/loayabdalla/track-items.git ~/.claude/skills/track-items
   ```

2. Copy the `deny` rules from `.claude/settings.json` to the `permissions.deny` list in `~/.claude/settings.json`. These rules block the Slack tools that write. The copy in this folder applies only to sessions that start in this folder.
3. Start Claude Code in this folder, and run `/track-items setup`:

   ```bash
   cd ~/.claude/skills/track-items && claude
   ```

   Setup asks for your main Linear team and the first month for the progress log. Then it makes your board, your progress log doc, and `config.local.json`. Git ignores this file.
4. Approve the consent screen at the first board write.
5. In the same session, run `/loop 5m /track-items tick`. The board then updates each hour, and when you click Update on the board.

## Commands

- `/track-items sync`: update the board now.
- `/track-items brief`: build today's brief.
- `/track-items list`: show your open items.
- `/track-items track <what>` and `/track-items done <what>`: add or close an item.
- `/track-items win <what>`: add a win to the progress log.
- `/track-items progress`: update the progress log now.

## Files

- `SKILL.md`: the skill instructions.
- `page/active-items.html`: the board page.
- `page/progress-log.md`: the template for the progress log doc.
- `page/progress-chart.jsx`: the chart template for the progress log.
- `scripts/`: the GitHub scripts.
- `.claude/settings.json`: the permission rules for the background session.
- `config.example.json`: the fields of `config.local.json`.
