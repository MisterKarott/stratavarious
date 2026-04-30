#!/bin/bash
# stratavarious-write.sh — POSIX-atomic vault write wrapper (no flock dependency)
# Called from the JS hook to ensure safe concurrent writes.
# Usage: stratavarious-write.sh <target-file>  (reads content from stdin)
# Uses mkdir-based locking — works on all Unix systems including macOS.

set -euo pipefail

TARGET_FILE="$1"
shift

STRATAVARIOUS_HOME="${STRATAVARIOUS_HOME:-$HOME/.claude/workspace/stratavarious}"
LOCK_DIR="${STRATAVARIOUS_HOME}/memory/.vault.lock.d"
LOCK_PID_FILE="${LOCK_DIR}/pid"
LOCK_TIMEOUT=30

# Ensure parent directory exists
mkdir -p "$(dirname "$TARGET_FILE")"

# Refuse to write to a symlink (defense against symlink redirection attacks)
if [ -L "$TARGET_FILE" ]; then
  echo "stratavarious: refusing to write to symlink: $TARGET_FILE" >&2
  exit 1
fi

# Acquire lock via atomic mkdir (POSIX, works on macOS without flock)
acquire_lock() {
  local elapsed=0
  while [ "$elapsed" -lt "$LOCK_TIMEOUT" ]; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      echo "$$" > "$LOCK_PID_FILE"
      return 0
    fi
    # Lock held — check if holder is still alive (stale lock detection)
    if [ -f "$LOCK_PID_FILE" ]; then
      local lock_pid
      lock_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null || echo 0)
      if [ "$lock_pid" -ne 0 ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
        continue
      fi
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

release_lock() {
  rm -f "$LOCK_PID_FILE" 2>/dev/null
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

trap release_lock EXIT

if ! acquire_lock; then
  echo "stratavarious: vault lock timeout (${LOCK_TIMEOUT}s)" >&2
  exit 1
fi

cat >> "$TARGET_FILE"
