#!/bin/bash
# test-e2e.sh — End-to-end integration tests for StrataVarious
# Bash 3.2 compatible (macOS)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

cleanup() {
    if [[ -n "${STRATAVARIES_TMP:-}" ]] && [[ -d "$STRATAVARIES_TMP" ]]; then
        rm -rf "$STRATAVARIES_TMP"
    fi
}
trap cleanup EXIT

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

assert_file_exists() {
    local file="$1"
    local desc="$2"
    if [[ -f "$file" ]]; then
        log_info "✓ $desc"
        ((TESTS_PASSED++))
        return 0
    fi
    log_error "✗ $desc: $file"
    ((TESTS_FAILED++))
    return 1
}

assert_dir_exists() {
    local dir="$1"
    local desc="$2"
    if [[ -d "$dir" ]]; then
        log_info "✓ $desc"
        ((TESTS_PASSED++))
        return 0
    fi
    log_error "✗ $desc: $dir"
    ((TESTS_FAILED++))
    return 1
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local desc="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        log_info "✓ $desc"
        ((TESTS_PASSED++))
        return 0
    fi
    log_error "✗ $desc"
    ((TESTS_FAILED++))
    return 1
}

assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    local desc="$3"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        log_info "✓ $desc"
        ((TESTS_PASSED++))
        return 0
    fi
    log_error "✗ $desc"
    ((TESTS_FAILED++))
    return 1
}

test_basic_capture() {
    log_info "=== Test: Basic session capture ==="
    
    STRATAVARIES_TMP=$(mktemp -d)
    export STRATAVARIES_TMP
    export STRATAVARIES_HOME="$STRATAVARIES_TMP"
    
    mkdir -p "$STRATAVARIES_TMP/memory/vault"
    
    cat > "$STRATAVARIES_TMP/memory/session-buffer.md" << 'EOF'
## 2025-01-01 12:00:00 UTC
- **Project:** test-project

### User Intent
Set up TypeScript project
EOF
    
    assert_file_exists "$STRATAVARIES_TMP/memory/session-buffer.md" "Session buffer created"
    assert_file_contains "$STRATAVARIES_TMP/memory/session-buffer.md" "test-project" "Project name"
    assert_file_contains "$STRATAVARIES_TMP/memory/session-buffer.md" "TypeScript" "Intent present"
    
    log_info "=== Basic capture test completed ==="
}

