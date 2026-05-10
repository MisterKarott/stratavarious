#!/bin/bash
# stratavarious-search.sh — Search vault notes by content and frontmatter
# Usage: ./stratavarious-search.sh [options] <query>
# Compatible with Bash 3.2 (macOS default)
# shellcheck shell=bash

set -euo pipefail

StrataVarious_HOME="${StrataVarious_HOME:-$HOME/.claude/workspace/stratavarious}"

# --- Defaults ---
FLAG_JSON=0
FILTER_CATEGORY=""
FILTER_PROJECT=""
FILTER_TAG=""
FILTER_SINCE_DAYS=""
FLAG_GLOBAL=0
LIMIT=10
QUERY=""

# --- Parse flags ---
while [ $# -gt 0 ]; do
    case "$1" in
        --json)         FLAG_JSON=1; shift ;;
        --global)       FLAG_GLOBAL=1; shift ;;
        --limit=*)      LIMIT="${1#--limit=}"; shift ;;
        --category=*)   FILTER_CATEGORY="${1#--category=}"; shift ;;
        --project=*)    FILTER_PROJECT="${1#--project=}"; shift ;;
        --tag=*)        FILTER_TAG="${1#--tag=}"; shift ;;
        --since=*)
            since_val="${1#--since=}"
            # Accept Nd format (e.g. 7d, 30d)
            case "$since_val" in
                *d) FILTER_SINCE_DAYS="${since_val%d}" ;;
                *)  echo "ERROR: --since must be in Nd format (e.g. --since=7d)" >&2; exit 2 ;;
            esac
            shift ;;
        --) shift; QUERY="$*"; break ;;
        --*) echo "Unknown flag: $1" >&2; exit 2 ;;
        *)  QUERY="$1"; shift ;;
    esac
done

if [ -z "$QUERY" ]; then
    echo "Usage: stratavarious-search.sh [--category=CATEGORY] [--project=NAME] [--tag=TAG] [--since=Nd] [--global] [--json] [--limit=N] <query>" >&2
    exit 2
fi

# --- Locate vault ---
VAULT_DIR="$StrataVarious_HOME/memory/vault"
if [ ! -d "$VAULT_DIR" ]; then
    if [ "$FLAG_JSON" -eq 1 ]; then
        printf '{"error":"vault not found","vault":"%s"}\n' "$VAULT_DIR"
    else
        echo "ERROR: vault not found at $VAULT_DIR" >&2
    fi
    exit 2
fi

# --- Detect search tool ---
USE_RG=0
if command -v rg > /dev/null 2>&1; then
    USE_RG=1
fi

# --- Compute cutoff date for --since (as YYYY-MM-DD) ---
SINCE_DATE=""
if [ -n "$FILTER_SINCE_DAYS" ]; then
    # macOS date: -v, Linux date: -d
    if date -v "-${FILTER_SINCE_DAYS}d" +%Y-%m-%d > /dev/null 2>&1; then
        SINCE_DATE=$(date -v "-${FILTER_SINCE_DAYS}d" +%Y-%m-%d)
    else
        SINCE_DATE=$(date -d "-${FILTER_SINCE_DAYS} days" +%Y-%m-%d 2>/dev/null || echo "")
    fi
fi


# --- Collect matching files ---
# Build list of candidate dirs based on --category and --global
SEARCH_DIRS=""
if [ -n "$FILTER_CATEGORY" ]; then
    cdir="$VAULT_DIR/$FILTER_CATEGORY"
    if [ ! -d "$cdir" ]; then
        if [ "$FLAG_JSON" -eq 1 ]; then
            printf '{"error":"category not found","category":"%s"}\n' "$FILTER_CATEGORY"
        else
            echo "ERROR: category '$FILTER_CATEGORY' not found in vault" >&2
        fi
        exit 2
    fi
    SEARCH_DIRS="$cdir"
else
    SEARCH_DIRS="$VAULT_DIR"
fi

