#!/bin/bash
# stratavarious-prune.sh — Vault hygiene: decay, duplicates, trivial notes
# Usage: ./stratavarious-prune.sh [--apply] [--yes] [--json] [--age-days N] [vault-dir]
# Default: dry-run (no vault modifications)
# Compatible with Bash 3.2 (macOS default)
# shellcheck shell=bash

set -euo pipefail

StrataVarious_HOME="${StrataVarious_HOME:-$HOME/.claude/workspace/stratavarious}"

# --- Flags ---
FLAG_APPLY=0
FLAG_YES=0
FLAG_JSON=0
AGE_DAYS="${StrataVarious_PRUNE_AGE_DAYS:-60}"
TRIVIAL_LINES=5
VAULT_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --apply)     FLAG_APPLY=1; shift ;;
        --yes)       FLAG_YES=1; shift ;;
        --json)      FLAG_JSON=1; shift ;;
        --age-days)  AGE_DAYS="$2"; shift 2 ;;
        --*)         echo "Unknown flag: $1" >&2; exit 2 ;;
        *)           VAULT_DIR="$1"; shift ;;
    esac
done

# --- Vault dir resolution (same convention as doctor/search) ---
if [ -z "$VAULT_DIR" ]; then
    VAULT_DIR="$StrataVarious_HOME/memory"
fi

if [ -f "$VAULT_DIR/MEMORY.md" ]; then
    if [ -d "$VAULT_DIR/vault" ]; then
        VAULT_NOTES_DIR="$VAULT_DIR/vault"
    else
        VAULT_NOTES_DIR="$VAULT_DIR"
    fi
else
    echo "ERROR: MEMORY.md not found in $VAULT_DIR" >&2
    exit 2
fi

TODAY=$(date +%Y-%m-%d)
TODAY_EPOCH=$(date +%s)

TMPDIR_PRUNE=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$TMPDIR_PRUNE'" EXIT

# --- Helper: extract frontmatter field ---
extract_fm_field() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
    BEGIN { in_fm=0 }
    NR==1 && $0=="---" { in_fm=1; next }
    in_fm && $0=="---" { exit }
    in_fm {
        pat = "^" field ":[[:space:]]*"
        if (match($0, pat)) {
            val = substr($0, RSTART + RLENGTH)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            gsub(/^"|"$/, "", val)
            print val
            exit
        }
    }
    ' "$file" 2>/dev/null
}

# --- Helper: count content lines after frontmatter ---
count_content_lines() {
    local file="$1"
    awk '
    BEGIN { in_fm=0; done_fm=0; count=0 }
    NR==1 && $0=="---" { in_fm=1; next }
    in_fm && $0=="---" { done_fm=1; next }
    done_fm && /[^[:space:]]/ { count++ }
    END { print count }
    ' "$file" 2>/dev/null
}

# --- Helper: extract H1 title ---
extract_title() {
    local file="$1"
    local title
    title=$(awk '
    BEGIN { in_fm=0; done_fm=0 }
    NR==1 && $0=="---" { in_fm=1; next }
    in_fm && $0=="---" { done_fm=1; next }
    done_fm && /^# / { sub(/^# /, ""); print; exit }
    ' "$file" 2>/dev/null)
    if [ -z "$title" ]; then
        basename "$file" .md
    else
        echo "$title"
    fi
}

# --- Helper: date string to epoch ---
date_to_epoch() {
    local d="$1"
    date -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null || \
    date -d "$d" +%s 2>/dev/null || \
    echo "0"
}

# --- Scan all vault notes ---
find "$VAULT_NOTES_DIR" -type f -name "*.md" 2>/dev/null | while IFS= read -r f; do
    case "$f" in
        */journal/*)   continue ;;
        */sessions/*)  continue ;;
        */_archive/*)  continue ;;
        */MEMORY.md)   continue ;;
    esac
    echo "$f"
done > "$TMPDIR_PRUNE/all_notes.txt" || true

