# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- marketplace.json enabling plugin installation via `claude plugin install github.com/MisterKarott/stratavarious`
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
