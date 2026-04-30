#!/bin/bash
# validate.sh — Validate vault note frontmatter against the expected schema
# Usage: ./validate.sh [vault-dir]
# Exit 1 if any note is invalid

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

  # Check frontmatter exists
  if ! head -1 "$file" | grep -q '^---'; then
    echo "FAIL $basename — missing frontmatter opening ---"
    ERRORS=$((ERRORS + 1))
    return
  fi

  # Detect closing --- using awk for strictness
  local fm_end
  fm_end=$(awk '/^---$/{c++; if(c==2){print NR; exit}}' "$file")
  if [ -z "$fm_end" ]; then
    echo "FAIL $basename — unclosed frontmatter"
    ERRORS=$((ERRORS + 1))
    return
  fi
  # Guard: fm_end must be at least 2 (opening line + content + closing line)
  if [ "$fm_end" -lt 2 ]; then
    echo "FAIL $basename — invalid frontmatter (too short)"
    ERRORS=$((ERRORS + 1))
    return
  fi

  local fm
  fm=$(head -$((fm_end - 1)) "$file" | tail -n +2)

  # Required fields — use sed instead of grep -oP (not portable on macOS)
  local date categorie tags
  date=$(echo "$fm" | sed -n 's/^date:[[:space:]]*\(.*\)$/\1/p')
  # 'categorie' est le champ canonique ; 'category' accepté pour compat
  categorie=$(echo "$fm" | sed -n 's/^categorie:[[:space:]]*\(.*\)$/\1/p')
  if [ -z "$categorie" ]; then
    categorie=$(echo "$fm" | sed -n 's/^category:[[:space:]]*\(.*\)$/\1/p')
  fi
  tags=$(echo "$fm" | sed -n 's/^tags:[[:space:]]*\(.*\)$/\1/p')

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
while IFS= read -r -d '' file; do
  [[ "$file" =~ /journal/ ]] && continue
  [[ "$file" =~ /sessions/ ]] && continue
  validate_file "$file"
done < <(find "$VAULT_DIR" -type f -name "*.md" -print0 2>/dev/null)

if [ $ERRORS -eq 0 ]; then
  echo "All vault notes valid."
  exit 0
else
  echo "$ERRORS validation error(s) found."
  exit 1
fi
