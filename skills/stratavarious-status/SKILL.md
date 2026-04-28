---
name: stratavarious-status
description: Show StrataVarious memory system status — vault contents, sessions, disk usage. Use when the user invokes /stratavarious-status or asks about memory status, vault contents, session history, or how much data StrataVarious holds.
user-invocable: true
argument-hint: "[path]"
allowed-tools: ["Bash", "Read"]
---

# /stratavarious-status

Show the current state of the StrataVarious memory system.

## Instructions

1. Read `STRATAVARIOUS.md` — count sessions (each `## Session` heading), show last session date
2. Read `MEMORY.md` — count vault notes, list categories from frontmatter
3. Read `session-buffer.md` — count pending captures (each `## YYYY-MM-DD` heading)
4. Report:

```
StrataVarious Status
───────────────────
Vault path: <resolved path>
Sessions in STRATAVARIOUS.md: N/3
Vault notes: N
Journal entries: N
Session buffer: N pending captures
Last consolidation: YYYY-MM-DD
Disk usage: <du -sh of vault/>
```

All paths resolve against `STRATAVARIOUS_HOME` (default: `~/.claude/workspace/stratavarious/memory/`).