NOTE_COUNT=$(wc -l < "$TMPDIR_PRUNE/all_notes.txt" | tr -d ' ')

if [ "$NOTE_COUNT" -eq 0 ]; then
    if [ "$FLAG_JSON" -eq 1 ]; then
        echo '{"decay":[],"trivial":[],"duplicates":[],"summary":{"decay":0,"trivial":0,"duplicates":0}}'
    else
        echo "# Prune Report — $TODAY"
        echo ""
        echo "Vault is empty — no notes to prune."
    fi
    exit 0
fi

# --- Build cross-reference corpus (all note content concatenated for grep) ---
while IFS= read -r f; do
    [ -z "$f" ] && continue
    cat "$f"
    echo ""
done < "$TMPDIR_PRUNE/all_notes.txt" > "$TMPDIR_PRUNE/corpus.txt" || true

# --- Check 1: Decay — errors/ category, old, unreferenced ---
DECAY_FILE="$TMPDIR_PRUNE/decay.tsv"
touch "$DECAY_FILE"

while IFS= read -r f; do
    [ -z "$f" ] && continue
    bn=$(basename "$f")
    stem="${bn%.md}"

    # Check category is error
    cat=$(extract_fm_field "$f" "categorie")
    [ "$cat" != "error" ] && continue

    # Check age
    note_date=$(extract_fm_field "$f" "date")
    [ -z "$note_date" ] && continue

    note_epoch=$(date_to_epoch "$note_date")
    [ "$note_epoch" -eq 0 ] && continue

    age_days=$(( (TODAY_EPOCH - note_epoch) / 86400 ))
    [ "$age_days" -lt "$AGE_DAYS" ] && continue

    # Check if referenced in any other note (by stem or basename)
    # Build corpus without this file
    grep -v "^$" "$TMPDIR_PRUNE/corpus.txt" > "$TMPDIR_PRUNE/corpus_check.txt" 2>/dev/null || true
    # Remove this file's own content from check (approximate: grep by content length approach is hard)
    # Simpler: check if stem appears in OTHER notes
    referenced=0
    while IFS= read -r other; do
        [ -z "$other" ] && continue
        [ "$other" = "$f" ] && continue
        if grep -q "$stem" "$other" 2>/dev/null; then
            referenced=1
            break
        fi
    done < "$TMPDIR_PRUNE/all_notes.txt"

    if [ "$referenced" -eq 0 ]; then
        year=$(echo "$note_date" | cut -d- -f1)
        echo "${f}	${note_date}	${age_days}	${year}" >> "$DECAY_FILE"
    fi
done < "$TMPDIR_PRUNE/all_notes.txt"

DECAY_COUNT=$(wc -l < "$DECAY_FILE" | tr -d ' ')

# --- Check 2: Trivial — fewer than TRIVIAL_LINES content lines ---
TRIVIAL_FILE="$TMPDIR_PRUNE/trivial.tsv"
touch "$TRIVIAL_FILE"

while IFS= read -r f; do
    [ -z "$f" ] && continue
    bn=$(basename "$f")
    cat=$(extract_fm_field "$f" "categorie")
    lines=$(count_content_lines "$f")
    if [ "$lines" -lt "$TRIVIAL_LINES" ]; then
        echo "${f}	${cat:-unknown}	${lines}" >> "$TRIVIAL_FILE"
    fi
done < "$TMPDIR_PRUNE/all_notes.txt"

TRIVIAL_COUNT=$(wc -l < "$TRIVIAL_FILE" | tr -d ' ')

# --- Check 3: Semantic duplicates — Levenshtein < 3 or Jaccard > 0.7, same category ---
DUP_FILE="$TMPDIR_PRUNE/duplicates.tsv"
touch "$DUP_FILE"

# Build title index: path|category|normalized_title
TITLE_INDEX="$TMPDIR_PRUNE/title_index.txt"
touch "$TITLE_INDEX"

