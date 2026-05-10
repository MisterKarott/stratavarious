#!/bin/bash
# test-doctor.sh — Integration tests for stratavarious-doctor.sh
# Bash 3.2 compatible

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$REPO_ROOT/scripts/stratavarious-doctor.sh"
BROKEN_VAULT="$REPO_ROOT/tests/fixtures/broken-vault"

log_info() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

assert_output_contains() {
    local output="$1"
    local pattern="$2"
    local desc="$3"
    if echo "$output" | grep -q "$pattern"; then
        log_info "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "$desc (pattern '$pattern' not found in output)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_output_not_contains() {
    local output="$1"
    local pattern="$2"
    local desc="$3"
    if ! echo "$output" | grep -q "$pattern"; then
        log_info "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "$desc (pattern '$pattern' should NOT be present)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_exit_code() {
    local actual="$1"
    local expected="$2"
    local desc="$3"
    if [ "$actual" -eq "$expected" ]; then
        log_info "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "$desc (expected exit $expected, got $actual)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "=== Doctor Integration Tests ==="

# Run doctor on broken vault, capture output and exit code
exit_code=0
output=$(bash "$DOCTOR" "$BROKEN_VAULT" 2>&1) || exit_code=$?

# Test 1: exits 2 (errors) on broken vault
assert_exit_code "$exit_code" 2 "exits 2 (errors) on broken vault"

# Test 2: detects broken link (ghost.md referenced but missing)
assert_output_contains "$output" "ghost\.md" "detects broken link: ghost.md"

# Test 3: detects orphan (orphan.md in vault but not in MEMORY.md)
assert_output_contains "$output" "orphan\.md" "detects orphan: orphan.md not referenced"

# Test 4: detects future date
assert_output_contains "$output" "future-date\.md" "detects future date in future-date.md"

# Test 5: detects date before 2020
assert_output_contains "$output" "old-date\.md" "detects old date in old-date.md"

# Test 6: detects malformed tags
assert_output_contains "$output" "bad-tags\.md" "detects malformed tags in bad-tags.md"

# Test 7: detects duplicate titles (dup-title-a.md mentioned)
assert_output_contains "$output" "dup-title-a\.md" "detects duplicate title: dup-title-a.md"

# Test 8: detects duplicate titles (dup-title-b.md mentioned)
assert_output_contains "$output" "dup-title-b\.md" "detects duplicate title: dup-title-b.md"

# Test 9: --json flag produces JSON (starts with {)
json_exit=0
json_output=$(bash "$DOCTOR" --json "$BROKEN_VAULT" 2>&1) || json_exit=$?
assert_output_contains "$json_output" "^{" "--json output starts with {"

# Test 10: clean vault exits 0
TMPDIR_CLEAN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CLEAN"' EXIT
mkdir -p "$TMPDIR_CLEAN/decisions"

cat > "$TMPDIR_CLEAN/MEMORY.md" << 'MEMEOF'
# StrataVarious Vault — Index

## Decisions

- `clean-note.md` — Clean Note
MEMEOF

cat > "$TMPDIR_CLEAN/decisions/clean-note.md" << 'NOTEEOF'
---
date: 2025-06-01
categorie: decision
tags: "#clean #test"
projet: test
---

# Clean Note

Everything is in order.
NOTEEOF

clean_exit=0
clean_output=$(bash "$DOCTOR" "$TMPDIR_CLEAN" 2>&1) || clean_exit=$?
assert_exit_code "$clean_exit" 0 "clean vault exits 0"

echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
[ "$TESTS_FAILED" -eq 0 ] && exit 0 || exit 1