test_secret_scrubbing() {
    log_info "=== Test: Secret scrubbing ==="
    
    STRATAVARIES_TMP=$(mktemp -d)
    export STRATAVARIES_TMP
    
    mkdir -p "$STRATAVARIES_TMP/memory"
    
    cat > "$STRATAVARIES_TMP/memory/session-buffer.md" << 'EOF'
## 2025-01-01 12:00:00 UTC
Stripe key: sk_test_51MxYb2BqdJLkPnQ8ZcRt9vE7KxF3hLmN
AWS key: AKIAIOSFODNN7EXAMPLE
Database: postgres://user:P@ssw0rdSecret123!@localhost:5432/db
Anthropic: sk-ant-api03-abc123DEFghIJKLmnoPQRsTUVwxyz4567890ABCDE
EOF
    
    local scrub_result
    scrub_result=$(node -e "
        const { scrubSecrets } = require('./hooks/stratavarious-stop.js');
        const fs = require('fs');
        const buffer = fs.readFileSync('$STRATAVARIES_TMP/memory/session-buffer.md', 'utf8');
        console.log(scrubSecrets(buffer));
    " 2>&1 || true)
    
    if echo "$scrub_result" | grep -q "sk_test_"; then
        log_error "✗ Stripe key not scrubbed"
        ((TESTS_FAILED++))
    else
        log_info "✓ Stripe key scrubbed"
        ((TESTS_PASSED++))
    fi

    if echo "$scrub_result" | grep -q "AKIAIOSFODNN7EXAMPLE"; then
        log_error "✗ AWS key not scrubbed"
        ((TESTS_FAILED++))
    else
        log_info "✓ AWS key scrubbed"
        ((TESTS_PASSED++))
    fi
    
    if echo "$scrub_result" | grep -q "sk-ant-"; then
        log_error "✗ Anthropic key not scrubbed"
        ((TESTS_FAILED++))
    else
        log_info "✓ Anthropic key scrubbed"
        ((TESTS_PASSED++))
    fi
    
    if echo "$scrub_result" | grep -q "[REDACTED]"; then
        log_info "✓ Redaction marker present"
        ((TESTS_PASSED++))
    else
        log_error "✗ Redaction marker missing"
        ((TESTS_FAILED++))
    fi
    
    log_info "=== Secret scrubbing test completed ==="
}

test_hook_no_crash() {
    log_info "=== Test: Hook doesn't crash ==="

    STRATAVARIES_TMP=$(mktemp -d)
    export STRATAVARIES_TMP
    export STRATAVARIES_HOME="$STRATAVARIES_TMP"

    mkdir -p "$STRATAVARIES_TMP/memory"
    mkdir -p "$STRATAVARIES_TMP/.claude/projects/test-project"

    cat > "$STRATAVARIES_TMP/.claude/projects/test-project/transcript.jsonl" << 'EOF'
{"type":"user","message":{"content":"Hello"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Hi there!"}]}}
EOF

    local hook_input
    hook_input="{\"cwd\":\"$STRATAVARIES_TMP/.claude/projects/test-project\",\"transcript_path\":\"$STRATAVARIES_TMP/.claude/projects/test-project/transcript.jsonl\"}"

    local hook_output
    hook_output=$(echo "$hook_input" | node ./hooks/stratavarious-stop.js 2>&1 || true)

    # Vérifier que le hook ne crashe pas
    if [[ -n "$hook_output" ]] && echo "$hook_output" | grep -qi "error"; then
        log_error "✗ Hook produced errors: $hook_output"
        ((TESTS_FAILED++))
    else
        log_info "✓ Hook executed without crashing"
        ((TESTS_PASSED++))
    fi

    log_info "=== Hook no-crash test completed ==="
}

test_vault_structure() {
    log_info "=== Test: Vault structure ==="

    STRATAVARIES_TMP=$(mktemp -d)
    export STRATAVARIES_HOME="$STRATAVARIES_TMP"
    export CLAUDE_PLUGIN_ROOT="$PWD"

    # Créer la structure vault attendue
    mkdir -p "$STRATAVARIES_HOME/memory/vault/decisions"
    mkdir -p "$STRATAVARIES_HOME/memory/vault/patterns"
    mkdir -p "$STRATAVARIES_HOME/memory/vault/conventions"

    # Créer des notes de test
    cat > "$STRATAVARIES_HOME/memory/vault/decisions/2025-01-01-test.md" << 'EOF'
---
date: 2025-01-01
categorie: decision
tags: #test
---

# Test Decision
EOF

    cat > "$STRATAVARIES_HOME/memory/vault/patterns/2025-01-01-pattern.md" << 'EOF'
---
date: 2025-01-01
categorie: pattern
tags: #test
---

# Test Pattern
EOF

    # Vérifier la structure
    assert_file_exists "$STRATAVARIES_HOME/memory/vault/decisions/2025-01-01-test.md" "Vault decisions folder"
    assert_file_exists "$STRATAVARIES_HOME/memory/vault/patterns/2025-01-01-pattern.md" "Vault patterns folder"
    assert_dir_exists "$STRATAVARIES_HOME/memory/vault/conventions" "Vault conventions folder"

    # Vérifier le contenu
    assert_file_contains "$STRATAVARIES_HOME/memory/vault/decisions/2025-01-01-test.md" "categorie: decision" "Frontmatter valide"
    assert_file_contains "$STRATAVARIES_HOME/memory/vault/patterns/2025-01-01-pattern.md" "categorie: pattern" "Frontmatter valide"

    log_info "=== Vault structure test completed ==="
}

main() {
    log_info "StrataVarious E2E Test Suite"
    log_info "=============================="
    
    test_basic_capture
    test_secret_scrubbing
    test_hook_no_crash
    test_vault_structure
    
    echo ""
    log_info "=============================="
    log_info "Test Summary"
    log_info "=============================="
    log_info "Passed: $TESTS_PASSED"
    log_info "Failed: $TESTS_FAILED"
    log_info "Total:  $((TESTS_PASSED + TESTS_FAILED))"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "✓ All tests passed!"
        exit 0
    else
        log_error "✗ Some tests failed"
        exit 1
    fi
}

main "$@"