while IFS= read -r f; do
    [ -z "$f" ] && continue
    cat=$(extract_fm_field "$f" "categorie")
    [ -z "$cat" ] && cat="unknown"
    title=$(extract_title "$f")
    # Normalize: lowercase, strip punctuation, collapse spaces
    norm=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' ' ' | tr -s ' ' | sed 's/^ //;s/ $//')
    echo "${f}|${cat}|${norm}" >> "$TITLE_INDEX"
done < "$TMPDIR_PRUNE/all_notes.txt"

# For each category, compare all pairs using awk Levenshtein + Jaccard
# Group by category
sort -t'|' -k2,2 "$TITLE_INDEX" > "$TMPDIR_PRUNE/title_sorted.txt" 2>/dev/null || true

awk -F'|' '
function levenshtein(s1, s2,    i, j, d, cost, m, n, a, b, c) {
    m = length(s1)
    n = length(s2)
    if (m == 0) return n
    if (n == 0) return m
    for (i = 0; i <= m; i++) d[i,0] = i
    for (j = 0; j <= n; j++) d[0,j] = j
    for (i = 1; i <= m; i++) {
        for (j = 1; j <= n; j++) {
            cost = (substr(s1,i,1) != substr(s2,j,1)) ? 1 : 0
            a = d[i-1,j] + 1
            b = d[i,j-1] + 1
            c = d[i-1,j-1] + cost
            d[i,j] = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c)
        }
    }
    return d[m,n]
}

function jaccard(s1, s2,    n1, n2, count, i, tok) {
    # Split into tokens
    n1 = split(s1, a1, " ")
    n2 = split(s2, a2, " ")
    delete seen
    delete inter
    for (i = 1; i <= n1; i++) seen[a1[i]] = 1
    count = 0
    for (i = 1; i <= n2; i++) {
        if (seen[a2[i]]) count++
    }
    union = n1 + n2 - count
    if (union == 0) return 0
    return count / union
}

{
    path = $1; cat = $2; title = $3
    # Store entries per category
    if (cat != prev_cat) {
        # Process previous category group
        for (i = 1; i < idx; i++) {
            for (j = i+1; j < idx; j++) {
                lev = levenshtein(titles[i], titles[j])
                jac = jaccard(titles[i], titles[j])
                if (lev < 3 || jac > 0.7) {
                    print paths[i] "\t" paths[j] "\t" prev_cat "\t" lev "\t" int(jac * 100)
                }
            }
        }
        delete paths; delete titles; idx = 1
        prev_cat = cat
    }
    paths[idx] = path
    titles[idx] = title
    idx++
}
END {
    for (i = 1; i < idx; i++) {
        for (j = i+1; j < idx; j++) {
            lev = levenshtein(titles[i], titles[j])
            jac = jaccard(titles[i], titles[j])
            if (lev < 3 || jac > 0.7) {
                print paths[i] "\t" paths[j] "\t" prev_cat "\t" lev "\t" int(jac * 100)
            }
        }
    }
}
' "$TMPDIR_PRUNE/title_sorted.txt" 2>/dev/null >> "$DUP_FILE" || true

DUP_COUNT=$(wc -l < "$DUP_FILE" | tr -d ' ')

TOTAL=$(( DECAY_COUNT + TRIVIAL_COUNT + DUP_COUNT ))

# --- Output ---
MODE_LABEL="DRY RUN"
[ "$FLAG_APPLY" -eq 1 ] && MODE_LABEL="APPLY"

