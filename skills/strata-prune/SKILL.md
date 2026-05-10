---
name: strata-prune
description: Vault hygiene for StrataVarious — detect decay, duplicates, and trivial notes. Use when the user invokes /strata-prune, asks to clean up the vault, remove old notes, find duplicate notes, prune stale memories, or run vault maintenance.
user-invocable: true
argument-hint: "[--apply] [--yes] [--age-days N] [--json]"
allowed-tools: ["Bash"]
---

# /strata-prune

Detect and optionally remove stale, duplicate, or trivial vault notes.

## Instructions

Run the prune script, passing any flags the user supplied:

```bash
bash "$HOME/.claude/workspace/stratavarious/stratavarious/scripts/stratavarious-prune.sh" "$@"
```

By default, runs in **dry-run mode** — no vault modifications. Pass `--apply` to execute actions.

## Candidate types

- **Decay** — error notes older than 60 days (configurable) not referenced by any other note → archived to `_archive/<year>/`
- **Trivial** — notes with fewer than 5 content lines → deleted
- **Semantic duplicates** — notes with very similar titles (Levenshtein distance < 3 or Jaccard similarity > 70%) in the same category → flagged for manual merge

## Flags

| Flag | Description |
|------|-------------|
| `--apply` | Execute archiving and deletion (dry-run by default) |
| `--yes` | Skip confirmation prompts |
| `--age-days N` | Override decay threshold (default: 60, env: `StrataVarious_PRUNE_AGE_DAYS`) |
| `--json` | Machine-readable JSON output |

## Workflow

1. Run `/strata-prune` to review candidates
2. Inspect the report — verify each candidate is appropriate
3. Run `/strata-prune --apply` to archive decay and delete trivial notes
4. Manually merge duplicate pairs identified in the report
5. Run `/strata-doctor` to verify vault integrity after pruning
