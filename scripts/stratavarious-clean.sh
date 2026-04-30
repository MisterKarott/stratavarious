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
  TITLES+=("$( { grep -m1 '^# ' "$f" 2>/dev/null || true; } | sed 's/^# //' | tr '[:upper:]' '[:lower:]' | tr -d ' ')")
done

# Check for exact duplicates based on content hash (O(n) with dictionary)
DUPLICATES_FOUND=0
declare -A SEEN_HASH  # Associative array: hash -> filename
for i in "${!VAULT_FILES[@]}"; do
  h="${HASHES[$i]}"
  if [[ -n "${SEEN_HASH[$h]:-}" ]]; then
    echo "⚠️  Exact duplicate detected:"
    echo "   $(basename "${VAULT_FILES[$i]}")"
    echo "   $(basename "${SEEN_HASH[$h]}")"
    echo "   Action: Delete one of them"
    echo ""
    DUPLICATES_FOUND=1
  else
    SEEN_HASH["$h"]="${VAULT_FILES[$i]}"
  fi
done

# Check for similar titles (O(n) with dictionary)
echo "Checking for similar topics..."
declare -A SEEN_TITLE  # Associative array: title -> filename
for i in "${!VAULT_FILES[@]}"; do
  t="${TITLES[$i]}"
  if [[ -n "$t" ]]; then
    if [[ -n "${SEEN_TITLE[$t]:-}" ]]; then
      echo "⚠️  Similar title detected:"
      echo "   $(basename "${VAULT_FILES[$i]}") - $t"
      echo "   $(basename "${SEEN_TITLE[$t]}") - $t"
      echo "   Action: Review and merge if covering same topic"
      echo ""
      DUPLICATES_FOUND=1
    else
      SEEN_TITLE["$t"]="${VAULT_FILES[$i]}"
    fi
  fi
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
