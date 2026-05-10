#!/bin/bash
# test-search.sh — Integration tests for stratavarious-search.sh
# Bash 3.2 compatible

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SEARCH="$REPO_ROOT/scripts/stratavarious-search.sh"
FIXTURE_VAULT="$REPO_ROOT/tests/fixtures/search-vault"

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

assert_output_contains() {
    local output="$1"
    local pattern="$2"
    local desc="$3"
    if echo "$output" | grep -q "$pattern"; then
        log_pass "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$desc (pattern '$pattern' not found)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_output_not_contains() {
    local output="$1"
    local pattern="$2"
    local desc="$3"
    if echo "$output" | grep -q "$pattern"; then
        log_fail "$desc (pattern '$pattern' was found but should not be)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        log_pass "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
}

assert_exit_code() {
    local actual="$1"
    local expected="$2"
    local desc="$3"
    if [ "$actual" -eq "$expected" ]; then
        log_pass "$desc (exit $expected)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$desc (expected exit $expected, got $actual)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Point search at fixture vault
export StrataVarious_HOME
StrataVarious_HOME=$(mktemp -d)
trap 'rm -rf "$StrataVarious_HOME"' EXIT

# Set up memory/vault symlink from fixture
mkdir -p "$StrataVarious_HOME/memory"
cp -r "$FIXTURE_VAULT/." "$StrataVarious_HOME/memory/"
# Rename fixture top-level dirs into vault/
mkdir -p "$StrataVarious_HOME/memory/vault"
for d in decisions errors patterns; do
    if [ -d "$StrataVarious_HOME/memory/$d" ]; then
        mv "$StrataVarious_HOME/memory/$d" "$StrataVarious_HOME/memory/vault/$d"
    fi
done

echo ""
echo "=== stratavarious-search integration tests ==="
echo ""

# --- Test 1: basic query returns results ---
out=$(bash "$SEARCH" "rate limiting" 2>&1 || true)
assert_output_contains "$out" "Rate Limiting" "basic query finds rate-limiting note"

# --- Test 2: query with no results prints 'No results' ---
out=$(bash "$SEARCH" "xyzzy-not-found-ever" 2>&1 || true)
assert_output_contains "$out" "No results" "no-match query returns 'No results'"

# --- Test 3: --category filter ---
out=$(bash "$SEARCH" --category=decisions "auth" 2>&1 || true)
assert_output_contains "$out" "Authentication" "--category=decisions finds auth note"
assert_output_not_contains "$out" "Docker" "--category=decisions excludes errors category"

# --- Test 4: --category filter wrong category errors ---
exit_code=0
bash "$SEARCH" --category=nonexistent "query" > /dev/null 2>&1 || exit_code=$?
assert_exit_code "$exit_code" 2 "--category=nonexistent exits 2"

# --- Test 5: --project filter ---
out=$(bash "$SEARCH" --project=nemty "api" 2>&1 || true)
assert_output_contains "$out" "Rate Limiting\|API Retry\|Authentication" "--project=nemty returns nemty notes"
assert_output_not_contains "$out" "Docker Compose" "--project=nemty excludes global notes"

# --- Test 6: --global filter excludes project notes ---
out=$(bash "$SEARCH" --global "pattern" 2>&1 || true)
assert_output_contains "$out" "Old Pattern" "--global finds global notes"
assert_output_not_contains "$out" "API Retry" "--global excludes project-specific notes"

# --- Test 7: --tag filter ---
out=$(bash "$SEARCH" --tag=infra "api" 2>&1 || true)
assert_output_contains "$out" "API Retry" "--tag=infra finds tagged note"
assert_output_not_contains "$out" "Authentication" "--tag=infra excludes untagged note"

# --- Test 8: --since filter (recent notes) ---
out=$(bash "$SEARCH" --since=7d "pattern" 2>&1 || true)
assert_output_not_contains "$out" "Old Pattern" "--since=7d excludes 2024 note"

# --- Test 9: --limit flag ---
out=$(bash "$SEARCH" --limit=1 "api" 2>&1 || true)
result_count=$(echo "$out" | grep -c "^### " || true)
if [ "$result_count" -le 1 ]; then
    log_pass "--limit=1 returns at most 1 result (got $result_count)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_fail "--limit=1 returned $result_count results (expected <=1)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- Test 10: --json output ---
out=$(bash "$SEARCH" --json "rate limiting" 2>&1 || true)
assert_output_contains "$out" '"results"' "--json output contains 'results' key"
assert_output_contains "$out" '"score"' "--json output contains 'score' key"

# --- Test 11: ranking — more recent note scores higher ---
out=$(bash "$SEARCH" --json "api" 2>&1 || true)
# api-retry-pattern (2026-04-10) should rank higher than old-pattern (2024-01-15)
# Both match "api" but retry is recent; check "API Retry" appears before "Old Pattern" in JSON
api_retry_pos=$(echo "$out" | grep -o '"title":"[^"]*"' | grep -n "API Retry" | cut -d: -f1 || echo "99")
old_pattern_pos=$(echo "$out" | grep -o '"title":"[^"]*"' | grep -n "Old Pattern" | cut -d: -f1 || echo "99")
if [ -n "$api_retry_pos" ] && [ -n "$old_pattern_pos" ] && [ "$api_retry_pos" -lt "$old_pattern_pos" ]; then
    log_pass "ranking: recent note (API Retry 2026) ranks before old note (2024)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_fail "ranking: expected API Retry before Old Pattern (got positions $api_retry_pos vs $old_pattern_pos)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- Test 12: missing query exits 2 ---
exit_code=0
bash "$SEARCH" > /dev/null 2>&1 || exit_code=$?
assert_exit_code "$exit_code" 2 "missing query exits 2"

# --- Summary ---
echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
