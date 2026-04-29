#!/bin/bash

STRATAVARIOUS_HOME="${STRATAVARIOUS_HOME:-$HOME/.claude/workspace/stratavarious}"
MEMORY_DIR="$STRATAVARIOUS_HOME/memory"
VAULT_DIR="$MEMORY_DIR/vault"
SESSION_BUFFER="$MEMORY_DIR/session-buffer.md"
STRATAVARIOUS_MD="$MEMORY_DIR/STRATAVARIOUS.md"

echo "--- StrataVarious Status ---"

# Guard: check vault exists
if [ ! -d "$VAULT_DIR" ]; then
  echo "Vault not initialized. Run setup.sh first."
  echo "--- End StrataVarious Status ---"
  exit 1
fi

# 1. Number of notes in vault/
NUM_VAULT_NOTES=$(find "$VAULT_DIR" -type f -name "*.md" | wc -l | tr -d ' ')
echo "Notes in vault: $NUM_VAULT_NOTES"

# 2. Size of vault/
VAULT_SIZE=$(du -sh "$VAULT_DIR" 2>/dev/null | awk '{print $1}')
echo "Vault size: $VAULT_SIZE"

# 3. Last consolidation date
if [ -f "$STRATAVARIOUS_MD" ]; then
  LAST_CONSOLIDATION_DATE=$(grep -E "## Session — [0-9]{4}-[0-9]{2}-[0-9]{2}" "$STRATAVARIOUS_MD" | tail -n 1 | sed -E 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/')
  if [ -z "$LAST_CONSOLIDATION_DATE" ]; then
    LAST_CONSOLIDATION_DATE="N/A (No sessions found in STRATAVARIOUS.md)"
  fi
else
  LAST_CONSOLIDATION_DATE="N/A (STRATAVARIOUS.md not found — run setup first)"
fi
echo "Last session consolidated: $LAST_CONSOLIDATION_DATE"

# 4. Sessions awaiting consolidation in session-buffer.md
if [ ! -f "$SESSION_BUFFER" ]; then
  echo "Session buffer: Not found (run setup first)"
else
  NUM=$(grep -cE '^## ' "$SESSION_BUFFER" 2>/dev/null || echo 0)
  if [ "$NUM" -eq 0 ]; then
    echo "Session buffer: Empty"
  else
    echo "Session buffer: $NUM session(s) awaiting consolidation."
  fi
fi

echo "--- End StrataVarious Status ---"
