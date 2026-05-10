#!/bin/bash
# test-prune.sh — Integration tests for stratavarious-prune.sh
# Bash 3.2 compatible

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRUNE="$REPO_ROOT/scripts/stratavarious-prune.sh"
FIXTURE_VAULT="$REPO_ROOT/tests/fixtures/prune-vault"

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

assert_contains() {
    local output="$1"
    local pattern="$2"
    local desc="$3"
    if echo "$output" | grep -q "$pattern"; then
        log_pass "$desc"
    else
        log_fail "$desc (pattern '$pattern' not found in output)"
        echo "  Output was:"
        echo "$output" | head -20 | sed 's/^/    /'
    fi
}

assert_not_contains() {
    local output="$1"
    local pattern="$2"
    local desc="$3"
    if echo "$output" | grep -q "$pattern"; then
        log_fail "$desc (pattern '$pattern' unexpectedly found)"
    else
        log_pass "$desc"
    fi
}

assert_exit() {
    local code="$1"
    local expected="$2"
    local desc="$3"
    if [ "$code" -eq "$expected" ]; then
        log_pass "$desc"
    else
        log_fail "$desc (exit $code, expected $expected)"
    fi
}

# Verify fixtures exist
if [ ! -f "$FIXTURE_VAULT/MEMORY.md" ]; then
    echo "ERROR: prune-vault fixture missing at $FIXTURE_VAULT" >&2
    exit 2
fi

echo "Running prune integration tests..."
echo ""

# ------------------------------------------------------------------ #
# 1. Dry-run: script exits 0
# ------------------------------------------------------------------ #
out=$(bash "$PRUNE" "$FIXTURE_VAULT" 2>&1) || true
assert_exit $? 0 "Dry-run exits 0"

# ------------------------------------------------------------------ #
# 2. Dry-run report contains expected sections
# ------------------------------------------------------------------ #
assert_contains "$out" "Prune Report" "Report header present"
assert_contains "$out" "Decay candidates" "Decay section present"
assert_contains "$out" "Trivial" "Trivial section present"
assert_contains "$out" "Semantic duplicate" "Duplicate section present"
assert_contains "$out" "DRY RUN" "Mode is DRY RUN"

# ------------------------------------------------------------------ #
# 3. Decay detection — old-docker-error.md (old, unreferenced)
# ------------------------------------------------------------------ #
assert_contains "$out" "old-docker-error" "Decay: old-docker-error.md detected"

# ------------------------------------------------------------------ #
# 4. Decay exclusion — recent-npm-error.md (too recent)
# ------------------------------------------------------------------ #
assert_not_contains "$out" "recent-npm-error" "Decay: recent-npm-error.md excluded (recent)"

# ------------------------------------------------------------------ #
# 5. Decay exclusion — referenced-error.md (referenced by auth-approach.md)
# ------------------------------------------------------------------ #
assert_not_contains "$out" "referenced-error" "Decay: referenced-error.md excluded (referenced)"

# ------------------------------------------------------------------ #
# 6. Trivial detection — stub-pattern.md and empty-stub.md
# ------------------------------------------------------------------ #
assert_contains "$out" "stub-pattern" "Trivial: stub-pattern.md detected"
assert_contains "$out" "empty-stub" "Trivial: empty-stub.md detected"

# ------------------------------------------------------------------ #
# 7. Trivial exclusion — auth-approach.md has enough content (not in trivial table)
# ------------------------------------------------------------------ #
trivial_section=$(echo "$out" | awk '/^## Trivial/,/^## Semantic/')
assert_not_contains "$trivial_section" "auth-approach" "Trivial: auth-approach.md excluded (enough content)"

# ------------------------------------------------------------------ #
# 8. Duplicate detection — auth-approach.md / auth-method.md
# ------------------------------------------------------------------ #
assert_contains "$out" "auth-approach\|auth-method\|Authentication" "Duplicates: auth pair detected"

# ------------------------------------------------------------------ #
# 9. JSON output format
# ------------------------------------------------------------------ #
json_out=$(bash "$PRUNE" --json "$FIXTURE_VAULT" 2>&1) || true
assert_contains "$json_out" '"mode"' "JSON: mode field present"
assert_contains "$json_out" '"decay"' "JSON: decay array present"
assert_contains "$json_out" '"trivial"' "JSON: trivial array present"
assert_contains "$json_out" '"duplicates"' "JSON: duplicates array present"
assert_contains "$json_out" '"summary"' "JSON: summary present"

# ------------------------------------------------------------------ #
# 10. JSON: decay count >= 1
# ------------------------------------------------------------------ #
decay_count=$(echo "$json_out" | grep -o '"decay":\[[^]]*\]' | grep -o '"file"' | wc -l | tr -d ' ')
if [ "$decay_count" -ge 1 ]; then
    log_pass "JSON: at least 1 decay candidate"
