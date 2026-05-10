# Contributing to StrataVarious

## Prerequisites

- Bash 3.2+ (macOS default)
- Node.js 20+
- Claude Code (for end-to-end testing)

No `npm install` is required. The project has no runtime dependencies.

## Local setup

```bash
git clone https://github.com/MisterKarott/stratavarious.git
cd stratavarious
git checkout -b feature/your-change
```

## Running tests

```bash
# Unit tests (hook functions)
node tests/unit.mjs

# End-to-end tests (scripts, validate, write)
bash tests/e2e.sh

# Performance benchmarks
node tests/bench.mjs

# Shellcheck (all .sh scripts)
shellcheck -s bash scripts/*.sh hooks/*.sh 2>/dev/null || shellcheck -s bash scripts/*.sh

# Frontmatter validation
bash scripts/stratavarious-validate.sh
```

CI runs all of these automatically on each push. All checks must be green before merging to `develop`.

## Project conventions

**Bash 3.2 strict.** All shell scripts must run on macOS's default Bash (3.2). Do not use:
- `declare -A` (associative arrays)
- `mapfile` / `readarray`
- `${var,,}` or `${var^^}` (case transformation)
- `[[ =~ ]]` with capture groups

Use `case`, `tr`, `sed`, `awk` instead.

**Hook resilience.** The JS hooks must never crash. Wrap everything in `try/catch` and exit 0.

**No new dependencies.** The runtime must remain pure bash + node. If you think a dependency is genuinely necessary, open an issue first.

**Shellcheck clean.** New scripts must pass `shellcheck -s bash` without warnings. If a warning is a false positive, add an inline `# shellcheck disable=SCxxxx` with a comment explaining why.

**Version sync.** When bumping the version, update both `plugin.json` and `package.json`.

## Adding a vault category

Vault categories are whitelisted in the frontmatter schema:

```
decision | convention | error | pattern | skill | preference | environment
```

To add a category:

1. Add the new value to the `categorie` whitelist in `scripts/stratavarious-validate.sh`.
2. Document the category semantics in `docs/architecture.md` (vault note schema section).
3. Add a test case in `tests/e2e.sh` that validates a note with the new category.
4. Update the vault note frontmatter schema in `docs/architecture.md`.

## Adding a secret scrubber pattern

The scrubber lives in `hooks/stratavarious-stop.js`, function `scrubSecrets`.

1. Add the regex to the `PATTERNS` array in `scrubSecrets`.
2. Add a positive test (secret detected) and a negative test (normal string not redacted) in `tests/unit.mjs`.
3. Verify the tests pass with `node tests/unit.mjs`.

Pattern requirements:
- Must be anchored or scoped to avoid false positives
- Must replace the secret value, not the key
- Must use a stable placeholder like `[REDACTED]`

## Adding a command (skill)

Commands are Claude Code skills stored in `skills/`.

1. Create `skills/your-command/SKILL.md`.
2. Register it in `.claude-plugin/plugin.json` under `skills`.
3. Write the skill in English (SKILL.md language convention).
4. Add an entry to the Commands table in `README.md`.
5. Document the trigger conditions clearly in the skill description field.

## Commit style

Follow Conventional Commits:

```
feat: add semantic deduplication
fix: repair lock timeout on macOS 13
docs: update sync.md with NAS instructions
test: add unit test for JWT scrubbing
chore: bump version to 2.1.0
perf: reduce memory-build scan time
refactor: extract buffer parser to separate function
```

Do not use "wip", "fix typo", or "address review" in the final commit history. Squash if needed before merging.

## Merge process

1. Work on a feature branch from `develop`.
2. Run the full test suite before opening a PR.
3. Update `CHANGELOG.md` under `## [Unreleased]` (Added / Changed / Fixed / Security sections).
4. Merge to `develop`. Never merge directly to `main` — releases are tagged from `develop` by the maintainer.

## Reporting bugs

Open an issue on GitHub. Include:

- StrataVarious version (`cat .claude-plugin/plugin.json | grep version`)
- OS and Bash version (`bash --version`)
- The error message from `.hook-errors.log` if applicable
- Steps to reproduce