# --- Find matching files with ripgrep or grep -r ---
MATCH_FILE=$(mktemp)
trap 'rm -f "$MATCH_FILE"' EXIT

if [ "$USE_RG" -eq 1 ]; then
    rg --files-with-matches --multiline -i "$QUERY" "$SEARCH_DIRS" > "$MATCH_FILE" 2>/dev/null || true
else
    # grep -r fallback; warn user
    echo "WARNING: ripgrep not found, falling back to grep -r (slower)" >&2
    grep -r -l -i "$QUERY" "$SEARCH_DIRS" > "$MATCH_FILE" 2>/dev/null || true
fi

# --- Ranking and filtering ---
# For each matching file:
#   1. Parse frontmatter (date, categorie, projet, tags)
#   2. Apply filters (project, tag, since)
#   3. Count matches in file
#   4. Compute recency_weight = exp(-age_days / 30) via awk
#   5. score = match_count * recency_weight
#   6. Collect snippet (2 lines around first match)
# Output: sorted list of top N

RESULTS_FILE=$(mktemp)
trap 'rm -f "$MATCH_FILE" "$RESULTS_FILE"' EXIT

while IFS= read -r fpath; do
    # Only .md files
    case "$fpath" in
        *.md) ;;
        *) continue ;;
    esac

    # Parse frontmatter fields
    fm_date=$(awk '/^---/{f++} f==1{if(/^date:/){gsub(/^date:[[:space:]]*/,""); print; exit}}' "$fpath" 2>/dev/null || echo "")
    fm_projet=$(awk '/^---/{f++} f==1{if(/^projet:/){gsub(/^projet:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}}' "$fpath" 2>/dev/null || echo "")
    fm_tags=$(awk '/^---/{f++} f==1{if(/^tags:/){gsub(/^tags:[[:space:]]*/,""); print; exit}}' "$fpath" 2>/dev/null || echo "")
    fm_title=$(grep -m1 "^# " "$fpath" 2>/dev/null | sed 's/^# //' || echo "")
    if [ -z "$fm_title" ]; then
        fm_title=$(basename "$fpath" .md)
    fi

    # Apply --project filter
    if [ -n "$FILTER_PROJECT" ] && [ "$FLAG_GLOBAL" -eq 0 ]; then
        if [ "$fm_projet" != "$FILTER_PROJECT" ]; then
            continue
        fi
    fi

    # Apply --global filter: skip project-specific notes (projet field not empty)
    if [ "$FLAG_GLOBAL" -eq 1 ] && [ -n "$fm_projet" ]; then
        continue
    fi

    # Apply --tag filter
    if [ -n "$FILTER_TAG" ]; then
        # tags field may be "#foo #bar" or "#foo, #bar"
        # Normalize and check presence
        tag_norm=$(echo "$fm_tags" | tr ',' ' ' | tr -s ' ')
        tag_check="#$FILTER_TAG"
        found_tag=0
        for t in $tag_norm; do
            if [ "$t" = "$tag_check" ]; then
                found_tag=1
                break
            fi
        done
        if [ "$found_tag" -eq 0 ]; then
            continue
        fi
    fi

    # Apply --since filter
    if [ -n "$SINCE_DATE" ] && [ -n "$fm_date" ]; then
        # Compare dates lexicographically (YYYY-MM-DD format)
        if [ "$fm_date" \< "$SINCE_DATE" ]; then
            continue
        fi
    fi

    # Compute age_days
    age_days=0
    if [ -n "$fm_date" ]; then
        # Convert YYYY-MM-DD to seconds since epoch
        # macOS: date -j -f, Linux: date -d
        if date -j -f "%Y-%m-%d" "$fm_date" +%s > /dev/null 2>&1; then
            note_epoch=$(date -j -f "%Y-%m-%d" "$fm_date" +%s 2>/dev/null || echo "")
        else
            note_epoch=$(date -d "$fm_date" +%s 2>/dev/null || echo "")
        fi
        today_epoch=$(date +%s)
        if [ -n "$note_epoch" ] && [ -n "$today_epoch" ]; then
            age_days=$(( (today_epoch - note_epoch) / 86400 ))
            if [ "$age_days" -lt 0 ]; then age_days=0; fi
        fi
    fi

    # Count matches in file
    match_count=$(grep -ci "$QUERY" "$fpath" 2>/dev/null || echo "1")
    if [ "$match_count" -eq 0 ]; then match_count=1; fi

    # Compute score = match_count * exp(-age_days/30) via awk
    score=$(awk -v mc="$match_count" -v age="$age_days" 'BEGIN {
        rw = exp(-age / 30.0)
        printf "%.6f", mc * rw
    }')

    # Get snippet: 2 lines around first match (grep -n, then pick context)
    snippet=$(grep -n -i "$QUERY" "$fpath" 2>/dev/null | head -1 || echo "")
    if [ -n "$snippet" ]; then
        lineno=$(echo "$snippet" | cut -d: -f1)
        snippet=$(awk -v l="$lineno" 'NR>=l && NR<=l+1 {print}' "$fpath" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
    fi

    # Derive category from path
    category=$(echo "$fpath" | sed "s|$VAULT_DIR/||" | cut -d/ -f1)

    # Append to results: score TAB title TAB path TAB snippet TAB match_count TAB category
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$score" "$fm_title" "$fpath" "$snippet" "$match_count" "$category" >> "$RESULTS_FILE"

done < "$MATCH_FILE"

# --- Sort by score descending, take top N ---
TOP=$(sort -t$'\t' -k1,1rn "$RESULTS_FILE" | head -"$LIMIT")

# --- Output ---
if [ "$FLAG_JSON" -eq 1 ]; then
    # JSON output
    first=1
    printf '{"query":"%s","results":[' "$QUERY"
    if [ -n "$TOP" ]; then
        while IFS=$'\t' read -r score title fpath snippet match_count category; do
            [ -z "$score" ] && continue
            # shellcheck disable=SC2001 # dynamic VAULT_DIR prefix requires sed; ${//} doesn't support it
            rel_path=$(echo "$fpath" | sed "s|$VAULT_DIR/||")
            if [ "$first" -eq 0 ]; then printf ','; fi
            first=0
            # Escape double-quotes in snippet and title
            title_esc="${title//\"/\\\"}"
            snippet_esc="${snippet//\"/\\\"}"
            printf '{"score":%.4f,"title":"%s","path":"%s","category":"%s","matches":%s,"snippet":"%s"}' \
                "$score" "$title_esc" "$rel_path" "$category" "$match_count" "$snippet_esc"
        done <<EOF
$TOP
EOF
    fi
    printf ']}\n'
else
    # Markdown output
    if [ -z "$TOP" ]; then
        # shellcheck disable=SC2016 # backtick is markdown literal
        printf '**No results** for query: `%s`\n' "$QUERY"
        exit 0
    fi

    # shellcheck disable=SC2016 # backtick is markdown literal
    printf '## Search results for `%s`\n\n' "$QUERY"
    rank=0
    while IFS=$'\t' read -r score title fpath snippet match_count category; do
        [ -z "$score" ] && continue
        rank=$((rank + 1))
        # shellcheck disable=SC2001 # dynamic VAULT_DIR prefix requires sed
        rel_path=$(echo "$fpath" | sed "s|$VAULT_DIR/||")
        printf '### %d. %s\n' "$rank" "$title"
        # shellcheck disable=SC2016 # backtick is markdown literal
        printf '- **Path:** `%s`\n' "$rel_path"
        printf '- **Category:** %s · **Matches:** %s · **Score:** %.4f\n' "$category" "$match_count" "$score"
        if [ -n "$snippet" ]; then
            printf '%s\n' "- **Snippet:** $snippet"
        fi
        printf '\n'
    done <<EOF
$TOP
EOF
fi
