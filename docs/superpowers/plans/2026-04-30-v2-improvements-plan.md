# StrataVarious v2.0 Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade StrataVarious to v2.0 with POSIX compatibility, per-project vault, security docs, file locking, and UX improvements.

**Architecture:** Five independent axes applied in priority order. Each task produces a working, testable state. POSIX compat is foundational — it must land first because scripts are modified in later tasks. Vault per-project is the biggest structural change and includes a migration path. The remaining tasks are additive.

**Tech Stack:** POSIX shell (sh/bash 3.2 compatible), Node.js (CommonJS, no deps), Claude Code plugin API (hooks, skills)

---

## Task 1: POSIX Compatibility — `stratavarious-validate.sh`

**Files:**
- Modify: `scripts/stratavarious-validate.sh`

- [ ] **Step 1: Rewrite validate.sh for POSIX compatibility**

Replace the full file content. Key changes: `[[ ]]` → `case`/`[ ]`, process substitution → pipe, `local` is POSIX in practice but keep `#!/bin/bash` since arrays are used.

```sh
#!/bin/bash
# validate.sh — Validate vault note frontmatter against the expected schema
# Usage: ./validate.sh [vault-dir]
# Exit 1 if any note is invalid
# Compatible with Bash 3.2 (macOS default)

set -euo pipefail

STRATAVARIOUS_HOME="${STRATAVARIOUS_HOME:-$HOME/.claude/workspace/stratavarious}"
VAULT_DIR="${1:-$STRATAVARIOUS_HOME/memory/vault}"

if [ ! -d "$VAULT_DIR" ]; then
  echo "Vault directory not found: $VAULT_DIR"
  exit 1
fi

VALID_CATEGORIES="decision convention error pattern skill preference environment"
ERRORS=0

validate_file() {
  local file="$1"
  local basename
  basename=$(basename "$file")

  local result
  result=$(awk '
  BEGIN { found_opening = 0; found_closing = 0; line_count = 0; fm_lines = "" }
  {
    line_count++
    if (NR == 1 && $0 == "---") {
      found_opening = 1
      next
    }
    if (found_opening && !found_closing && $0 == "---") {
      found_closing = 1
      exit
    }
    if (found_opening && !found_closing) {
      fm_lines = fm_lines $0 "\n"
    }
  }
  END {
    if (!found_opening) {
      print "MISSING_OPENING"
      exit
    }
    if (!found_closing) {
      print "UNCLOSED"
      exit
    }
    if (line_count < 2) {
      print "TOO_SHORT"
      exit
    }
    date = ""
    categorie = ""
    tags = ""
    n = split(fm_lines, lines, "\n")
    for (i = 1; i <= n; i++) {
      line = lines[i]
      if (match(line, /^date:[[:space:]]*/)) {
        date = substr(line, RSTART + RLENGTH)
      } else if (match(line, /^categorie:[[:space:]]*/)) {
        categorie = substr(line, RSTART + RLENGTH)
      } else if (match(line, /^category:[[:space:]]*/)) {
        if (categorie == "") categorie = substr(line, RSTART + RLENGTH)
      } else if (match(line, /^tags:[[:space:]]*/)) {
        tags = substr(line, RSTART + RLENGTH)
      }
    }
    print date "|" categorie "|" tags
  }
  ' "$file")

  case "$result" in
    MISSING_OPENING)
      echo "FAIL $basename — missing frontmatter opening ---"
      ERRORS=$((ERRORS + 1))
      return
      ;;
    UNCLOSED)
      echo "FAIL $basename — unclosed frontmatter"
      ERRORS=$((ERRORS + 1))
      return
      ;;
    TOO_SHORT)
      echo "FAIL $basename — invalid frontmatter (too short)"
      ERRORS=$((ERRORS + 1))
      return
      ;;
  esac

  local date categorie tags
  date=$(echo "$result" | cut -d'|' -f1)
  categorie=$(echo "$result" | cut -d'|' -f2)
  tags=$(echo "$result" | cut -d'|' -f3)

  if [ -z "$date" ]; then
    echo "FAIL $basename — missing date"
    ERRORS=$((ERRORS + 1))
  elif ! echo "$date" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "FAIL $basename — invalid date format: $date (expected YYYY-MM-DD)"
    ERRORS=$((ERRORS + 1))
  fi

  if [ -z "$categorie" ]; then
    echo "FAIL $basename — missing category"
    ERRORS=$((ERRORS + 1))
  elif ! echo " $VALID_CATEGORIES " | grep -q " $categorie "; then
    echo "FAIL $basename — invalid category: $categorie"
    ERRORS=$((ERRORS + 1))
  fi

  if [ -z "$tags" ]; then
    echo "FAIL $basename — missing tags"
    ERRORS=$((ERRORS + 1))
  fi
}

# Process all .md files (excluding journal/ and sessions/)
find "$VAULT_DIR" -type f -name "*.md" -print0 2>/dev/null | while IFS= read -r -d '' file; do
  case "$file" in
    */journal/*) continue ;;
    */sessions/*) continue ;;
  esac
  validate_file "$file"
done

if [ $ERRORS -eq 0 ]; then
  echo "All vault notes valid."
  exit 0
else
  echo "$ERRORS validation error(s) found."
  exit 1
fi
```

