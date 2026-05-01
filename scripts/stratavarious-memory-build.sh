#!/bin/bash
# stratavarious-memory-build.sh — Rebuild MEMORY.md from vault contents
# Usage: ./stratavarious-memory-build.sh [project-name]
# If project-name given, only includes notes with matching projet: frontmatter.
# Notes without projet: are treated as _global (included in all projects).
# Compatible with Bash 3.2 (macOS default)

set -euo pipefail

StrataVarious_HOME="${StrataVarious_HOME:-$HOME/.claude/workspace/stratavarious}"
VAULT_DIR="$StrataVarious_HOME/memory/vault"
MEMORY_FILE="$StrataVarious_HOME/memory/MEMORY.md"
PROJECT_FILTER="${1:-}"
MAX_LINES=200

if [ ! -d "$VAULT_DIR" ]; then
  echo "Vault directory not found: $VAULT_DIR"
  exit 1
fi

CATEGORIES="decisions conventions errors patterns skills preferences environments"

# Extract frontmatter fields from a vault note
# Output: date|categorie|tags|projet|title
# Note: tags field is extracted but not currently used in memory build
extract_frontmatter() {
  local file="$1"
  awk '
  BEGIN { found_opening = 0; found_closing = 0; fm_lines = "" }
  {
    if (NR == 1 && $0 == "---") { found_opening = 1; next }
    if (found_opening && !found_closing && $0 == "---") { found_closing = 1; exit }
    if (found_opening && !found_closing) { fm_lines = fm_lines $0 "\n" }
  }
  END {
    date = ""; categorie = ""; tags = ""; projet = ""; title = ""
    n = split(fm_lines, lines, "\n")
    for (i = 1; i <= n; i++) {
      line = lines[i]
      if (match(line, /^date:[[:space:]]*/)) date = substr(line, RSTART + RLENGTH)
      else if (match(line, /^categorie:[[:space:]]*/)) categorie = substr(line, RSTART + RLENGTH)
      else if (match(line, /^tags:[[:space:]]*/)) tags = substr(line, RSTART + RLENGTH)
      else if (match(line, /^projet:[[:space:]]*/)) projet = substr(line, RSTART + RLENGTH)
    }
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", date)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", categorie)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", tags)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", projet)
  }
 print date "|" categorie "|" tags "|" projet
  ' "$file"

}

# Collect all vault entries (excluding journal/ and sessions/)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

find "$VAULT_DIR" -type f -name "*.md" -print0 2>/dev/null | while IFS= read -r -d '' file; do
  case "$file" in
    */journal/*) continue ;;
    */sessions/*) continue ;;
  esac

  fm=$(extract_frontmatter "$file")
  date=$(echo "$fm" | cut -d'|' -f1)
  categorie=$(echo "$fm" | cut -d'|' -f2)
  projet=$(echo "$fm" | cut -d'|' -f4)
  # Extract title separately (first # heading after frontmatter)
  title=$(awk '
    /^---$/ { if (started) { in_fm = !in_fm; next } else { in_fm = 1; started = 1; next } }
    in_fm { next }
    /^# / { sub(/^# /, ""); print; exit }
  ' "$file" 2>/dev/null)
  basename=$(basename "$file")

  # Skip if no date or categorie
  [ -z "$date" ] && continue
  [ -z "$categorie" ] && continue

  # Filter by project if requested
  if [ -n "$PROJECT_FILTER" ]; then
    if [ -n "$projet" ] && [ "$projet" != "$PROJECT_FILTER" ] && [ "$projet" != "_global" ]; then
      continue
    fi
  fi

  # Build index entry
  echo "$date|$categorie|$basename|$title"
done > "$TMPDIR/entries.txt"

# Build MEMORY.md
{
  if [ -n "$PROJECT_FILTER" ]; then
    echo "# StrataVarious Vault — Index"
    echo ""
    echo "> Map of Content. Auto-generated. Do not edit manually."
    echo "> Filtered by project: $PROJECT_FILTER"
  else
    echo "# StrataVarious Vault — Index"
    echo ""
    echo "> Map of Content. Auto-generated. Do not edit manually."
    echo "> Showing all projects."
  fi
  echo ""

  line_count=4

  for cat in $CATEGORIES; do
    echo "## ${cat^}"
    echo ""

    # Get entries for this category, sorted by date desc
    cat_entries=$(grep "|$cat|" "$TMPDIR/entries.txt" 2>/dev/null | sort -t'|' -k1 -r)

    if [ -z "$cat_entries" ]; then
      line_count=$((line_count + 2))
      continue
    fi

    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      basename=$(echo "$entry" | cut -d'|' -f3)
      title=$(echo "$entry" | cut -d'|' -f4)
      [ -z "$title" ] && title="$basename"

      echo "- \`$basename\` — $title"
      line_count=$((line_count + 1))
      [ "$line_count" -ge "$MAX_LINES" ] && break
    done <<< "$cat_entries"

    [ "$line_count" -ge "$MAX_LINES" ] && break
    echo ""
    line_count=$((line_count + 1))
  done

  if [ "$line_count" -ge "$MAX_LINES" ]; then
    echo ""
    echo "> Index truncated at ${MAX_LINES} lines. Run /stratavarious to consolidate."
  fi
} > "$MEMORY_FILE"

echo "MEMORY.md rebuilt (${line_count} lines, project filter: ${PROJECT_FILTER:-all})"
