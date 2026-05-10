# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `scripts/stratavarious-prune.sh` — vault hygiene script. Detects: decay (error notes older than N days, configurable via `StrataVarious_PRUNE_AGE_DAYS`, default 60, not referenced by any other note → archive to `_archive/<year>/`), trivial notes (<5 content lines → delete), and semantic duplicates (Levenshtein distance < 3 or Jaccard token similarity > 70% on normalized titles within same category → manual merge). Dry-run by default. Flags: `--apply`, `--yes`, `--json`, `--age-days N`. Levenshtein implemented in pure awk (Bash 3.2 compatible, no external deps).
- `/strata-prune` skill — Claude Code skill that invokes the prune script.
- README: `## Vault hygiene` section documenting the doctor + prune + status workflow.
- `tests/integration/test-prune.sh` — 27 integration tests covering all candidate types, dry-run checksum guard, `--apply --yes` archive/delete, JSON output, and error handling.
- `tests/fixtures/prune-vault/` — test fixtures with decay candidates, trivial notes, duplicate pairs, recent notes, and referenced error notes.
- `scripts/stratavarious-search.sh` — full-text vault search with frontmatter filters and recency-based ranking. Score = `match_count × exp(-age_days/30)`. Filters: `--category`, `--project`, `--tag`, `--since=Nd`, `--global`. Flags: `--json` (machine output), `--limit=N` (default 10). Uses ripgrep with grep -r fallback.
- `/strata-search` skill — Claude Code skill that invokes the search script.
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
- Secret scrubber: new patterns for GitHub fine-grained PATs (`github_pat_...`), Google OAuth access tokens (`ya29....`), and Anthropic API keys (`sk-ant-...`)
- Strict mode (`STRATAVARIOUS_STRICT_SCRUB=1`): opt-in mid-line matching for `password=`, `api_key=`, `secret=`, etc.
- Entropy scan (`STRATAVARIOUS_ENTROPY_SCAN=1`): opt-in Shannon entropy detection for unknown token formats (threshold configurable via `STRATAVARIOUS_ENTROPY_THRESHOLD`, default 4.5 bits/char)
- 15 new unit tests covering all new patterns (positive and negative cases), entropy calculation, and strict mode

### Security
- Extended coverage for Anthropic, GitHub fine-grained PAT, and Google OAuth token formats

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
