# StrataVarious v2.0 — Improvements Design

**Date**: 2026-04-30
**Source**: External review (Avis.md)
**Scope**: 5 axes — POSIX compat, vault per-project, security docs, flock, UX

---

## 1. POSIX Compatibility

### Goal
All shell scripts work on macOS (Bash 3.2) without requiring Bash 4+.

### Changes
- Rewrite `scripts/setup.sh`, `stratavarious-status.sh`, `stratavarious-validate.sh`, `stratavarious-clean.sh` to be POSIX-compatible
- Replace `[[ ]]` with `[ ]`
- Replace `${var,,}` (lowercase) with `$(echo "$var" | tr '[:upper:]' '[:lower:]')`
- Replace `mapfile` with `while read` loops
- Replace process substitution `< <(...)` with pipes or temp files
- Replace associative arrays with `case` statements or grep-based lookups
- Keep `#!/bin/bash` shebang for scripts using indexed arrays (Bash 3.2 compatible)
- Use `#!/bin/sh` only for scripts with zero array usage

### Files affected
- `scripts/setup.sh`
- `scripts/stratavarious-status.sh`
- `scripts/stratavarious-validate.sh`
- `scripts/stratavarious-clean.sh`

### Validation
- Test all scripts on Bash 3.2 (`/bin/bash` on macOS without Homebrew bash)
- CI: add a Bash 3.2 compatibility check step

---

## 2. Vault Per-Project + Global Profile

### Goal
Isolate knowledge by repository while keeping cross-project preferences global.

### New Structure
```
~/.claude/workspace/stratavarious/
├── profile.md                    ← Developer preferences (editor, languages, style)
├── vault/
│   ├── mon-repo/
│   │   ├── decisions/
│   │   ├── conventions/
│   │   ├── patterns/
│   │   ├── errors/
│   │   ├── skills/
│   │   └── environments/
│   ├── autre-repo/
│   │   └── ...
│   └── _global/
│       └── ...                   ← Knowledge not tied to a specific repo
├── memory/
│   └── session-buffer.md
└── STRATAVARIOUS.md              ← Current project handoff
```

### Changes
- Hook detects current repo name via `git rev-parse --show-toplevel` → `basename`
- Notes written to `vault/<repo-name>/<category>/`
- Session-start hook reads: `profile.md` + `vault/<current-repo>/` + `_global/`
- `profile.md` template added for developer preferences (not project-specific)
- Migration: existing vault contents move to `_global/` on first run of v2
- STRATAVARIOUS.md stays at project root (per-project handoff, unchanged)

### Files affected
- `hooks/stratavarious-stop.js` (write path logic)
- `hooks/stratavarious-session-start.js` (read path logic)
- `scripts/setup.sh` (directory structure creation)
- `templates/profile.md` (new template)
- `README.md` (updated structure docs)

---

## 3. Security Documentation

### Goal
Be transparent about secret scanning limitations.

### Changes
- Add "Security" section to README:
  - Explain regex-based scanning approach
  - List covered patterns (API keys, tokens, DB connection strings, etc.)
  - Explicit disclaimer: "StrataVarious reduces leak risk but cannot eliminate it"
  - Recommend not storing secrets in plain text during sessions
  - Mention gitleaks/trufflehog as complementary tools
- Add warning in `templates/STRATAVARIOUS.md`:
  - Brief note that captured content is scrubbed but users should avoid pasting raw secrets

### Files affected
- `README.md`
- `templates/STRATAVARIOUS.md`

---

## 4. File Locking with flock

### Goal
Prevent data corruption when multiple Claude Code sessions write concurrently.

### Implementation
```sh
with_vault_lock() {
    local lockfile="${VAULT_DIR}/.lock"
    exec 9>"${lockfile}"
    if ! flock -w 30 9; then
        echo "stratavarious: vault lock timeout (30s)" >&2
        exit 1
    fi
}
```

- Exclusive lock (`flock -x`) on `vault/.lock` via fd 9
- 30-second timeout (consolidation can be heavy)
- Lock auto-released when script exits (fd closed)
- Applied in: `setup.sh`, stop hook (buffer writes), consolidation scripts
- The JS hook (`stratavarious-stop.js`) delegates vault writes to a shell script wrapper that handles flock, rather than implementing locking in Node.js

### Files affected
- `scripts/setup.sh`
- `scripts/stratavarious-write.sh` (new — shell wrapper with flock, called from JS hook)
- Any consolidation/writing script

### Note
`flock` is available on macOS (from `util-linux` via Homebrew or system) and Linux. If `flock` is not found on PATH, degrade gracefully with a warning and proceed without locking.

---

## 5. UX Improvements

### 5a. .strataignore
- File format: same as `.gitignore` (glob patterns, one per line)
- Location: project root
- Hook reads `.strataignore` at session start
- Skips capture for paths/patterns matching the ignore list
- If file absent → no filtering (current behavior)
- Patterns: `*.log`, `temp/`, `experiments/`, etc.

### 5b. /strata-pause
- New skill: `skills/strata-pause/SKILL.md`
- Toggle behavior: creates/removes `.stratavarious-paused` marker in vault dir
- Hook checks for marker at start → if present, skip all capture
- Output: "Capture paused. Run /strata-pause again to resume."
- Marker file contains timestamp of when pause was activated

### 5c. Demo Recording
- Record an Asciinema cast showing full flow:
  1. Active session with context
  2. Session ends → vault written
  3. New session → context restored from vault
- Convert to GIF for README embedding
- Add `scripts/demo-recording.sh` for reproducible demo
- Embed in README header section

### Files affected
- `hooks/stratavarious-stop.js` (.strataignore + pause check)
- `hooks/stratavarious-session-start.js` (.strataignore read)
- `skills/strata-pause/SKILL.md` (new)
- `templates/.strataignore` (new, example template)
- `scripts/demo-recording.sh` (new)
- `README.md` (demo embed + .strataignore docs)
- `plugin.json` (new skill reference)

---

## Versioning

- Current: v1.6.2
- Target: v2.0.0 (breaking change — vault structure migration)
- Migration script included in `scripts/setup.sh` for existing users
- `profile.md` seeded from existing vault content on first v2 run

## Priority Order

1. POSIX compatibility (foundational — unblocks macOS users)
2. flock (safety — prevents data loss)
3. Vault per-project (architectural — requires migration)
4. Security docs (documentation only)
5. UX improvements (incremental features)
