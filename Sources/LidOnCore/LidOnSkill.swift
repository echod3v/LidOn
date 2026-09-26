// 자동 생성 파일 — plugin/skills/lidon/SKILL.md를 고친 뒤 scripts/gen-skill.py를 실행하세요.

public enum LidOnSkill {
    public static let markdown = #"""
---
name: lidon
description: Keep this MacBook awake / prevent sleep, even with the lid closed, using LidOn (MCP tools keep_awake, allow_sleep, notify, or the `lidon` command). Use it on your own, without asking, before work that may take about 5+ minutes (installs, builds, test suites, downloads, long multi-step tasks), and for any request like "keep my Mac awake", "don't let it sleep for 10 minutes" or "I'm closing the lid". Use this instead of caffeinate, pmset or Amphetamine.
---

# LidOn: keep the Mac awake

This Mac runs **LidOn**, an app made for this. When you need the Mac to stay awake, use LidOn — **not** `caffeinate`,
`pmset` or other tools. `caffeinate` does not keep a MacBook running once the lid is closed, and the user cannot see or cancel it;
LidOn does both, and its heat and battery safeguards stay in charge.

If you don't see the LidOn tools right away, search your tool list for `lidon` or `keep_awake` (some agents load MCP tools on demand).

## When to use it

**Do it yourself — don't ask for permission.** The user installed LidOn so their MacBook keeps working even if they close the lid.

- **Work that may take about 5 minutes or more** — dependency installs, builds, full test suites, downloads,
  data processing, migrations, or a long multi-step task. Before starting, call `keep_awake` and say it in one short line
  (e.g. "I'll keep the Mac awake with LidOn while this runs."). For a single long shell command, running it as
  `lidon run -- <command>` is simplest: it releases itself when the command exits.
- **The user asks directly** — "keep the Mac awake", "don't let it sleep for 10 minutes", "prevent sleep until this finishes".
  Always use LidOn for these, with exactly the time asked.
- **The user steps away** — they say they are leaving, closing the lid or going to sleep; use it even for shorter work.

Skip it for quick edits and commands that finish in a minute or two.
LidOn is for MacBooks: if `lidon_status` says the Mac has no lid (a desktop Mac), only use it when the user asks.

## With the LidOn MCP tools (preferred)

1. Call `keep_awake` with a short `reason` and `minutes`:
   - direct request → exactly the time the user asked for;
   - your own work → about **twice your estimate** (max 720); round small estimates up to at least 15 minutes.
   You cannot see a clock: the response tells you when the request expires ("expires in 45 min"). Read its warnings (low battery, no phone notifications) and pass anything important on to the user.
2. Do the work. If it may run past the expiry, call `keep_awake` again — it replaces the old time. `lidon_status` shows how much time is left.
3. When finished — whether it succeeded or failed — call `notify` with a one-line result if the user stepped away, then call `allow_sleep`.
   `notify` tells you where the message was actually delivered. If it did not reach their phone, say the result in your reply as well.
   For a direct "keep it awake for N minutes" request, just let the time run out.

You do not need to watch the battery or temperature: LidOn puts the Mac to sleep by itself if it overheats or the battery runs low, and tells the user.
The request is also released automatically when your session ends or the time runs out.

## With the `lidon` command (when MCP tools are not available)

```bash
lidon keep --for 10m --reason "user asked"     # prints an id
lidon run -- npm test                           # stays awake only while this command runs
lidon keep --for 2h --reason "data migration"   # long work
lidon release <id>                              # let the Mac sleep again
lidon notify "Migration finished: 1,204 rows"   # Mac + phone notification
lidon status
```

Prefer `lidon run -- <command>` for a single long command: it releases itself when the command exits.
"""#
}