- [ ] **Step 2: Test validate.sh on macOS default bash**

Run: `/bin/bash scripts/stratavarious-validate.sh /nonexistent 2>&1 || true`
Expected: "Vault directory not found: /nonexistent"

Run: `mkdir -p /tmp/sv-test-vault && /bin/bash scripts/stratavarious-validate.sh /tmp/sv-test-vault`
Expected: "All vault notes valid." (empty vault)

Run: `rm -rf /tmp/sv-test-vault`

- [ ] **Step 3: Commit**

```bash
git add scripts/stratavarious-validate.sh
git commit -m "stratavarious v2.0 — POSIX compat: validate.sh"
```

---

## Task 2: POSIX Compatibility — `stratavarious-status.sh`

**Files:**
- Modify: `scripts/stratavarious-status.sh`

- [ ] **Step 1: Rewrite status.sh for POSIX compatibility**

The script already uses mostly POSIX constructs. Only issue: `set -uo pipefail` is fine in bash 3.2. No Bash 4+ features used. Keep as-is but verify.

No changes needed — the script is already Bash 3.2 compatible. Verify:

Run: `shellcheck scripts/stratavarious-status.sh`
Expected: no errors (or only style warnings)

- [ ] **Step 2: Commit if changes were needed**

No commit needed if script passes validation unchanged.

---

## Task 3: POSIX Compatibility — `stratavarious-clean.sh`

**Files:**
- Modify: `scripts/stratavarious-clean.sh`

- [ ] **Step 1: Rewrite clean.sh for Bash 3.2 compatibility**

Key changes: remove `declare -A` (associative arrays — Bash 4+), replace with temp file approach. Remove `[[ =~ ]]` regex matching — use `case` or grep instead. Remove process substitution `< <(...)`.

```sh
#!/bin/bash
# Compatible with Bash 3.2 (macOS default)
set -euo pipefail

STRATAVARIOUS_HOME="${STRATAVARIOUS_HOME:-$HOME/.claude/workspace/stratavarious}"
MEMORY_DIR="$STRATAVARIOUS_HOME/memory"
VAULT_DIR="$MEMORY_DIR/vault"

echo "--- StrataVarious Vault Cleaning ---"
echo ""

file_hash() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$1"
  else
    shasum "$1" | awk '{print $1}'
  fi
}

# Collect all vault files (excluding journal and sessions) into temp files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

find "$VAULT_DIR" -type f -name "*.md" -print0 2>/dev/null | while IFS= read -r -d '' file; do
  case "$file" in
    */journal/*) continue ;;
    */sessions/*) continue ;;
  esac
  echo "$file"
done > "$TMPDIR/files.txt"

FILE_COUNT=$(wc -l < "$TMPDIR/files.txt" | tr -d ' ')

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "No vault files found."
  exit 0
fi

echo "Found $FILE_COUNT vault files to analyze"
echo ""

# Pre-compute hashes and titles
DUPLICATES_FOUND=0

# Check for exact duplicates using sorted hashes
while IFS= read -r file; do
  h=$(file_hash "$file")
  echo "$h  $file"
done < "$TMPDIR/files.txt" | sort > "$TMPDIR/hashed.txt"

awk '
{
  hash = $1
  # Rebuild filename (may contain spaces)
  fname = ""
  for (i = 2; i <= NF; i++) {
    if (fname != "") fname = fname " "
    fname = fname $i
  }
  if (hash == prev_hash) {
    print "DUP: " prev_file
    print "DUP: " fname
  }
  prev_hash = hash
  prev_file = fname
}
' "$TMPDIR/hashed.txt" | while IFS= read -r line; do
  case "$line" in
    DUP:\ *)
      f=$(echo "$line" | sed 's/^DUP: //')
      echo "  - $(basename "$f")"
      DUPLICATES_FOUND=1
      ;;
  esac
done

# Check for similar titles using sorted normalized titles
while IFS= read -r file; do
  title=$(grep -m1 '^# ' "$file" 2>/dev/null | sed 's/^# //' | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  if [ -n "$title" ]; then
    echo "$title  $file"
  fi
done < "$TMPDIR/files.txt" | sort > "$TMPDIR/titles.txt"

awk '
{
  title = ""
  fname = ""
  # First field(s) = title (separated by double space from filename)
  # But titles may contain spaces — find the "  " separator
  sep = index($0, "  ")
  if (sep > 0) {
    title = substr($0, 1, sep - 1)
    fname = substr($0, sep + 2)
  }
  if (title == prev_title && title != "") {
    print "SIMILAR: " fname
    print "SIMILAR_PREV: " prev_file
  }
  prev_title = title
  prev_file = fname
}
' "$TMPDIR/titles.txt" | while IFS= read -r line; do
  case "$line" in
    SIMILAR:\ *)
      f=$(echo "$line" | sed 's/^SIMILAR: //')
      echo "  - $(basename "$f")"
      ;;
    SIMILAR_PREV:\ *)
      f=$(echo "$line" | sed 's/^SIMILAR_PREV: //')
      echo "  - $(basename "$f")"
      DUPLICATES_FOUND=1
      ;;
  esac
done

if [ "$DUPLICATES_FOUND" -eq 0 ]; then
  echo "No duplicates detected"
  echo ""
  echo "Vault is clean. To mark a note as deprecated, add to its frontmatter:"
  echo "  deprecated: true"
  echo "  deprecated_reason: Replaced by new-note.md on YYYY-MM-DD"
else
  echo ""
  echo "Action required: Review the files above and:"
  echo "  1. Merge content if they cover the same topic"
  echo "  2. Mark as deprecated if one is obsolete"
  echo "  3. Delete exact duplicates"
fi

echo ""
echo "--- End StrataVarious Vault Cleaning ---"
```

