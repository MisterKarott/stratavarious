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