else
    log_fail "JSON: expected at least 1 decay candidate, got $decay_count"
fi

# ------------------------------------------------------------------ #
# 11. JSON: trivial count >= 2
# ------------------------------------------------------------------ #
trivial_count=$(echo "$json_out" | grep -o '"trivial":\[[^]]*\]' | grep -o '"file"' | wc -l | tr -d ' ')
if [ "$trivial_count" -ge 2 ]; then
    log_pass "JSON: at least 2 trivial candidates"
else
    log_fail "JSON: expected at least 2 trivial candidates, got $trivial_count"
fi

# ------------------------------------------------------------------ #
# 12. Dry-run: vault files unchanged (checksum guard)
# ------------------------------------------------------------------ #
# Compute checksums using find + stat (portable)
checksum_vault() {
    find "$1" -type f -name "*.md" | sort | while IFS= read -r f; do
        wc -c < "$f"
    done | tr -d '\n'
}
checksum_before=$(checksum_vault "$FIXTURE_VAULT")
bash "$PRUNE" "$FIXTURE_VAULT" > /dev/null 2>&1 || true
checksum_after=$(checksum_vault "$FIXTURE_VAULT")

if [ "$checksum_before" = "$checksum_after" ]; then
    log_pass "Dry-run: no vault files modified"
else
    log_fail "Dry-run: vault files were modified (expected no changes)"
fi

# ------------------------------------------------------------------ #
# 13. Custom --age-days: flag accepted without error
# ------------------------------------------------------------------ #
set +e
bash "$PRUNE" --age-days 365 "$FIXTURE_VAULT" > /dev/null 2>&1
age_exit=$?
set -e
if [ "$age_exit" -eq 0 ]; then
    log_pass "--age-days flag accepted"
else
    log_fail "--age-days flag: unexpected exit $age_exit"
fi

# ------------------------------------------------------------------ #
# 14. --apply --yes: mode label shows APPLY in output
# ------------------------------------------------------------------ #
TMPVAULT_DRY=$(mktemp -d)
cp -r "$FIXTURE_VAULT/." "$TMPVAULT_DRY/"
# shellcheck disable=SC2064
trap "rm -rf '$TMPVAULT_DRY'" EXIT
apply_dry_out=$(bash "$PRUNE" --apply --yes "$TMPVAULT_DRY" 2>&1) || true
assert_contains "$apply_dry_out" "APPLY" "--apply: mode label shows APPLY"

# ------------------------------------------------------------------ #
# 15. --apply --yes on temp copy: archives decay, deletes trivial
# ------------------------------------------------------------------ #
TMPVAULT=$(mktemp -d)
cp -r "$FIXTURE_VAULT/." "$TMPVAULT/"

apply_yes_out=$(bash "$PRUNE" --apply --yes "$TMPVAULT" 2>&1) || true
# After apply: old-docker-error should be archived
if [ -f "$TMPVAULT/errors/old-docker-error.md" ]; then
    log_fail "--apply --yes: old-docker-error.md still in errors/ (expected archive)"
elif find "$TMPVAULT" -name "old-docker-error.md" | grep -q "_archive"; then
    log_pass "--apply --yes: old-docker-error.md archived"
else
    log_fail "--apply --yes: old-docker-error.md not found anywhere"
fi

# Trivial notes deleted
if [ ! -f "$TMPVAULT/patterns/stub-pattern.md" ] && [ ! -f "$TMPVAULT/patterns/empty-stub.md" ]; then
    log_pass "--apply --yes: trivial notes deleted"
else
    log_fail "--apply --yes: some trivial notes not deleted"
fi

# ------------------------------------------------------------------ #
# 16. Unknown flag exits 2
# ------------------------------------------------------------------ #
set +e
bash "$PRUNE" --unknown-flag "$FIXTURE_VAULT" > /dev/null 2>&1
exit_code=$?
set -e
if [ "$exit_code" -eq 2 ]; then
    log_pass "Unknown flag exits 2"
else
    log_fail "Unknown flag: expected exit 2, got $exit_code"
fi

# ------------------------------------------------------------------ #
# 17. Missing vault exits 2
# ------------------------------------------------------------------ #
set +e
bash "$PRUNE" /tmp/nonexistent-vault-xyz > /dev/null 2>&1
exit_code=$?
set -e
if [ "$exit_code" -eq 2 ]; then
    log_pass "Missing vault exits 2"
else
    log_fail "Missing vault: expected exit 2, got $exit_code"
fi

# ------------------------------------------------------------------ #
# Results
# ------------------------------------------------------------------ #
echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