- [ ] **Step 2: Test clean.sh on macOS default bash**

Run: `mkdir -p /tmp/sv-clean-test/memory/vault && /bin/bash scripts/stratavarious-clean.sh`
Expected: "No vault files found." (empty vault)

Run: `rm -rf /tmp/sv-clean-test`

- [ ] **Step 3: Commit**

```bash
git add scripts/stratavarious-clean.sh
git commit -m "stratavarious v2.0 — POSIX compat: clean.sh (remove Bash 4+ features)"
```

---

## Task 4: POSIX Compatibility — `setup.sh`

**Files:**
- Modify: `scripts/setup.sh`

- [ ] **Step 1: Rewrite setup.sh for Bash 3.2 compatibility**

Current script already uses mostly POSIX-compatible constructs. The only Bash 4+ concern is `BASH_SOURCE` — but that's Bash 3.2 compatible. Check for `[[ ]]` usage — none found. The script is already Bash 3.2 compatible.

No changes needed. Verify:

Run: `shellcheck scripts/setup.sh`
Expected: no errors (or only style warnings)

- [ ] **Step 2: Commit if changes were needed**

No commit needed if script passes validation unchanged.

---

## Task 5: POSIX Compatibility — Update README and CI

**Files:**
- Modify: `README.md` (Requirements section)
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Update README Requirements section**

In `README.md`, replace:

```
- Bash 4+ (`scripts/` are POSIX-compatible shell)
```

With:

```
- Bash 3.2+ (macOS default works — all scripts are Bash 3.2 compatible)
```

- [ ] **Step 2: Add Bash 3.2 compat check to CI**

In `.github/workflows/ci.yml`, add after the "Shellcheck" step:

```yaml
      - name: Bash 3.2 compatibility check
        run: |
          # Verify scripts don't use Bash 4+ features (associative arrays, mapfile, etc.)
          for f in scripts/*.sh; do
            if grep -qE '(declare -A|mapfile|readarray|\$\{[a-zA-Z_]+,,\}|\[\[.*=\~)' "$f"; then
              echo "FAIL: $f uses Bash 4+ features"
              grep -nE '(declare -A|mapfile|readarray|\$\{[a-zA-Z_]+,,\}|\[\[.*=\~)' "$f"
              exit 1
            fi
          done
          echo "All scripts are Bash 3.2 compatible"
```

- [ ] **Step 3: Run tests to verify nothing broke**

Run: `cd stratavarious && npm test`
Expected: all tests pass

- [ ] **Step 4: Commit**

```bash
git add README.md .github/workflows/ci.yml
git commit -m "stratavarious v2.0 — POSIX compat: update docs and CI"
```

---

## Task 6: File Locking — `stratavarious-write.sh` wrapper

**Files:**
- Create: `scripts/stratavarious-write.sh`

- [ ] **Step 1: Create the flock wrapper script**

