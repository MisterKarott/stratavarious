<p align="center">
  <img src="https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet?style=for-the-badge&logo=anthropic" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/version-1.6.0-6c5ce7?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-00b894?style=for-the-badge" alt="License">
</p>

<h1 align="center">StrataVarious</h1>

<p align="center"><strong>Persistent memory for Claude Code.</strong><br>
Never start a session from zero again.</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-active-success?style=flat-square" alt="Status">
  <img src="https://img.shields.io/badge/Made%20by-MisterKarott-ff6b6b?style=flat-square" alt="Author">
</p>

---

## The Problem

Claude Code is powerful, but every session starts from scratch. You re-explain your stack, your naming conventions, the weird edge case you spent two hours debugging last Tuesday. You paste context into `CLAUDE.md` files and hope you remember to update them. Over time, you accumulate knowledge that lives only in past conversations — invisible to the next session.

This isn't just inconvenient. It's **lost institutional memory**. Every session re-derives things you already figured out. Every handoff risks dropping critical context.

**StrataVarious** fixes this by giving Claude Code a persistent, evolving memory that grows with every session — automatically.

## What StrataVarious Does

StrataVarious is a Claude Code plugin that builds a **living knowledge vault** from your actual work sessions. It operates on a simple principle:

> The most valuable knowledge about a project is produced naturally during development. You shouldn't have to manually write it down.

Instead of asking you to maintain documentation, StrataVarious:

1. **Observes** what happens in each session — decisions made, errors hit, patterns discovered, dead ends abandoned
2. **Distills** raw session data into structured, reusable knowledge
3. **Persists** that knowledge across sessions so Claude always has context
4. **Protects** your secrets — credentials and API keys never enter the vault

The result is a self-maintaining knowledge base that gets smarter the more you work.

## Philosophy

**Knowledge should flow downstream.** When you debug a tricky Docker networking issue on a Tuesday, that solution should be available on Wednesday — without you doing anything. StrataVarious treats every session as a potential knowledge source and extracts what matters automatically.

**Zero-friction by default.** The Stop hook captures data transparently. You don't need to remember to write things down or run a command before closing your session. The system works even if you forget it exists.

**Selective memory, not hoarding.** StrataVarious doesn't dump entire conversation transcripts into files. The consolidation pipeline analyzes, filters, and structures raw session data into concise, actionable knowledge. A 2-hour debugging session might produce 5 lines of vault knowledge — the 5 lines that matter.

**Local-first, always.** All data stays on your machine. No cloud sync, no external API calls, no telemetry. Your vault is a git repository you control entirely.

## How It Works

```
┌──────────────────────────────────────────────────────────┐
│                     YOUR SESSIONS                        │
│                                                          │
│  Session 1 ──► Session 2 ──► Session 3 ──► ...          │
│      │              │              │                     │
│      ▼              ▼              ▼                     │
│  ┌──────────────────────────────────────────┐            │
│  │        SessionStart Hook (automatic)     │            │
│  │   Injects STRATA.md into fresh session   │            │
│  └────────────────┬─────────────────────────┘            │
│                   │                                      │
│                   ▼                                      │
│  ┌──────────────────────────────────────────┐            │
│  │           Stop Hook (automatic)          │            │
│  │        Captures session data on exit     │            │
│  └────────────────┬─────────────────────────┘            │
│                   ▼                                      │
│  ┌──────────────────────────────────────────┐            │
│  │       /stratavarious consolidation       │            │
│  │                                          │            │
│  │  Phase 0 — Capture intentions            │            │
│  │    Ask next steps before consolidating   │            │
│  │                                          │            │
│  │  Phase 1 — Read buffer                   │            │
│  │    Load raw session capture              │            │
│  │                                          │            │
│  │  Phase 2 — Analyze session               │            │
│  │    Identify decisions, errors, patterns  │            │
│  │                                          │            │
│  │  Phase 3a — Write STRATA.md  ◄── NEW     │            │
│  │    Portable handoff at project root      │            │
│  │                                          │            │
│  │  Phase 3 — Write to working memory       │            │
│  │    Update STRATAVARIOUS.md (last 3)      │            │
│  │                                          │            │
│  │  Phase 4 — Security scan                 │            │
│  │    Strip credentials and API keys        │            │
│  │                                          │            │
│  │  Phase 5 — Archive to vault              │            │
│  │    Persist themed knowledge notes        │            │
│  │                                          │            │
│  │  Phase 6 — Git commit                    │            │
│  │    Version the accumulated knowledge     │            │
│  │                                          │            │
│  │  Phase 7 — Cleanup buffer                │            │
│  │    Clear raw session data                │            │
│  └────────────────┬─────────────────────────┘            │
│                   ▼                                      │
│  ┌──────────────────────────────────────────┐            │
│  │           KNOWLEDGE VAULT                │            │
│  │         Persists across sessions         │            │
│  │         Grows with every session         │            │
│  └──────────────────────────────────────────┘            │
└──────────────────────────────────────────────────────────┘
```

