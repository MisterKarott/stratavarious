#!/bin/bash
# Compatible with Bash 3.2 (macOS default)
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

# Collect all vault files (excluding journal and sessions) into temp files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

find "$VAULT_DIR" -type f -name "*.md" -print0 2>/dev/null | while IFS= read -r -d '' file; do
  case "$file" in
    */journal/*) continue ;;
    */sessions/*) continue ;;
  esac
  echo "$file"
done > "$TMPDIR/files.txt"

FILE_COUNT=$(wc -l < "$TMPDIR/files.txt" | tr -d ' ')

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "No vault files found."
  exit 0
fi

echo "Found $FILE_COUNT vault files to analyze"
echo ""

# Pre-compute hashes and titles
DUPLICATES_FOUND=0

# Check for exact duplicates using sorted hashes
while IFS= read -r file; do
  h=$(file_hash "$file")
  echo "$h  $file"
done < "$TMPDIR/files.txt" | sort > "$TMPDIR/hashed.txt"

awk '
{
  hash = $1
  # Rebuild filename (may contain spaces)
  fname = ""
  for (i = 2; i <= NF; i++) {
    if (fname != "") fname = fname " "
    fname = fname $i
  }
  if (hash == prev_hash) {
    print "DUP: " prev_file
    print "DUP: " fname
  }
  prev_hash = hash
  prev_file = fname
}
' "$TMPDIR/hashed.txt" | while IFS= read -r line; do
  case "$line" in
    DUP:\ *)
      f=$(echo "$line" | sed 's/^DUP: //')
      echo "  - $(basename "$f")"
      DUPLICATES_FOUND=1
      ;;
  esac
done

# Check for similar titles using sorted normalized titles
while IFS= read -r file; do
  title=$(grep -m1 '^# ' "$file" 2>/dev/null | sed 's/^# //' | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  if [ -n "$title" ]; then
    echo "$title  $file"
  fi
done < "$TMPDIR/files.txt" | sort > "$TMPDIR/titles.txt"

awk '
{
  title = ""
  fname = ""
  # First field(s) = title (separated by double space from filename)
  # But titles may contain spaces — find the "  " separator
  sep = index($0, "  ")
  if (sep > 0) {
    title = substr($0, 1, sep - 1)
    fname = substr($0, sep + 2)
  }
  if (title == prev_title && title != "") {
    print "SIMILAR: " fname
    print "SIMILAR_PREV: " prev_file
  }
  prev_title = title
  prev_file = fname
}
' "$TMPDIR/titles.txt" | while IFS= read -r line; do
  case "$line" in
    SIMILAR:\ *)
      f=$(echo "$line" | sed 's/^SIMILAR: //')
      echo "  - $(basename "$f")"
      ;;
    SIMILAR_PREV:\ *)
      f=$(echo "$line" | sed 's/^SIMILAR_PREV: //')
      echo "  - $(basename "$f")"
      DUPLICATES_FOUND=1
      ;;
  esac
done

if [ "$DUPLICATES_FOUND" -eq 0 ]; then
  echo "No duplicates detected"
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
