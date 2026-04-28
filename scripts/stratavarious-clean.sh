#!/bin/bash

STRATAVARIOUS_HOME="${STRATAVARIOUS_HOME:-$HOME/.claude/workspace/stratavarious}"
MEMORY_DIR="$STRATAVARIOUS_HOME/memory"
VAULT_DIR="$MEMORY_DIR/vault"

echo "--- StrataVarious Vault Cleaning ---"
echo ""

# Collect all vault files (excluding journal for now)
VAULT_FILES=()
while IFS= read -r -d '' file; do
  # Skip journal files
  if [[ "$file" =~ /journal/ ]]; then
    continue
  fi
  VAULT_FILES+=("$file")
done < <(find "$VAULT_DIR" -type f -name "*.md" -print0)

if [ ${#VAULT_FILES[@]} -eq 0 ]; then
  echo "No vault files found."
  exit 0
fi

echo "Found ${#VAULT_FILES[@]} vault files to analyze:"
for file in "${VAULT_FILES[@]}"; do
  echo "  - $(basename "$file")"
done
echo ""

# Check for potential duplicates based on file size and content hash
DUPLICATES_FOUND=0
for i in "${!VAULT_FILES[@]}"; do
  FILE1="${VAULT_FILES[$i]}"
  SIZE1=$(stat -f%z "$FILE1" 2>/dev/null || stat -c%s "$FILE1" 2>/dev/null)
  HASH1=$(md5sum "$FILE1" 2>/dev/null | cut -d' ' -f1 || md5 "$FILE1" | cut -d' ' -f4)

  for j in $(seq $((i + 1)) $((${#VAULT_FILES[@]} - 1))); do
    FILE2="${VAULT_FILES[$j]}"
    SIZE2=$(stat -f%z "$FILE2" 2>/dev/null || stat -c%s "$FILE2" 2>/dev/null)

    # Check if files are identical (same hash)
    HASH2=$(md5sum "$FILE2" 2>/dev/null | cut -d' ' -f1 || md5 "$FILE2" | cut -d' ' -f4)

    if [ "$HASH1" = "$HASH2" ]; then
      echo "⚠️  Exact duplicate detected:"
      echo "   $(basename "$FILE1")"
      echo "   $(basename "$FILE2")"
      echo "   Action: Delete one of them"
      echo ""
      DUPLICATES_FOUND=1
    fi
  done
done

# Check for similar titles/categories
echo "Checking for similar topics..."
for i in "${!VAULT_FILES[@]}"; do
  FILE1="${VAULT_FILES[$i]}"
  TITLE1=$(grep -m1 '^# ' "$FILE1" 2>/dev/null | sed 's/^# //' | tr '[:upper:]' '[:lower:]' | tr -d ' ' || echo "")

  for j in $(seq $((i + 1)) $((${#VAULT_FILES[@]} - 1))); do
    FILE2="${VAULT_FILES[$j]}"
    TITLE2=$(grep -m1 '^# ' "$FILE2" 2>/dev/null | sed 's/^# //' | tr '[:upper:]' '[:lower:]' | tr -d ' ' || echo "")

    if [ -n "$TITLE1" ] && [ -n "$TITLE2" ] && [ "$TITLE1" = "$TITLE2" ]; then
      echo "⚠️  Similar title detected:"
      echo "   $(basename "$FILE1") - $TITLE1"
      echo "   $(basename "$FILE2") - $TITLE2"
      echo "   Action: Review and merge if covering same topic"
      echo ""
      DUPLICATES_FOUND=1
    fi
  done
done

if [ $DUPLICATES_FOUND -eq 0 ]; then
  echo "✅ No duplicates detected"
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
