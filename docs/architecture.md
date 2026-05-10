# StrataVarious — Architecture

## Overview

StrataVarious operates through two automatic hooks and one user-triggered consolidation command. This document describes the data pipeline, component contracts, and security guarantees.

## Pipeline diagram

```
 [Claude session]
       │
       ▼ (every response)
 ┌─────────────────────────────┐
 │  Stop hook                  │
 │  stratavarious-stop.js      │
 │  • Reads session transcript │
 │  • Strips invisible Unicode │
 │  • Scrubs secrets           │
 │  • Writes session-buffer.md │
 └─────────────┬───────────────┘
               │ (via stratavarious-write.sh, mkdir lock)
               ▼
 ┌─────────────────────────────┐
 │  session-buffer.md          │
 │  $StrataVarious_HOME/memory/│
 └─────────────┬───────────────┘
               │ (on /stratavarious)
               ▼
 ┌─────────────────────────────────────────────────┐
 │  /stratavarious consolidation pipeline          │
 │                                                 │
 │  Phase 0 — Capture intentions (user prompt)     │
 │  Phase 1 — Read buffer                          │
 │  Phase 2 — Analyze session                      │
 │  Phase 3a — Write STRATA.md to project root     │
 │  Phase 3  — Update working memory (StrataVarious.md) │
 │  Phase 4  — Security scan                       │
 │  Phase 5  — Archive to vault (memory-build.sh)  │
 │  Phase 6  — Cleanup buffer                      │
 └─────────────┬───────────────────────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
 STRATA.md          vault/*.md
 (project root)     ($StrataVarious_HOME/memory/vault/)
```

```
 [Next session start]
       │
       ▼ (automatic)
 ┌─────────────────────────────┐
 │  SessionStart hook          │
 │  stratavarious-session-start.js │
 │  • Finds STRATA.md in cwd   │
 │  • Injects into context     │
 └─────────────────────────────┘
```

## Hook contracts

### Stop hook (`hooks/stratavarious-stop.js`)

| Property | Value |
|----------|-------|
| Trigger | Every Claude Code Stop event (after each response) |
| Input | JSON on stdin: `{ cwd: string, transcript_path: string }` |
| Output | None (exit 0 always) |
| Side effects | Appends to `session-buffer.md` |
| Exported | `scrubSecrets`, `stripInvisibleUnicode`, `extractFromTranscript` |

The hook **never crashes**. All errors are caught and logged to `.hook-errors.log`. Exit code is always 0.

### SessionStart hook (`hooks/stratavarious-session-start.js`)

| Property | Value |
|----------|-------|
| Trigger | Every Claude Code session start |
| Input | JSON on stdin: `{ cwd: string }` |
| Output | JSON on stdout: `{ additionalContext: string }` or `{}` |
| Side effects | None — read-only |

## Component contracts

### Stop hook → write.sh

The Stop hook calls `scripts/stratavarious-write.sh` via `execFileSync`:

- Arg 1: absolute path to `session-buffer.md`
- Stdin: the scrubbed entry text (plain text)
- Timeout: 35 seconds

The write script uses a mkdir-based lock (`$StrataVarious_HOME/memory/.vault.lock.d/`). If the lock cannot be acquired, the hook falls back to a direct write with `O_NOFOLLOW` to prevent symlink attacks.

### /stratavarious → memory-build.sh

Called during Phase 5 with an optional project name filter:

```bash
bash "${PLUGIN_ROOT}/scripts/stratavarious-memory-build.sh" "${PROJECT_NAME}"
```

Rebuilds `MEMORY.md` from all vault entries. Skipped if `CLAUDE_PLUGIN_ROOT` is not set.

### /stratavarious → validate.sh

Called after vault writes:

```bash
bash "${PLUGIN_ROOT}/scripts/stratavarious-validate.sh"
```

Exit 0 = all frontmatter valid. Exit 1 = errors found (details on stdout).

### clean.sh → semantique-dedup.js