```sh
#!/bin/bash
# stratavarious-write.sh — File-locked vault write wrapper
# Called from the JS hook to ensure safe concurrent writes.
# Usage: stratavarious-write.sh <target-file> <content>
# If flock is not available, proceeds without locking (with warning).

set -euo pipefail

TARGET_FILE="$1"
shift

STRATAVARIOUS_HOME="${STRATAVARIOUS_HOME:-$HOME/.claude/workspace/stratavarious}"
LOCK_FILE="${STRATAVARIOUS_HOME}/memory/.vault.lock"

# Ensure parent directory exists
mkdir -p "$(dirname "$TARGET_FILE")"

# Try flock if available, otherwise proceed without locking
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  if ! flock -w 30 9; then
    echo "stratavarious: vault lock timeout (30s)" >&2
    exit 1
  fi
  # Write within lock
  cat >> "$TARGET_FILE"
  # Lock released when fd 9 closes at script exit
else
  echo "stratavarious: flock not found, writing without lock" >&2
  cat >> "$TARGET_FILE"
fi
```

- [ ] **Step 2: Test the wrapper**

Run: `echo "test line" | bash scripts/stratavarious-write.sh /tmp/sv-lock-test.md && cat /tmp/sv-lock-test.md`
Expected: "test line"

Run: `rm -f /tmp/sv-lock-test.md`

- [ ] **Step 3: Make executable and commit**

```bash
chmod +x scripts/stratavarious-write.sh
git add scripts/stratavarious-write.sh
git commit -m "stratavarious v2.0 — Add flock-based write wrapper"
```

---

## Task 7: File Locking — Integrate wrapper in stop hook

**Files:**
- Modify: `hooks/stratavarious-stop.js` (lines 377-384, the append section)

- [ ] **Step 1: Replace direct `fs.appendFileSync` with shell wrapper call**

In `hooks/stratavarious-stop.js`, replace the append block (lines 377-384):

```js
  // Append
  try {
    fs.mkdirSync(path.dirname(BUFFER_PATH), { recursive: true });
    fs.appendFileSync(BUFFER_PATH, entry, 'utf8');
  } catch (error) {
    logHookError(error, 'append-buffer');
    process.exit(0);
  }
```

With:

```js
  // Append via locked write wrapper
  try {
    fs.mkdirSync(path.dirname(BUFFER_PATH), { recursive: true });
    const scriptPath = path.join(__dirname, '..', 'scripts', 'stratavarious-write.sh');
    execSync(`bash "${scriptPath}" "${BUFFER_PATH}"`, { input: entry, encoding: 'utf8', timeout: 35000 });
  } catch (error) {
    // Fallback to direct write if wrapper fails
    try {
      fs.appendFileSync(BUFFER_PATH, entry, 'utf8');
    } catch (fbError) {
      logHookError(fbError, 'append-buffer-fallback');
    }
    logHookError(error, 'append-buffer');
    process.exit(0);
  }
```

- [ ] **Step 2: Test the hook still works**

Run: `mkdir -p /tmp/strata-test/memory && echo '{}' | STRATAVARIOUS_HOME=/tmp/strata-test node hooks/stratavarious-stop.js && cat /tmp/strata-test/memory/session-buffer.md`
Expected: session entry appended with timestamp and project info

- [ ] **Step 3: Commit**

```bash
git add hooks/stratavarious-stop.js
git commit -m "stratavarious v2.0 — Use flock wrapper for buffer writes"
```

---

## Task 8: File Locking — Integrate wrapper in setup.sh

**Files:**
- Modify: `scripts/setup.sh`

- [ ] **Step 1: Add flock lock around setup writes**

In `scripts/setup.sh`, wrap the directory creation and template copy section (lines 13-93) with a lock. Add after the variable declarations (line 11):

```sh
LOCK_FILE="$STRATAVARIOUS_HOME/memory/.vault.lock"

acquire_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    if ! flock -w 30 9; then
      echo "Error: vault lock timeout (30s)" >&2
      exit 1
    fi
  fi
}

acquire_lock
```

Add the `acquire_lock` call right before the `echo "StrataVarious setup..."` line.

- [ ] **Step 2: Test setup.sh**

Run: `STRATAVARIOUS_HOME=/tmp/sv-setup-test bash scripts/setup.sh`
Expected: Setup completes successfully, all files created

Run: `rm -rf /tmp/sv-setup-test`

- [ ] **Step 3: Commit**

```bash
git add scripts/setup.sh
git commit -m "stratavarious v2.0 — Add flock locking to setup.sh"
```

---

## Task 9: Vault Per-Project — Restructure setup.sh

**Files:**
- Modify: `scripts/setup.sh`

- [ ] **Step 1: Update setup.sh to create per-project vault structure**

Change the directory creation section. After `mkdir -p "$MEMORY_DIR"`, replace the old `VAULT_DIR` subdirectories with the new structure. The vault root is now `$MEMORY_DIR/vault` with per-project subdirs created on-demand.

Replace the directory structure block (approximately lines 17-18):

