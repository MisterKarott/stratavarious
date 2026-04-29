#!/bin/bash
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

# Collect all vault files (excluding journal)
VAULT_FILES=()
while IFS= read -r -d '' file; do
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

# Pre-compute hashes and titles to avoid O(n²) re-computation
declare -a HASHES TITLES
for f in "${VAULT_FILES[@]}"; do
  HASHES+=("$(file_hash "$f")")
  TITLES+=("$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# //' | tr '[:upper:]' '[:lower:]' | tr -d ' ' || echo "")")
done

# Check for exact duplicates based on content hash
DUPLICATES_FOUND=0
for i in "${!VAULT_FILES[@]}"; do
  HASH1="${HASHES[$i]}"
  for j in $(seq $((i + 1)) $((${#VAULT_FILES[@]} - 1))); do
    HASH2="${HASHES[$j]}"
    if [ "$HASH1" = "$HASH2" ]; then
      echo "⚠️  Exact duplicate detected:"
      echo "   $(basename "${VAULT_FILES[$i]}")"
      echo "   $(basename "${VAULT_FILES[$j]}")"
      echo "   Action: Delete one of them"
      echo ""
      DUPLICATES_FOUND=1
    fi
  done
done

# Check for similar titles
echo "Checking for similar topics..."
for i in "${!VAULT_FILES[@]}"; do
  TITLE1="${TITLES[$i]}"
  for j in $(seq $((i + 1)) $((${#VAULT_FILES[@]} - 1))); do
    TITLE2="${TITLES[$j]}"
    if [ -n "$TITLE1" ] && [ -n "$TITLE2" ] && [ "$TITLE1" = "$TITLE2" ]; then
      echo "⚠️  Similar title detected:"
      echo "   $(basename "${VAULT_FILES[$i]}") - $TITLE1"
      echo "   $(basename "${VAULT_FILES[$j]}") - $TITLE2"
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
