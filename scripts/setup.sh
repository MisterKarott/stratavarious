#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLUGIN_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
STRATAVARIOUS_HOME="${STRATAVARIOUS_HOME:-$HOME/.claude/workspace/stratavarious}"
MEMORY_DIR="$STRATAVARIOUS_HOME/memory"
VAULT_DIR="$MEMORY_DIR/vault"
JOURNAL_DIR="$VAULT_DIR/journal"
SESSIONS_DIR="$VAULT_DIR/sessions"
TEMPLATE_DIR="$PLUGIN_ROOT/templates"

echo "StrataVarious setup..."
echo "Vault path: $STRATAVARIOUS_HOME"

# 1. Create directory structure
mkdir -p "$MEMORY_DIR" "$VAULT_DIR" "$JOURNAL_DIR" "$SESSIONS_DIR"

# 2. Copy templates (only if not already existing)
# MEMORY.md gets special merge treatment (see step 2b)
for file in STRATAVARIOUS.md profile.md session-buffer.md; do
  TARGET="$MEMORY_DIR/$file"
  if [ ! -f "$TARGET" ]; then
    cp "$TEMPLATE_DIR/$file" "$TARGET"
    echo "Created $file"
  else
    echo "$file already exists, skipping"
  fi
done

# 2b. MEMORY.md: create or merge
MEMORY_TARGET="$MEMORY_DIR/MEMORY.md"
MEMORY_BACKUP="$MEMORY_DIR/MEMORY.md.pre-stratavarious.bak"
SV_MARKER="# StrataVarious Vault — Index"

if [ ! -f "$MEMORY_TARGET" ]; then
  # No existing MEMORY.md — clean install
  cp "$TEMPLATE_DIR/MEMORY.md" "$MEMORY_TARGET"
  echo "Created MEMORY.md"
elif grep -qF "$SV_MARKER" "$MEMORY_TARGET" 2>/dev/null; then
  # Already has StrataVarious header — update in place
  echo "MEMORY.md already contains StrataVarious index, skipping"
else
  # Existing MEMORY.md without StrataVarious content — merge
  cp "$MEMORY_TARGET" "$MEMORY_BACKUP"
  {
    echo ""
    echo "---"
    echo ""
    cat "$TEMPLATE_DIR/MEMORY.md"
  } >> "$MEMORY_TARGET"
  echo "MEMORY.md merged (backup: MEMORY.md.pre-stratavarious.bak)"
fi

# 3. Copy .gitignore
if [ ! -f "$MEMORY_DIR/.gitignore" ]; then
  cp "$TEMPLATE_DIR/.gitignore" "$MEMORY_DIR/.gitignore"
  echo "Created .gitignore"
fi

# 4. Initialize Git in memory/
if [ ! -d "$MEMORY_DIR/.git" ]; then
  git init "$MEMORY_DIR"
  echo "Initialized git repository"
else
  echo "Git repository already exists"
fi

# 5. Check write permissions
TEST_FILE="$MEMORY_DIR/.stratavarious_write_test"
if touch "$TEST_FILE" && rm "$TEST_FILE"; then
  echo "Write permissions confirmed"
else
  echo "Error: Cannot write to $MEMORY_DIR"
  exit 1
fi

echo "Setup complete. Run /stratavarious after your first session to consolidate."
