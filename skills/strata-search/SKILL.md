---
name: strata-search
description: Search StrataVarious vault notes by content and frontmatter. Use when the user invokes /strata-search, asks to search the vault, find past notes, look up a topic, or retrieve a memory with optional filters (category, project, tag, date range).
user-invocable: true
argument-hint: "<query> [--category=CATEGORY] [--project=NAME] [--tag=TAG] [--since=Nd] [--global] [--json] [--limit=N]"
allowed-tools: ["Bash"]
---

# /strata-search

Search StrataVarious vault notes by full-text and frontmatter filters.

## Instructions

Run the search script, passing the user's query and any flags they supplied:

```bash
bash "$HOME/.claude/workspace/stratavarious/stratavarious/scripts/stratavarious-search.sh" "$@"
```

The script searches vault note content and frontmatter using ripgrep (fallback: grep -r), ranks results by `match_count × exp(-age_days/30)`, and returns the top 10 results in readable markdown.

## Flags

- `--category=CATEGORY` — restrict to a vault category (decisions, errors, patterns, conventions, skills, preferences, environment)
- `--project=NAME` — only show notes with `projet: NAME` in frontmatter
- `--global` — only show notes without a project (global knowledge)
- `--tag=TAG` — filter by tag (without the `#`, e.g. `--tag=auth`)
- `--since=Nd` — only notes dated within the last N days (e.g. `--since=7d`)
- `--json` — machine-readable JSON output
- `--limit=N` — return top N results (default: 10)

## Examples

```
/strata-search rate limiting
/strata-search auth --category=decisions --since=30d
/strata-search docker --tag=infra --limit=5
/strata-search api key --global --json
```
