<p align="center">
  <img src="https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet?style=for-the-badge&logo=anthropic" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/version-1.6.0-6c5ce7?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-00b894?style=for-the-badge" alt="License">
</p>

<h1 align="center">StrataVarious</h1>

<p align="center"><strong>Persistent memory for Claude Code.</strong><br>
A local-first knowledge vault that keeps context between sessions, so you stop re-explaining your project every morning.</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/data-100%25%20local-2d3436?style=flat-square" alt="Local-first">
  <img src="https://img.shields.io/badge/telemetry-none-2d3436?style=flat-square" alt="No telemetry">
</p>

---

## The problem

Claude Code is powerful, but every session starts from scratch. You re-explain your stack, your naming conventions, the weird edge case you spent two hours debugging last Tuesday. You paste context into `CLAUDE.md` files and hope you remember to update them. Over time, you accumulate knowledge that lives only in past conversations — invisible to the next session.

This isn't just inconvenient. It's **lost institutional memory**. Every session re-derives things you already figured out. Every handoff risks dropping critical context.

StrataVarious gives Claude Code a persistent, evolving memory that grows with every session — automatically, and entirely on your machine.

## What it does

StrataVarious is a Claude Code plugin that builds a structured knowledge base from your actual work sessions. It operates on a simple principle:

> The most valuable knowledge about a project is produced naturally during development. You shouldn't have to manually write it down.

Instead of asking you to maintain documentation, StrataVarious:

1. **Observes** what happens in each session — decisions made, errors hit, patterns discovered, dead ends abandoned.
2. **Distills** raw session data into structured, reusable notes.
3. **Persists** that knowledge across sessions so Claude always has context.
4. **Protects** your secrets — credentials and API keys never enter the vault.

The result is a self-maintaining knowledge base that compounds with use.

## Philosophy

**Knowledge should flow downstream.** When you debug a tricky Docker networking issue on a Tuesday, that solution should be available on Wednesday — without you doing anything. StrataVarious treats every session as a potential knowledge source and extracts what matters automatically.

**Zero-friction by default.** The Stop hook captures data transparently. You don't need to remember to write things down or run a command before closing your session. The system works even if you forget it exists.

**Selective memory, not hoarding.** StrataVarious doesn't dump entire conversation transcripts into files. The consolidation pipeline analyzes, filters, and structures raw session data into concise, actionable knowledge. A two-hour debugging session might produce five lines of vault knowledge — the five lines that matter.

**Local-first, always.** All data stays on your machine. No cloud sync, no external API calls, no telemetry. Your vault is entirely under your control.

## How it works

```
┌──────────────────────────────────────────────────────────┐
│                     YOUR SESSIONS                        │
│                                                          │
│  Session 1 ──► Session 2 ──► Session 3 ──► ...           │
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
│  │  Phase 1 — Read buffer                   │            │
│  │  Phase 2 — Analyze session               │            │
│  │  Phase 3a — Write STRATA.md              │            │
│  │  Phase 3 — Update working memory         │            │
│  │  Phase 4 — Security scan                 │            │
│  │  Phase 5 — Archive to vault              │            │
│  │  Phase 6 — Cleanup buffer                │            │
│  └────────────────┬─────────────────────────┘            │
│                   ▼                                      │
│  ┌──────────────────────────────────────────┐            │
│  │           KNOWLEDGE VAULT                │            │
│  │         Persists across sessions         │            │
│  └──────────────────────────────────────────┘            │
└──────────────────────────────────────────────────────────┘
```

### Two layers of memory

StrataVarious maintains two complementary layers:

**Working memory** (`STRATAVARIOUS.md`) — a rolling window of your last three sessions. Lightweight, always loaded, gives Claude immediate context about what you've been doing recently. Think of it as short-term memory.

**Knowledge vault** (`vault/`) — durable, themed notes organized by category: decisions, error resolutions, patterns, preferences, dead ends. This is long-term memory. It grows over time and is indexed in `MEMORY.md`, which Claude auto-loads at session start.

Together, these layers mean Claude starts every session knowing what you did recently *and* what you've learned over time.

## Features

**Session memory (short-term).** Your last three sessions are automatically summarized and loaded into context at session start. Claude knows what you worked on yesterday, what errors you hit, and where you left off — without you saying a word.

**Knowledge vault (long-term).** Durable notes organized by theme persist across all sessions. Over time, the vault accumulates your project's institutional knowledge: architectural decisions and why they were made, error patterns and their fixes, coding conventions, environment quirks. The kind of knowledge that normally lives only in the heads of experienced team members.

**Automatic capture.** The Stop hook runs transparently after each Claude response. It reads the session transcript to extract user intent, tool operations, file changes, and errors — then writes structured data to a buffer. No user action required.

**Portable handoff file.** After each `/stratavarious`, a `STRATA.md` file is written to the root of the current git project. It contains a structured summary of the session: goal, decisions, files modified, what worked, dead ends, errors, and next steps. You can pass this file directly to a fresh session — no copy-pasting, no re-explaining.

