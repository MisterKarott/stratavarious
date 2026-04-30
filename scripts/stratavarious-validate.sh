#!/bin/bash
# validate.sh — Validate vault note frontmatter against the expected schema
# Usage: ./validate.sh [vault-dir]
# Exit 1 if any note is invalid
# Compatible with Bash 3.2 (macOS default)

set -euo pipefail

STRATAVARIOUS_HOME="${STRATAVARIOUS_HOME:-$HOME/.claude/workspace/stratavarious}"
VAULT_DIR="${1:-$STRATAVARIOUS_HOME/memory/vault}"

if [ ! -d "$VAULT_DIR" ]; then
  echo "Vault directory not found: $VAULT_DIR"
  exit 1
fi

VALID_CATEGORIES="decision convention error pattern skill preference environment"
ERRORS=0

validate_file() {
  local file="$1"
  local basename
  basename=$(basename "$file")

  local result
  result=$(awk '
  BEGIN { found_opening = 0; found_closing = 0; line_count = 0; fm_lines = "" }
  {
    line_count++
    if (NR == 1 && $0 == "---") {
      found_opening = 1
      next
    }
    if (found_opening && !found_closing && $0 == "---") {
      found_closing = 1
      exit
    }
    if (found_opening && !found_closing) {
      fm_lines = fm_lines $0 "\n"
    }
  }
  END {
    if (!found_opening) {
      print "MISSING_OPENING"
      exit
    }
    if (!found_closing) {
      print "UNCLOSED"
      exit
    }
    if (line_count < 2) {
      print "TOO_SHORT"
      exit
    }
    date = ""
    categorie = ""
    tags = ""
    n = split(fm_lines, lines, "\n")
    for (i = 1; i <= n; i++) {
      line = lines[i]
      if (match(line, /^date:[[:space:]]*/)) {
        date = substr(line, RSTART + RLENGTH)
      } else if (match(line, /^categorie:[[:space:]]*/)) {
        categorie = substr(line, RSTART + RLENGTH)
      } else if (match(line, /^category:[[:space:]]*/)) {
        if (categorie == "") categorie = substr(line, RSTART + RLENGTH)
      } else if (match(line, /^tags:[[:space:]]*/)) {
        tags = substr(line, RSTART + RLENGTH)
      }
    }
    print date "|" categorie "|" tags
  }
  ' "$file")

  case "$result" in
    MISSING_OPENING)
      echo "FAIL $basename — missing frontmatter opening ---"
      ERRORS=$((ERRORS + 1))
      return
      ;;
    UNCLOSED)
      echo "FAIL $basename — unclosed frontmatter"
      ERRORS=$((ERRORS + 1))
      return
      ;;
    TOO_SHORT)
      echo "FAIL $basename — invalid frontmatter (too short)"
      ERRORS=$((ERRORS + 1))
      return
      ;;
  esac

  local date categorie tags
  date=$(echo "$result" | cut -d'|' -f1)
  categorie=$(echo "$result" | cut -d'|' -f2)
  tags=$(echo "$result" | cut -d'|' -f3)

  if [ -z "$date" ]; then
    echo "FAIL $basename — missing date"
    ERRORS=$((ERRORS + 1))
  elif ! echo "$date" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "FAIL $basename — invalid date format: $date (expected YYYY-MM-DD)"
    ERRORS=$((ERRORS + 1))
  fi

  if [ -z "$categorie" ]; then
    echo "FAIL $basename — missing category"
    ERRORS=$((ERRORS + 1))
  elif ! echo " $VALID_CATEGORIES " | grep -q " $categorie "; then
    echo "FAIL $basename — invalid category: $categorie"
    ERRORS=$((ERRORS + 1))
  fi

  if [ -z "$tags" ]; then
    echo "FAIL $basename — missing tags"
    ERRORS=$((ERRORS + 1))
  fi
}

# Process all .md files (excluding journal/ and sessions/)
# Use a temp file to count errors across the pipe subshell boundary (Bash 3.2 compatible)
ERROR_COUNT_FILE=$(mktemp)
echo "0" > "$ERROR_COUNT_FILE"

find "$VAULT_DIR" -type f -name "*.md" -print0 2>/dev/null | while IFS= read -r -d '' file; do
  case "$file" in
    */journal/*) continue ;;
    */sessions/*) continue ;;
  esac
  ERRORS=0
  validate_file "$file"
  if [ $ERRORS -gt 0 ]; then
    prev=$(cat "$ERROR_COUNT_FILE")
    echo $((prev + ERRORS)) > "$ERROR_COUNT_FILE"
  fi
done

TOTAL_ERRORS=$(cat "$ERROR_COUNT_FILE")
rm -f "$ERROR_COUNT_FILE"

if [ "$TOTAL_ERRORS" -eq 0 ]; then
  echo "All vault notes valid."
  exit 0
else
  echo "$TOTAL_ERRORS validation error(s) found."
  exit 1
fi