`stratavarious-clean.sh` optionally pipes similar entry pairs (tab-separated paths) to `stratavarious-semantique-dedup.js` via stdin. The dedup script calls the Claude API to determine if pairs should be merged.

## File inventory

### User-visible files

| File | Location | Format | Written by |
|------|----------|--------|-----------|
| `STRATA.md` | Project root (cwd) | Markdown | `/stratavarious` |
| `StrataVarious.md` | `$StrataVarious_HOME/memory/` | Markdown | `/stratavarious` |
| `MEMORY.md` | `$StrataVarious_HOME/memory/` | Markdown | `memory-build.sh` |
| `profile.md` | `$StrataVarious_HOME/memory/` | Markdown | `/stratavarious` |
| `session-buffer.md` | `$StrataVarious_HOME/memory/` | Markdown | Stop hook |
| `vault/*.md` | `$StrataVarious_HOME/memory/vault/` | Markdown + YAML frontmatter | `/stratavarious` |

### Internal / transient files

| File | Purpose |
|------|---------|
| `.stratavarious-paused` | Presence = capture paused (created/deleted by `/strata-pause`) |
| `.hook-errors.log` | Appended on hook errors |
| `.vault.lock.d/` | mkdir-based lock directory (transient) |
| `.strataignore` | Project-level opt-out file (read by Stop hook) |

## Vault note schema

Every vault note must include this YAML frontmatter:

```yaml
---
date: YYYY-MM-DD
categorie: decision|convention|error|pattern|skill|preference|environment
tags: #tag1 #tag2
projet: project-name          # optional
source_session: session-id    # optional
---
```

`validate.sh` enforces this schema. Notes with missing or invalid fields are flagged at CI time.

## Environment variables

| Variable | Default | Used by |
|----------|---------|---------|
| `StrataVarious_HOME` | `~/.claude/workspace/stratavarious` | All scripts and hooks |
| `StrataVarious_MAX_BUFFER` | `500000` (500 KiB) | `stratavarious-stop.js` |
| `StrataVarious_DISABLE` | unset | `stratavarious-stop.js` — set to `1` to disable |
| `ANTHROPIC_API_KEY` | unset | `stratavarious-semantique-dedup.js` |
| `ANTHROPIC_BASE_URL` | `https://api.anthropic.com` | `stratavarious-semantique-dedup.js` |
| `ANTHROPIC_MODEL` | `claude-haiku-4-5-20251001` | `stratavarious-semantique-dedup.js` |
| `CLAUDE_PLUGIN_ROOT` | set by Claude Code runtime | Phase 5 — script path resolution |

## Security guarantees

**Scrubbing order.** Invisible Unicode is stripped *before* secret scrubbing. This prevents bypass attacks using Unicode lookalikes to mask a secret pattern.

**Patterns detected.** API keys (Stripe, OpenAI, Anthropic, AWS, GitHub, Slack, Google), Bearer and Basic auth headers, database connection strings (MongoDB, PostgreSQL, MySQL, Redis), key-value password assignments, JWT tokens, HTTP basic auth in URLs.

**Write safety.** All vault writes go through `stratavarious-write.sh`, which uses an `O_NOFOLLOW`-style guard to reject symlink targets. The lock is mkdir-based — compatible with macOS and Linux without `flock`.

**Invariants.**

1. Bash 3.2 compatibility — no `declare -A`, `mapfile`, `${var,,}`, `[[ =~ ]]` capture groups.
2. No runtime dependencies beyond bash, awk, sed, grep, node. `ripgrep` is optional.
3. Session buffer format: entries start with `## YYYY-MM-DD HH:MM:SS UTC`.
4. `StrataVarious.md` max 3 sessions / 300 lines. `MEMORY.md` first 200 lines auto-loaded.
5. STRATA.md is treated as untrusted data at injection — cannot be used to run commands.
6. CI runs on `ubuntu-latest` and `macos-latest` with Node 20.