**Auto-injection on session start.** A `SessionStart` hook detects `STRATA.md` at the current project root and automatically injects its content into the new session. The next session starts with the handoff already loaded.

**Handoff replacement.** `/stratavarious` fully replaces `/handoff`. Before consolidating, it asks about your next steps and intentions. Those feed directly into `STRATA.md` and `STRATAVARIOUS.md`. The next session loads both automatically.

**Security scan.** Before anything enters the vault, a security scan strips credentials, API keys, tokens, and other sensitive values. Your secrets stay out of the knowledge base. The raw session buffer is also gitignored as an additional safety net.

## Requirements

- Claude Code (latest stable release)
- Bash 4+ (`scripts/` are POSIX-compatible shell)
- Git (handoff detection is scoped to the current git project)
- macOS, Linux, or Windows via WSL

No Python, no Node, no external runtime. The plugin is pure shell + Markdown.

## Installation

```bash
claude plugin install github.com/MisterKarott/stratavarious
```

That's it. The Stop and SessionStart hooks register automatically. The vault initializes itself on the first run of `/stratavarious`.

### Verifying the installation

```bash
/stratavarious-status
```

You should see vault status, entry count, and last consolidation date. If the vault hasn't been initialized yet, the command will tell you to run `/stratavarious` once.

## Quick start

```bash
# 1. Install
claude plugin install github.com/MisterKarott/stratavarious

# 2. Work normally — the Stop hook captures data in the background

# 3. End of session (or whenever): consolidate
/stratavarious
```

Next time you start Claude Code, your context is already there. Working memory loads automatically. The vault index is available. You pick up where you left off.

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
| `/stratavarious` | Run the full 7-phase consolidation pipeline — captures intentions, analyzes the conversation, writes `STRATA.md` to project root, updates working memory, archives to vault |
| `/strata` | Alias for `/stratavarious` |
| `/stratavarious-status` | Show vault status — entry count, last consolidation date, vault size, recent activity |

## Scripts

| Script | Purpose |
|---|---|
| `scripts/setup.sh` | Initialize the vault directory structure with default templates |
| `scripts/stratavarious-status.sh` | CLI status check — useful outside Claude Code |
| `scripts/stratavarious-clean.sh` | Scan the vault for duplicate or stale entries and flag them for review |
| `scripts/stratavarious-validate.sh` | Validate vault note frontmatter — exits 1 if any note is malformed (CI-friendly) |

## What gets captured

StrataVarious is selective by design. Not everything in a session is worth remembering. The consolidation pipeline looks for:

- **User preferences** — explicit ("I prefer arrow functions") and detected (you keep rejecting certain suggestions).
- **Architectural decisions** — what was chosen and, critically, *why*. The rationale is often more valuable than the decision itself.
- **Errors and resolutions** — the bug, the root cause, and the fix. Next time you hit something similar, the answer is already there.
- **Successful patterns** — approaches that worked and are worth reusing.
- **Dead ends** — approaches that were abandoned, and why. This prevents re-exploring the same failed paths.
- **Project conventions** — naming patterns, file organization, environment quirks, tool configurations.

## What stays private

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

## Use cases

**Solo developers.** Stop re-explaining your project to Claude every morning. StrataVarious remembers your stack, your conventions, and the bugs you already solved.

**Long-running projects.** After weeks of work, the vault accumulates deep project knowledge. Claude becomes more effective over time, not less.

**Team context sharing.** The vault is plain Markdown and can be committed (or partially committed) to a repo. New team members ramp up faster with shared institutional memory.

**Debugging journals.** Error resolution entries form a searchable history of every bug you've encountered and how it was fixed. Like a personal Stack Overflow.

## Troubleshooting

**The Stop hook doesn't seem to fire.** Check that the plugin is enabled with `claude plugin list`. If you're in CI or a sandbox, `STRATAVARIOUS_DISABLE=1` may be set.

**`/stratavarious` says the buffer is empty.** The Stop hook only writes after a real session turn. Run a few prompts first, then consolidate.

**`STRATA.md` wasn't injected in my new session.** Auto-injection requires being inside a git repository (handoff is scoped per project). Verify with `git rev-parse --show-toplevel`.

**I want to wipe everything and start over.** Delete `~/.claude/workspace/stratavarious/`. The next `/stratavarious` will reinitialize cleanly.

**Something looks malformed in the vault.** Run `scripts/stratavarious-validate.sh`. It will exit non-zero and point to the offending file.

## Uninstall

```bash
claude plugin uninstall stratavarious
rm -rf ~/.claude/workspace/stratavarious   # optional: removes vault data
```

No leftover state, no system-level changes.

## Contributing

Issues and pull requests are welcome. For non-trivial changes, please open an issue first to discuss the direction. Run `scripts/stratavarious-validate.sh` before submitting a PR — CI uses the same check.

## License

[MIT](LICENSE) &copy; MisterKarott
