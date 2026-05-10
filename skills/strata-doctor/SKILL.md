---
name: strata-doctor
description: Audit StrataVarious vault integrity — broken MEMORY.md links, orphan notes, malformed frontmatter, dates in future or before 2020, malformed tags, duplicate titles. Use when the user invokes /strata-doctor or asks about vault health, broken links, orphan notes, or integrity check.
user-invocable: true
argument-hint: "[--json] [--fix] [--yes]"
allowed-tools: ["Bash"]
---

# /strata-doctor

Audit StrataVarious vault integrity.

## Instructions

Run the doctor script, passing any flags the user supplied:

```bash
bash "$HOME/.claude/workspace/stratavarious/stratavarious/scripts/stratavarious-doctor.sh" "$@"
```

The script reports:
- **Errors (exit 2):** broken MEMORY.md links, orphan notes, frontmatter failures
- **Warnings (exit 1):** future dates, dates before 2020, malformed tags, duplicate titles
- **Exit 0:** vault is healthy

Flags:
- `--json` — machine-readable JSON output
- `--fix` — interactively repair orphans and normalize tags
- `--yes` — skip confirmations (use with `--fix`)