if [ "$FLAG_JSON" -eq 1 ]; then
    # JSON output
    printf '{"mode":"%s","date":"%s","age_threshold_days":%s,"decay":[' "$MODE_LABEL" "$TODAY" "$AGE_DAYS"
    first=1
    while IFS='	' read -r path note_date age_days year; do
        [ -z "$path" ] && continue
        bn=$(basename "$path")
        [ "$first" -eq 1 ] && first=0 || printf ','
        printf '{"file":"%s","date":"%s","age_days":%s,"action":"archive","archive_dir":"_archive/%s"}' \
            "$bn" "$note_date" "$age_days" "$year"
    done < "$DECAY_FILE"
    printf '],"trivial":['
    first=1
    while IFS='	' read -r path cat lines; do
        [ -z "$path" ] && continue
        bn=$(basename "$path")
        [ "$first" -eq 1 ] && first=0 || printf ','
        printf '{"file":"%s","category":"%s","content_lines":%s,"action":"delete"}' \
            "$bn" "$cat" "$lines"
    done < "$TRIVIAL_FILE"
    printf '],"duplicates":['
    first=1
    while IFS='	' read -r path1 path2 cat lev jac; do
        [ -z "$path1" ] && continue
        bn1=$(basename "$path1"); bn2=$(basename "$path2")
        [ "$first" -eq 1 ] && first=0 || printf ','
        printf '{"file_a":"%s","file_b":"%s","category":"%s","levenshtein":%s,"jaccard_pct":%s,"action":"manual_merge"}' \
            "$bn1" "$bn2" "$cat" "$lev" "$jac"
    done < "$DUP_FILE"
    printf '],"summary":{"decay":%s,"trivial":%s,"duplicates":%s,"total":%s}}' \
        "$DECAY_COUNT" "$TRIVIAL_COUNT" "$DUP_COUNT" "$TOTAL"
    printf '\n'
    exit 0
fi

# Markdown output
echo "# Prune Report — $TODAY ($MODE_LABEL)"
echo ""
echo "> Age threshold: **${AGE_DAYS} days** (override via \`StrataVarious_PRUNE_AGE_DAYS\`)"
echo ""

# Section 1: Decay
echo "## Decay candidates — archive"
echo ""
if [ "$DECAY_COUNT" -eq 0 ]; then
    echo "_No decay candidates._"
else
    echo "> Error notes older than ${AGE_DAYS} days, not referenced by any other vault note."
    echo ""
    echo "| Note | Date | Age | Action |"
    echo "|------|------|-----|--------|"
    while IFS='	' read -r path note_date age_days year; do
        [ -z "$path" ] && continue
        bn=$(basename "$path")
        printf "| \`%s\` | %s | %sd | archive → \`_archive/%s/\` |\n" \
            "$bn" "$note_date" "$age_days" "$year"
    done < "$DECAY_FILE"
fi
echo ""

# Section 2: Trivial
echo "## Trivial/empty candidates — delete"
echo ""
if [ "$TRIVIAL_COUNT" -eq 0 ]; then
    echo "_No trivial candidates._"
else
    echo "> Notes with fewer than ${TRIVIAL_LINES} content lines (excluding frontmatter)."
    echo ""
    echo "| Note | Category | Content lines | Action |"
    echo "|------|----------|---------------|--------|"
    while IFS='	' read -r path cat lines; do
        [ -z "$path" ] && continue
        bn=$(basename "$path")
        printf "| \`%s\` | %s | %s | delete |\n" "$bn" "$cat" "$lines"
    done < "$TRIVIAL_FILE"
fi
echo ""

# Section 3: Duplicates
echo "## Semantic duplicate candidates — merge"
echo ""
if [ "$DUP_COUNT" -eq 0 ]; then
    echo "_No duplicate candidates._"
else
    echo "> Notes with very similar titles (Levenshtein distance < 3 or Jaccard similarity > 70%) in the same category."
    echo ""
    echo "| Note A | Note B | Category | Levenshtein | Jaccard | Action |"
    echo "|--------|--------|----------|-------------|---------|--------|"
    while IFS='	' read -r path1 path2 cat lev jac; do
        [ -z "$path1" ] && continue
        bn1=$(basename "$path1"); bn2=$(basename "$path2")
        printf "| \`%s\` | \`%s\` | %s | %s | %s%% | manual merge |\n" \
            "$bn1" "$bn2" "$cat" "$lev" "$jac"
    done < "$DUP_FILE"