```sh
# Old:
mkdir -p "$MEMORY_DIR" "$VAULT_DIR" "$JOURNAL_DIR" "$SESSIONS_DIR"
```

With:

```sh
# Create base vault structure — per-project subdirs are created on-demand by hooks
mkdir -p "$MEMORY_DIR" "$VAULT_DIR" "$VAULT_DIR/_global"

# Create category subdirs inside _global
for cat in decisions conventions patterns errors skills environments; do
  mkdir -p "$VAULT_DIR/_global/$cat"
done
```

Remove the `JOURNAL_DIR` and `SESSIONS_DIR` variable declarations (they're no longer needed as top-level dirs).

- [ ] **Step 2: Add migration logic for existing flat vault**

After the directory creation, add migration block:

```sh
# Migrate existing flat vault to per-project structure (one-time)
MIGRATION_MARKER="$VAULT_DIR/.v2-migrated"
if [ ! -f "$MIGRATION_MARKER" ] && [ -d "$VAULT_DIR" ]; then
  # Move any .md files directly in vault/ (not in subdirs) to _global/
  for f in "$VAULT_DIR"/*.md; do
    [ -f "$f" ] || continue
    mv "$f" "$VAULT_DIR/_global/"
    echo "Migrated $(basename "$f") to _global/"
  done
  # Move old journal/ and sessions/ if they exist
  if [ -d "$VAULT_DIR/journal" ]; then
    mv "$VAULT_DIR/journal" "$VAULT_DIR/_global/journal"
    echo "Migrated journal/ to _global/"
  fi
  if [ -d "$VAULT_DIR/sessions" ]; then
    mv "$VAULT_DIR/sessions" "$VAULT_DIR/_global/sessions"
    echo "Migrated sessions/ to _global/"
  fi
  touch "$MIGRATION_MARKER"
  echo "Vault migrated to v2 per-project structure"
fi
```

- [ ] **Step 3: Test setup with migration**

Run: `mkdir -p /tmp/sv-migrate/memory/vault/journal /tmp/sv-migrate/memory/vault/sessions && echo "---\ndate: 2025-01-01\ncategorie: decision\ntags: test\n---\nTest note" > /tmp/sv-migrate/memory/vault/test-note.md && STRATAVARIOUS_HOME=/tmp/sv-migrate bash scripts/setup.sh`
Expected: "Migrated test-note.md to _global/", "Vault migrated to v2 per-project structure"

Run: `ls /tmp/sv-migrate/memory/vault/_global/`
Expected: test-note.md, categories dirs

Run: `rm -rf /tmp/sv-migrate`

- [ ] **Step 4: Commit**

```bash
git add scripts/setup.sh
git commit -m "stratavarious v2.0 — Per-project vault structure with migration"
```

---

## Task 10: Vault Per-Project — Update stop hook write path

**Files:**
- Modify: `hooks/stratavarious-stop.js`

- [ ] **Step 1: Add repo-aware vault path detection**

In `hooks/stratavarious-stop.js`, add a function after `getProjectName` (line ~136):

```js
function getRepoName(cwd) {
  try {
    const root = execSync('git rev-parse --show-toplevel', {
      cwd,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: 2000,
    }).trim();
    return path.basename(root);
  } catch {
    return getProjectName(cwd);
  }
}
```

- [ ] **Step 2: Update the buffer write to use repo-scoped path**

The session-buffer stays global (it's ephemeral). Only the vault write path changes. The buffer write at the end of `main()` stays as-is. The repo name is already captured as `project` metadata in the entry. The actual per-project vault path will be used by the `/stratavarious` consolidation skill (not the stop hook).

So: no change needed to the stop hook's write path. The `project` field in the buffer entry is sufficient for the consolidation skill to route notes to the correct project vault.

- [ ] **Step 3: Commit**

No commit needed for this task — the stop hook already captures project name correctly.

---

## Task 11: Vault Per-Project — Update session-start hook

**Files:**
- Modify: `hooks/stratavarious-session-start.js`

- [ ] **Step 1: Add profile.md loading**

After the STRATA.md loading logic (line ~48), add profile.md loading:

```js
const os = require('os');  // Add at top of file with other requires

// Inside main(), after the strataPath logic, add before the final process.stdout.write:
  const STRATAVARIOUS_HOME = process.env.STRATAVARIOUS_HOME || path.join(os.homedir(), '.claude', 'workspace', 'stratavarious');
  const profilePath = path.join(STRATAVARIOUS_HOME, 'memory', 'profile.md');

  if (fs.existsSync(profilePath)) {
    try {
      const profileContent = fs.readFileSync(profilePath, 'utf8').trim();
      if (profileContent.length > 50) {
        // Append to the existing additionalContext string
        result.additionalContext += '\n\n[StrataVarious] User profile loaded:\n\n' + profileContent;
      }
    } catch {
      // Profile unreadable — skip
    }
  }
```

The key change: add `os` to the requires at the top of the file, then in `main()` after building the `result` object (the existing STRATA.md loading), read profile.md and append it to `result.additionalContext` before `process.stdout.write(JSON.stringify(result))`.

- [ ] **Step 2: Test session-start hook**

Run: `echo '{"cwd":"/tmp"}' | node hooks/stratavarious-session-start.js`
Expected: `{}` (no STRATA.md at /tmp) — no crash

- [ ] **Step 3: Commit**

```bash
git add hooks/stratavarious-session-start.js
git commit -m "stratavarious v2.0 — Load profile.md at session start"
```

---

## Task 12: Vault Per-Project — Create profile.md template

**Files:**
- Modify: `templates/profile.md`

- [ ] **Step 1: Update profile.md template**

The current template exists but is minimal. Keep it as-is — it's already appropriate. The existing content at `templates/profile.md` has the right structure (Identity, Coding Preferences, Communication Style, Working Patterns, Stack).

No changes needed.

- [ ] **Step 2: No commit needed**

Template is already correct.

---

## Task 13: Security Documentation — README section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add Security section after "What stays private" table**

Insert after line 215 (the "No data ever leaves your machine..." paragraph):

```markdown

## Security

StrataVarious includes a built-in secret scanner that runs before any data enters the vault. It detects and redacts:

- API keys (Stripe, OpenAI, Anthropic, AWS, GitHub, Slack, Google)
- Bearer and Basic authentication headers
- Database connection strings (MongoDB, PostgreSQL, MySQL, Redis)
- Passwords in key-value assignments (`password=...`, `api_key: ...`)
- JWT tokens
- HTTP basic auth in URLs

**Important limitations:** The scanner uses pattern matching (regex). It cannot guarantee detection of all possible secret formats, especially:
- Custom or proprietary key formats
- Secrets embedded in non-standard locations
- Base64-encoded credentials that don't match known patterns

**Recommendations:**
- Avoid pasting raw secrets into Claude Code sessions
- Use environment variables or secret managers instead of hardcoding values
- Consider [gitleaks](https://github.com/gitleaks/gitleaks) or [trufflehog](https://github.com/trufflesecurity/trufflehog) as complementary tools for comprehensive secret detection

StrataVarious reduces the risk of secrets entering the vault, but does not eliminate it.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "stratavarious v2.0 — Add security limitations documentation"
```

---

## Task 14: Security Documentation — STRATAVARIOUS.md warning

**Files:**
- Modify: `templates/STRATAVARIOUS.md`

- [ ] **Step 1: Add security warning to working memory template**

Replace the current content of `templates/STRATAVARIOUS.md`:

```
# StrataVarious — Working Memory

> Last 3 sessions. When a 4th arrives, the oldest is ejected to the vault.
```

With:

```
# StrataVarious — Working Memory

> Last 3 sessions. When a 4th arrives, the oldest is ejected to the vault.

<!-- SECURITY NOTE: Session data is scrubbed of known secret patterns before storage.
     Avoid pasting raw credentials, API keys, or connection strings into sessions. -->
```

- [ ] **Step 2: Commit**

```bash
git add templates/STRATAVARIOUS.md
git commit -m "stratavarious v2.0 — Add security warning to working memory template"
```

---

## Task 15: UX — `.strataignore` support

**Files:**
- Modify: `hooks/stratavarious-stop.js`
- Create: `templates/.strataignore`

- [ ] **Step 1: Add .strataignore check in stop hook**

In `hooks/stratavarious-stop.js`, add a function after the existing helper functions (around line 149):

```js
function shouldIgnore(cwd) {
  try {
    const ignorePath = path.join(cwd, '.strataignore');
    if (!fs.existsSync(ignorePath)) return false;
    const patterns = fs.readFileSync(ignorePath, 'utf8')
      .split('\n')
      .map(l => l.trim())
      .filter(l => l && !l.startsWith('#'));
    // Simple check: if cwd matches any pattern, skip capture
    // Patterns are evaluated against the project directory
    return false; // .strataignore filters paths within sessions, not the whole session
  } catch {
    return false;
  }
}
```

In the `main()` function, add after the `STRATAVARIOUS_DISABLE` check (line ~294):

```js
  // Check for .strataignore in project root
  if (shouldIgnore(cwd)) process.exit(0);
```

Note: The `.strataignore` at this level would need to be a per-session ignore (skip capture entirely for this project). For path-level filtering within captured content, that's a consolidation concern. Keep it simple: if `.strataignore` exists and is non-empty, skip capture.

Actually, the simpler and more useful approach: `.strataignore` contains project paths to skip. The hook checks if the current project name matches any entry. Replace the function:

```js
function shouldIgnore(cwd) {
  try {
    const ignorePath = path.join(cwd, '.strataignore');
    if (!fs.existsSync(ignorePath)) return false;
    const content = fs.readFileSync(ignorePath, 'utf8').trim();
    // Non-empty .strataignore means "skip this project"
    return content.split('\n').some(l => l.trim() && !l.startsWith('#'));
  } catch {
    return false;
  }
}
```

- [ ] **Step 2: Create .strataignore template**

Create `templates/.strataignore`:

```
# StrataVarious ignore file
# Place at the root of any project where you don't want session capture.
# Any non-comment, non-empty line enables ignore mode for this project.
# Example patterns (informational — any content here activates ignore):
# temp/
# experiments/
# scratch/
```

- [ ] **Step 3: Test the ignore mechanism**

Run: `echo "skip" > /tmp/.strataignore && echo '{"cwd":"/tmp"}' | STRATAVARIOUS_HOME=/tmp/strata-test node hooks/stratavarious-stop.js; echo "exit: $?"`
Expected: exits 0, no buffer write

Run: `rm -f /tmp/.strataignore`

- [ ] **Step 4: Commit**

```bash
git add hooks/stratavarious-stop.js templates/.strataignore
git commit -m "stratavarious v2.0 — Add .strataignore support"
```

---

## Task 16: UX — `/strata-pause` skill

**Files:**
- Create: `skills/strata-pause/SKILL.md`

- [ ] **Step 1: Create the pause/resume skill**

Create `skills/strata-pause/SKILL.md`:

```markdown
---
name: strata-pause
description: Toggle capture pause — run once to pause, again to resume
---

# StrataVarious Pause

Toggle session capture on/off.

## When to use

- Exploratory sessions you don't want in the vault
- Debugging messy experiments
- Temporary breaks from capture

## Instructions

Check if the file `${STRATAVARIOUS_HOME}/memory/.stratavarious-paused` exists (where STRATAVARIOUS_HOME defaults to `~/.claude/workspace/stratavarious`).

**If it exists (currently paused):**
1. Delete the file
2. Tell the user: "Capture resumed."

**If it doesn't exist (currently active):**
1. Create the file with the current timestamp as content
2. Tell the user: "Capture paused. Run /strata-pause again to resume."
```

- [ ] **Step 2: Add pause check in stop hook**

In `hooks/stratavarious-stop.js`, in the `main()` function, add after the `STRATAVARIOUS_DISABLE` check (line ~294):

```js
  // Check for pause marker
  const pauseMarker = path.join(STRATAVARIOUS_HOME, 'memory', '.stratavarious-paused');
  if (fs.existsSync(pauseMarker)) process.exit(0);
```

- [ ] **Step 3: Test pause mechanism**

Run: `mkdir -p /tmp/strata-test/memory && touch /tmp/strata-test/memory/.stratavarious-paused && echo '{}' | STRATAVARIOUS_HOME=/tmp/strata-test node hooks/stratavarious-stop.js; echo "exit: $?"`
Expected: exits 0 immediately, no buffer write

Run: `rm -f /tmp/strata-test/memory/.stratavarious-paused`

- [ ] **Step 4: Commit**

```bash
git add skills/strata-pause/SKILL.md hooks/stratavarious-stop.js
git commit -m "stratavarious v2.0 — Add /strata-pause skill and hook check"
```

---

## Task 17: UX — Demo recording script

**Files:**
- Create: `scripts/demo-recording.sh`

- [ ] **Step 1: Create the demo recording script**

```sh
#!/bin/bash
# demo-recording.sh — Record an Asciinema demo of StrataVarious workflow
# Prerequisites: asciinema (brew install asciinema)
# Output: demo.cast (Asciinema v2 format) and demo.gif (if agg is installed)

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLUGIN_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
CAST_FILE="$PLUGIN_ROOT/demo.cast"

echo "StrataVarious Demo Recording"
echo "Output: $CAST_FILE"
echo ""

# Check for asciinema
if ! command -v asciinema >/dev/null 2>&1; then
  echo "Error: asciinema not found. Install with: brew install asciinema"
  exit 1
fi

echo "Recording will start. Follow the prompts to demonstrate:"
echo "  1. A Claude Code session with context"
echo "  2. Running /stratavarious consolidation"
echo "  3. Starting a new session with restored context"
echo ""
echo "Press Ctrl+D when done recording."
echo ""

asciinema rec "$CAST_FILE" --overwrite

echo ""
echo "Recording saved to: $CAST_FILE"

# Convert to GIF if agg is available
if command -v agg >/dev/null 2>&1; then
  GIF_FILE="$PLUGIN_ROOT/demo.gif"
  agg "$CAST_FILE" "$GIF_FILE"
  echo "GIF saved to: $GIF_FILE"
else
  echo "Tip: Install agg (cargo install asciiinema-aggregate) to generate a GIF"
fi
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x scripts/demo-recording.sh
git add scripts/demo-recording.sh
git commit -m "stratavarious v2.0 — Add demo recording script"
```

---

## Task 18: Update README — Architecture section for v2

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Architecture diagram in README**

Replace the architecture section (lines 160-177) with the new per-project structure:

```markdown
## Architecture

```
<your-project>/
├── STRATA.md                   ← Portable handoff (written by /strata, injected at next SessionStart)
└── .strataignore               ← (optional) Skip capture for this project

~/.claude/workspace/stratavarious/
└── memory/
    ├── STRATAVARIOUS.md        ← Working memory (last 3 sessions, auto-loaded)
    ├── MEMORY.md               ← Vault index (auto-loaded by Claude at session start)
    ├── profile.md              ← Developer preferences and work patterns (global)
    ├── session-buffer.md       ← Raw capture from Stop hook (gitignored)
    └── vault/
        ├── _global/            ← Cross-project knowledge
        │   ├── decisions/
        │   ├── conventions/
        │   ├── patterns/
        │   ├── errors/
        │   ├── skills/
        │   └── environments/
        ├── my-project/         ← Per-project knowledge
        │   ├── decisions/
        │   ├── ...
        └── another-project/
            └── ...
```

The vault is designed to be human-readable. Every file is plain Markdown. You can browse, edit, or delete entries manually. The system won't break if you rearrange things.
```

- [ ] **Step 2: Update Commands table — add /strata-pause**

Add to the commands table:

```
| `/strata-pause` | Toggle session capture on/off — pause for exploratory sessions, resume when ready |
```

- [ ] **Step 3: Update Scripts table — add new scripts**

Add to the scripts table:

```
| `scripts/stratavarious-write.sh` | File-locked append wrapper — ensures safe concurrent vault writes |
| `scripts/demo-recording.sh` | Record an Asciinema demo of the StrataVarious workflow |
```

- [ ] **Step 4: Update version badge**

Replace `1.6.0` with `2.0.0` in the badge URL (line 3).

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "stratavarious v2.0 — Update README for v2 architecture"
```

---

## Task 19: Bump version to 2.0.0

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `package.json`

- [ ] **Step 1: Update version in plugin.json**

Change `"version": "1.6.0"` to `"version": "2.0.0"` in `.claude-plugin/plugin.json`.

- [ ] **Step 2: Update version in package.json**

Change `"version": "1.6.0"` to `"version": "2.0.0"` in `package.json`.

- [ ] **Step 3: Run full test suite**

Run: `npm test`
Expected: all tests pass

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json package.json
git commit -m "stratavarious v2.0.0 — Version bump"
```

---

## Task 20: Final validation

**Files:**
- All project files

- [ ] **Step 1: Run npm run validate**

Run: `npm run validate`
Expected: lint + tests all pass

- [ ] **Step 2: Run shellcheck on all scripts**

Run: `shellcheck scripts/*.sh`
Expected: no errors

- [ ] **Step 3: Test stop hook end-to-end**

Run: `rm -rf /tmp/sv-e2e && mkdir -p /tmp/sv-e2e/memory && echo '{}' | STRATAVARIOUS_HOME=/tmp/sv-e2e node hooks/stratavarious-stop.js && cat /tmp/sv-e2e/memory/session-buffer.md`
Expected: session entry with timestamp, project, cwd fields

- [ ] **Step 4: Test session-start hook**

Run: `echo '{"cwd":"/tmp"}' | node hooks/stratavarious-session-start.js`
Expected: `{}` — no crash

- [ ] **Step 5: Test with pause active**

Run: `touch /tmp/sv-e2e/memory/.stratavarious-paused && echo '{}' | STRATAVARIOUS_HOME=/tmp/sv-e2e node hooks/stratavarious-stop.js && wc -l /tmp/sv-e2e/memory/session-buffer.md`
Expected: line count unchanged (pause prevented write)

- [ ] **Step 6: Test with .strataignore**

Run: `rm /tmp/sv-e2e/memory/.stratavarious-paused && echo "skip" > /tmp/.strataignore && echo '{}' | STRATAVARIOUS_HOME=/tmp/sv-e2e node hooks/stratavarious-stop.js && wc -l /tmp/sv-e2e/memory/session-buffer.md`
Expected: line count unchanged (ignore prevented write)

- [ ] **Step 7: Cleanup**

Run: `rm -rf /tmp/sv-e2e /tmp/.strataignore`

- [ ] **Step 8: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "stratavarious v2.0.0 — Final fixes from validation"
```
