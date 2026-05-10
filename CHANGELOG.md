# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- marketplace.json enabling plugin installation via `claude plugin install github.com/MisterKarott/stratavarious`
- `scripts/stratavarious-doctor.sh` — vault integrity audit script. Detects: broken MEMORY.md links, orphan notes (in vault but not indexed), dates in future or before 2020, tags not in `#lowercase` format, duplicate titles in the same MEMORY.md section, and frontmatter errors (via validate.sh). Flags: `--json` (machine output), `--fix` (interactive repair for orphans and tag normalization), `--yes` (skip confirmations). Exit codes: 0=healthy, 1=warnings only, 2=errors found.
- `/strata-doctor` skill — Claude Code skill that invokes the doctor script.
- `docs/performance.md` — performance reference doc with P50/P95/max baselines, thresholds, and methodology.
- `package.json`: `"os": ["darwin", "linux"]` field.
- Bench `scrubSecrets (256KB realistic)` — 256 KiB buffer with ~20 evenly distributed secrets (production-realistic density). P95 threshold: 20 ms.
- Bench `extractFromTranscript (1000 entries)` — 1000-entry JSONL transcript (~256 KiB), 100 iterations. P95 threshold: 500 ms.
- All benchmarks now report P50/P95/max instead of average only.
- CI: `perf-check` job (`workflow_dispatch` only, non-blocking) runs `node tests/bench.mjs` on ubuntu-latest.
- `docs/architecture.md` — Stop hook pipeline, security guarantees, component contracts, environment variables
- `docs/sync.md` — Vault sync strategy across machines via private git repository
- `docs/contributing.md` — Development setup, test suite, conventions for adding categories/patterns/commands
- `docs/README.md` — Documentation index (updated to include performance.md)
- `templates/vault.gitignore` — Ready-to-copy gitignore for vault git sync setup
- README.md: Documentation section pointing to `docs/`, troubleshooting entry for vault divergence across machines

### Fixed
- hooks/hooks.json structure: wrap hooks definition under top-level `hooks` key as required by Claude Code plugin runtime. Without this wrapper, plugin installation succeeds but hooks fail to load with a Zod validation error (expected: record, received: undefined).

## [2.0.0] - 2025-01-XX

### Added
- Initial v2.0.0 release as Claude Code plugin
- Stop hook for automatic session capture and consolidation
- SessionStart hook for injecting STRATA.md context into new sessions
- Commands: `/stratavarious`, `/strata`, `/strata-pause`, `/stratavarious-status`
- Scripts: setup, validate, clean, memory-build, status, write
- Vault system with categories: decisions, conventions, errors, patterns, skills, preferences, environment
- Secret scrubbing (8+ patterns) with safety guards
- Templates for MEMORY.md, STRATA.md, profiles, session buffer
- Unit tests for core hook functions (23 tests)
- Performance benchmarks for scrubSecrets, stripInvisibleUnicode, extractFromTranscript
- CI pipeline with shellcheck, Bash 3.2 compat, unit tests on ubuntu+macos

### Security
- Secret scrubbing prevents credentials from entering vault
- Symlink guards on write operations
- Lock-based atomic writes with stale lock detection
- Transcript path validation against traversal attacks

### Changed
- Migrated from v1 flat structure to per-project workspace layout
- BREAKING: vault directory moved to `~/.claude/workspace/stratavarious/memory/vault/`
- BREAKING: environment variable renamed from `StrataVarious_HOME` to `STRATAVARIOUS_HOME` (now fully uppercase, documented usage)

### Fixed
- Bash 3.2 compatibility (no arrays, no [[ =~ ]] with capture groups, no declare -A)
- Race conditions in concurrent writes via mkdir-based locking
- Frontmatter validation with proper YAML parsing

[Unreleased]: https://github.com/MisterKarott/stratavarious/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/MisterKarott/stratavarious/releases/tag/v2.0.0