fi
echo ""

# Summary
echo "## Summary"
echo ""
echo "| Type | Count |"
echo "|------|-------|"
printf "| Decay (archive) | %s |\n" "$DECAY_COUNT"
printf "| Trivial (delete) | %s |\n" "$TRIVIAL_COUNT"
printf "| Duplicates (merge) | %s |\n" "$DUP_COUNT"
printf "| **Total candidates** | **%s** |\n" "$TOTAL"
echo ""

if [ "$FLAG_APPLY" -eq 0 ]; then
    if [ "$TOTAL" -eq 0 ]; then
        echo "_Vault is clean — no action needed._"
    else
        echo "_Dry-run complete. Run with \`--apply\` to execute archiving and deletion._"
        echo "_Duplicate merges always require manual review._"
    fi
fi

# --- Apply mode ---
if [ "$FLAG_APPLY" -eq 1 ]; then
    if [ "$TOTAL" -eq 0 ]; then
        echo "_No candidates to process._"
        exit 0
    fi

    APPLIED=0
    SKIPPED=0

    echo "---"
    echo ""
    echo "## Apply"
    echo ""

    # Apply: archive decay candidates
    if [ "$DECAY_COUNT" -gt 0 ]; then
        echo "### Archiving decay candidates"
        echo ""
        while IFS='	' read -r path note_date age_days year; do
            [ -z "$path" ] && continue
            bn=$(basename "$path")
            archive_dir="$VAULT_NOTES_DIR/_archive/$year"

            if [ "$FLAG_YES" -eq 0 ]; then
                printf "Archive \`%s\` → \`_archive/%s/\`? [y/N] " "$bn" "$year"
                if [ -c /dev/tty ] 2>/dev/null; then
                    read -r answer < /dev/tty
                else
                    answer="n"
                    echo "N (non-interactive)"
                fi
                case "$answer" in
                    [Yy]*) ;;
                    *) echo "Skipped."; SKIPPED=$(( SKIPPED + 1 )); continue ;;
                esac
            fi

            mkdir -p "$archive_dir"
            mv "$path" "$archive_dir/$bn"
            echo "Archived: \`$bn\` → \`_archive/$year/\`"
            APPLIED=$(( APPLIED + 1 ))
        done < "$DECAY_FILE"
        echo ""
    fi

    # Apply: delete trivial candidates
    if [ "$TRIVIAL_COUNT" -gt 0 ]; then
        echo "### Deleting trivial candidates"
        echo ""
        while IFS='	' read -r path cat lines; do
            [ -z "$path" ] && continue
            bn=$(basename "$path")

            if [ "$FLAG_YES" -eq 0 ]; then
                printf "Delete \`%s\` (%s lines)? [y/N] " "$bn" "$lines"
                read -r answer < /dev/tty
                case "$answer" in
                    [Yy]*) ;;
                    *) echo "Skipped."; SKIPPED=$(( SKIPPED + 1 )); continue ;;
                esac
            fi

            rm "$path"
            echo "Deleted: \`$bn\`"
            APPLIED=$(( APPLIED + 1 ))
        done < "$TRIVIAL_FILE"
        echo ""
    fi

    # Duplicates: report only, no auto-action
    if [ "$DUP_COUNT" -gt 0 ]; then
        echo "### Semantic duplicates — manual action required"
        echo ""
        echo "> Duplicate merges cannot be automated. Review the pairs above and merge manually."
        echo ""
    fi

    echo "---"
    echo ""
    printf "_Applied: %s | Skipped: %s_\n" "$APPLIED" "$SKIPPED"
    if [ "$APPLIED" -gt 0 ]; then
        echo ""
        echo "> **Note:** MEMORY.md entries for modified notes must be updated manually."
        echo "> Run \`/strata-doctor --fix\` to detect and repair orphaned references."
    fi
fi