### Two layers of memory

StrataVarious maintains two complementary layers:

- **Working memory** (`STRATAVARIOUS.md`) — a rolling window of your last 3 sessions. Lightweight, always loaded, gives Claude immediate context about what you've been doing recently. Think of it as short-term memory.

- **Knowledge vault** (`vault/`) — durable, themed notes organized by category: decisions, error resolutions, patterns, preferences, dead ends. This is long-term memory. It grows over time and is indexed in `MEMORY.md`, which Claude auto-loads at session start.

Together, these layers mean Claude starts every session knowing what you did recently *and* what you've learned over time.

## Features

### Session Memory (Short-Term)

Your last 3 sessions are automatically summarized and loaded into context at session start. Claude knows what you worked on yesterday, what errors you hit, and where you left off — without you saying a word.

### Knowledge Vault (Long-Term)

Durable notes organized by theme persist across all sessions. Over time, the vault accumulates your project's institutional knowledge: architectural decisions and why they were made, error patterns and their fixes, coding conventions, environment quirks. This is the knowledge that normally lives only in the heads of experienced team members.

### Automatic Capture

The Stop hook runs transparently after each Claude response. It reads the session transcript to extract user intent, tool operations, file changes, and errors — then writes structured data to a buffer. No user action required.

### Portable Handoff File

After each `/stratavarious`, a `STRATA.md` file is written to the root of the current git project. It contains a structured summary of the session: goal, decisions, files modified, what worked, dead ends, errors, and next steps. You can pass this file directly to a fresh session — no copy-pasting, no re-explaining.

### Auto-Injection on Session Start

A `SessionStart` hook detects `STRATA.md` at the current project root and automatically injects its content into the new session's context. The next session starts with the handoff already loaded — you don't have to do anything.

### Handoff Replacement

`/stratavarious` fully replaces `/handoff`. Before consolidating, it asks about your next steps and intentions. Those feed directly into `STRATA.md` and `STRATAVARIOUS.md`. Next session loads both automatically.

### Consolidation Pipeline

Running `/stratavarious` triggers a 9-phase pipeline: capture intentions → read conversation + buffer → analyze → write STRATA.md → write to working memory → security scan → archive to vault → git commit → cleanup.

### Security Scan

Before anything enters the vault, a security scan strips credentials, API keys, tokens, and other sensitive values. Your secrets stay out of the knowledge base. The raw session buffer is also gitignored as an additional safety net.

### Git-Tracked History

The entire vault is a git repository. Every consolidation creates a commit. You can diff knowledge over time, revert bad entries, branch for experiments, or audit what was captured. Your memory has a history.

## Installation

```bash
claude plugin install github.com/MisterKarott/stratavarious
```

## Quick Start

```bash
# 1. Install the plugin
claude plugin install github.com/MisterKarott/stratavarious
```

```bash
# 2. Initialize the vault — or skip this, /stratavarious auto-inits on first run
bash ~/.claude/plugins/cache/*/stratavarious/*/scripts/setup.sh
```

The Stop hook captures session data automatically. Work normally.

```bash
# 3. At end of session (or whenever you want), consolidate
/stratavarious
```

Next time you start Claude Code, your context is already there. The working memory loads automatically. The vault index is available. You pick up where you left off.

## Architecture

```
<your-project>/
└── STRATA.md                   ← Portable handoff (written by /strata, injected at next SessionStart)

~/.claude/workspace/stratavarious/
└── memory/
    ├── STRATAVARIOUS.md        ← Working memory (last 3 sessions, auto-loaded)
    ├── MEMORY.md               ← Vault index (auto-loaded by Claude at session start)
    ├── profile.md              ← Detected user preferences and work patterns
    ├── session-buffer.md       ← Raw capture from Stop hook (gitignored)
    └── vault/
        ├── *.md                ← Themed knowledge notes (decisions, errors, patterns...)
        ├── journal/            ← Daily summaries for chronological browsing
        └── sessions/           ← Full archived session data
```

The vault is designed to be human-readable. Every file is plain Markdown. You can browse, edit, or delete entries manually. The system won't break if you rearrange things.

## Commands

| Command | Description |
|---|---|
| `/stratavarious` | Run the full 9-phase consolidation pipeline — captures intentions, analyzes the conversation, writes `STRATA.md` to project root, updates working memory, archives to vault, commits to git |
| `/strata` | Alias for `/stratavarious` — same pipeline, shorter name |
| `/stratavarious-status` | Show vault status — entry count, last consolidation date, vault size, recent activity |

## Scripts

| Script | Purpose |
|---|---|
| `scripts/setup.sh` | Initialize the vault directory structure with default templates |
| `scripts/stratavarious-status.sh` | CLI status check — useful outside Claude Code |
| `scripts/stratavarious-clean.sh` | Scan the vault for duplicate or stale entries and flag them for review |
| `scripts/stratavarious-validate.sh` | Validate vault note frontmatter — exits 1 if any note is malformed |

## What Gets Captured

StrataVarious is selective by design. Not everything that happens in a session is worth remembering. The consolidation pipeline looks for:

- **User preferences** — explicit ("I prefer arrow functions") and detected (you keep rejecting certain suggestions)
- **Architectural decisions** — what was chosen and, critically, *why* — the rationale is often more valuable than the decision itself
- **Errors and resolutions** — the bug, the root cause, and the fix. Next time you hit something similar, the answer is already there
- **Successful patterns** — approaches that worked and are worth reusing
- **Dead ends** — approaches that were abandoned, and why. This prevents re-exploring the same failed paths
- **Project conventions** — naming patterns, file organization, environment quirks, tool configurations

## What Stays Private

| Concern | How it's handled |
|---|---|
| Session buffer | Gitignored — raw capture is never committed to the vault |
| Credentials / API keys | Security scan strips them before any vault write |
| Sensitive values | Tokens, passwords, and connection strings are detected and removed |
| Data residency | Everything stays on your machine. No cloud, no API, no sync |

No data ever leaves your machine. There is no telemetry, no analytics, no phone-home. The vault is yours.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `STRATAVARIOUS_HOME` | `~/.claude/workspace/stratavarious` | Root directory for all vault data |
| `STRATAVARIOUS_MAX_BUFFER` | `512000` (500 KB) | Max size of `session-buffer.md` before truncation |
| `STRATAVARIOUS_DISABLE` | *(unset)* | Set to `1` to disable the Stop hook entirely (useful in CI) |

Override by setting the environment variable before starting Claude Code.

## Use Cases

**Solo developers** — Stop re-explaining your project to Claude every morning. StrataVarious remembers your stack, your conventions, and the weird bugs you already solved.

**Long-running projects** — After weeks of work, the vault accumulates deep project knowledge. Claude becomes more effective over time, not less.

**Team context sharing** — The vault is a git repo. Commit it to your project and teammates get the accumulated knowledge. New team members ramp up faster.

**Debugging journals** — The error resolution entries form a searchable history of every bug you've encountered and how it was fixed. Like a personal Stack Overflow.

## License

[MIT](LICENSE) &copy; MisterKarott
