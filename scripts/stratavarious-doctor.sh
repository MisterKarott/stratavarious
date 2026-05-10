#!/bin/bash
# stratavarious-doctor.sh — Audit vault integrity
# Usage: ./stratavarious-doctor.sh [--json] [--fix] [--yes] [vault-dir]
# Exit: 0=healthy, 1=warnings only, 2=errors found
# Compatible with Bash 3.2 (macOS default)
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
StrataVarious_HOME="${StrataVarious_HOME:-$HOME/.claude/workspace/stratavarious}"

# --- Flags ---
FLAG_JSON=0
FLAG_FIX=0
FLAG_YES=0
VAULT_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json) FLAG_JSON=1; shift ;;
        --fix)  FLAG_FIX=1;  shift ;;
        --yes)  FLAG_YES=1;  shift ;;
        --*)    echo "Unknown flag: $1" >&2; exit 2 ;;
        *)      VAULT_DIR="$1"; shift ;;
    esac
done

# Determine MEMORY_FILE and VAULT_NOTES_DIR
# Support two calling conventions:
#   1. Default: vault-dir = $StrataVarious_HOME/memory  (contains MEMORY.md + vault/)
#   2. Test mode: vault-dir is a flat dir containing MEMORY.md + category subdirs
if [ -z "$VAULT_DIR" ]; then
    VAULT_DIR="$StrataVarious_HOME/memory"
fi

if [ -f "$VAULT_DIR/MEMORY.md" ]; then
    MEMORY_FILE="$VAULT_DIR/MEMORY.md"
    # If vault/ subdir exists, use it; else scan VAULT_DIR itself (test mode)
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

TMPDIR_DOCTOR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$TMPDIR_DOCTOR'" EXIT

ERRORS_FILE="$TMPDIR_DOCTOR/errors.txt"
WARNINGS_FILE="$TMPDIR_DOCTOR/warnings.txt"
touch "$ERRORS_FILE" "$WARNINGS_FILE"

add_error()   { echo "$1" >> "$ERRORS_FILE"; }
add_warning() { echo "$1" >> "$WARNINGS_FILE"; }

# --- Parse MEMORY.md: extract referenced basenames ---
# Lines format: - `basename.md` — Title
# shellcheck disable=SC2016  # backreferences in sed regex are intentional, not shell vars
grep '^\- `' "$MEMORY_FILE" 2>/dev/null | \
    sed 's/^- `\([^`]*\)`.*/\1/' > "$TMPDIR_DOCTOR/memory_basenames.txt" || true

# --- Scan vault notes (excluding MEMORY.md, journal/, sessions/) ---
find "$VAULT_NOTES_DIR" -type f -name "*.md" 2>/dev/null | while IFS= read -r f; do
    case "$f" in
        */journal/*)   continue ;;
        */sessions/*)  continue ;;
        */MEMORY.md)   continue ;;
    esac
    echo "$f"
done > "$TMPDIR_DOCTOR/vault_paths.txt" || true

# Build basename list from vault
while IFS= read -r f; do
    [ -z "$f" ] && continue
    basename "$f"
done < "$TMPDIR_DOCTOR/vault_paths.txt" > "$TMPDIR_DOCTOR/vault_basenames.txt" || true

# --- Check 1: Broken links (in MEMORY.md but not in vault) ---
while IFS= read -r bn; do
    [ -z "$bn" ] && continue
    if ! grep -qxF "$bn" "$TMPDIR_DOCTOR/vault_basenames.txt" 2>/dev/null; then
        add_error "BROKEN_LINK: $bn (referenced in MEMORY.md but not found in vault)"
    fi
done < "$TMPDIR_DOCTOR/memory_basenames.txt"

# --- Check 2: Orphans (in vault but not referenced in MEMORY.md) ---
while IFS= read -r path; do
    [ -z "$path" ] && continue
    bn=$(basename "$path")
    if ! grep -qxF "$bn" "$TMPDIR_DOCTOR/memory_basenames.txt" 2>/dev/null; then
        add_error "ORPHAN: $bn (file exists in vault but not referenced in MEMORY.md)"
    fi
done < "$TMPDIR_DOCTOR/vault_paths.txt"

# --- Helper: extract frontmatter field value ---
extract_fm_field() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
    BEGIN { in_fm=0; found_open=0; found_close=0 }
    NR==1 && $0=="---" { in_fm=1; found_open=1; next }
    in_fm && $0=="---" { found_close=1; exit }
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

# --- Check 3: Dates in future or before 2020 ---
while IFS= read -r path; do
    [ -z "$path" ] && continue
    bn=$(basename "$path")
    note_date=$(extract_fm_field "$path" "date")
    [ -z "$note_date" ] && continue
    if [ "$note_date" \> "$TODAY" ]; then
        add_warning "FUTURE_DATE: $bn (date $note_date is in the future)"
    elif [ "$note_date" \< "2020-01-01" ]; then
        add_warning "OLD_DATE: $bn (date $note_date is before 2020)"
    fi
done < "$TMPDIR_DOCTOR/vault_paths.txt"

# --- Check 4: Malformed tags (not in #lowercase format) ---
while IFS= read -r path; do
    [ -z "$path" ] && continue
    bn=$(basename "$path")
    tags=$(extract_fm_field "$path" "tags")
    [ -z "$tags" ] && continue
    # Skip array format (validate.sh handles it)
    case "$tags" in
        \[*) continue ;;
    esac
    # Valid: one or more #lowercase-word tokens separated by spaces
    if ! echo "$tags" | grep -qE '^(#[a-z0-9_-]+ *)+$'; then
        add_warning "BAD_TAGS: $bn (tags not in #lowercase format: $tags)"
    fi
done < "$TMPDIR_DOCTOR/vault_paths.txt"

# --- Check 5: Frontmatter validation via validate.sh ---
VALIDATE_SCRIPT="$SCRIPT_DIR/stratavarious-validate.sh"
if [ -x "$VALIDATE_SCRIPT" ]; then
    val_output=$(bash "$VALIDATE_SCRIPT" "$VAULT_NOTES_DIR" 2>&1) || true
    echo "$val_output" | while IFS= read -r line; do
        case "$line" in
            FAIL*)
                tmp="${line#FAIL }"; bn="${tmp%% *}"
                tmp2="${line#FAIL }"; msg="${tmp2#* — }"
                add_error "FRONTMATTER: $bn — $msg"
                ;;
            WARN*)
                tmp="${line#WARN }"; bn="${tmp%% *}"
                tmp2="${line#WARN }"; msg="${tmp2#* — }"
                add_warning "FRONTMATTER_WARN: $bn — $msg"
                ;;
        esac
    done
fi

# --- Check 6: Duplicate titles within same MEMORY.md section ---
current_section=""
while IFS= read -r line; do
    case "$line" in
        "## "*)
            current_section=$(echo "$line" | sed 's/^## //' | tr '[:upper:]' '[:lower:]')
            ;;
        "- \`"*)
            if [ -n "$current_section" ]; then
                tmp="${line#*\`}"; bn="${tmp%%\`*}"
                tmp2="${line#*\` — }"; title="$tmp2"
                echo "${current_section}|${title}|${bn}" >> "$TMPDIR_DOCTOR/title_index.txt"
            fi
            ;;
    esac
done < "$MEMORY_FILE"

if [ -f "$TMPDIR_DOCTOR/title_index.txt" ]; then
    sort "$TMPDIR_DOCTOR/title_index.txt" | awk -F'|' '
    {
        key = $1 "|" $2
        if (key == prev_key && prev_key != "") {
            print "DUPLICATE|" prev_bn "|" $3 "|" $2
        }
        prev_key = key
        prev_bn = $3
    }
    ' | while IFS='|' read -r _ bn1 bn2 title; do
        add_warning "DUPLICATE: $bn1 and $bn2 share the same title: \"$title\""
    done
fi

# --- Compute counts ---
ERROR_COUNT=$(grep -c '' "$ERRORS_FILE" 2>/dev/null || echo 0)
WARNING_COUNT=$(grep -c '' "$WARNINGS_FILE" 2>/dev/null || echo 0)

# --- Report: Markdown ---
if [ "$FLAG_JSON" -eq 0 ]; then
    echo "## StrataVarious Doctor Report"
    echo ""
    echo "Vault: $VAULT_NOTES_DIR"
    echo "Date:  $TODAY"
    echo ""
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "### Errors"
        echo ""
        while IFS= read -r e; do
            [ -z "$e" ] && continue
            echo "- $e"
        done < "$ERRORS_FILE"
        echo ""
    fi
    if [ "$WARNING_COUNT" -gt 0 ]; then
        echo "### Warnings"
        echo ""
        while IFS= read -r w; do
            [ -z "$w" ] && continue
            echo "- $w"
        done < "$WARNINGS_FILE"
        echo ""
    fi
    if [ "$ERROR_COUNT" -eq 0 ] && [ "$WARNING_COUNT" -eq 0 ]; then
        echo "Vault is healthy — no issues found."
    else
        echo "### Summary"
        echo ""
        echo "Errors: $ERROR_COUNT | Warnings: $WARNING_COUNT"
    fi
fi

# --- Report: JSON ---
if [ "$FLAG_JSON" -eq 1 ]; then
    errors_array=$(grep -v '^$' "$ERRORS_FILE" 2>/dev/null | \
        sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/' | \
        paste -sd',' - 2>/dev/null || echo "")
    warnings_array=$(grep -v '^$' "$WARNINGS_FILE" 2>/dev/null | \
        sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/' | \
        paste -sd',' - 2>/dev/null || echo "")
    echo "{\"errors\":[${errors_array}],\"warnings\":[${warnings_array}],\"error_count\":${ERROR_COUNT},\"warning_count\":${WARNING_COUNT}}"
fi

# --- Fix mode ---
if [ "$FLAG_FIX" -eq 1 ]; then
    echo ""
    echo "=== Fix Mode ==="

    # Fix orphans: add to MEMORY.md under correct category
    if [ -s "$ERRORS_FILE" ]; then
        while IFS= read -r line; do
            case "$line" in
                ORPHAN:*)
                    tmp="${line#ORPHAN: }"; bn="${tmp%% *}"
                    orphan_path=$(grep "/${bn}$" "$TMPDIR_DOCTOR/vault_paths.txt" 2>/dev/null | head -1)
                    [ -z "$orphan_path" ] && continue
                    cat=$(extract_fm_field "$orphan_path" "categorie")
                    [ -z "$cat" ] && cat="decisions"
                    note_title=$(awk '
                        /^---$/ { if (started) { in_fm=!in_fm } else { in_fm=1; started=1 } next }
                        in_fm { next }
                        /^# / { sub(/^# /,""); print; exit }
                    ' "$orphan_path" 2>/dev/null)
                    [ -z "$note_title" ] && note_title="$bn"
                    section=$(echo "$cat" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
                    echo "  Orphan: $bn → ## $section"
                    proceed=y
                    if [ "$FLAG_YES" -eq 0 ]; then
                        printf "  Add to MEMORY.md? [y/N] "
                        read -r proceed
                    fi
                    if [ "$proceed" = "y" ] || [ "$proceed" = "Y" ]; then
                        awk -v header="## $section" -v entry="- \`$bn\` — $note_title" '
                            $0 == header { print; print entry; next }
                            { print }
                        ' "$MEMORY_FILE" > "$TMPDIR_DOCTOR/MEMORY_fixed.md"
                        cp "$TMPDIR_DOCTOR/MEMORY_fixed.md" "$MEMORY_FILE"
                        echo "  Fixed: $bn added to ## $section"
                    fi
                    ;;
            esac
        done < "$ERRORS_FILE"
    fi

    # Fix bad tags: normalize to #lowercase format
    if [ -s "$WARNINGS_FILE" ]; then
        while IFS= read -r line; do
            case "$line" in
                BAD_TAGS:*)
                    tmp="${line#BAD_TAGS: }"; bn="${tmp%% *}"
                    note_path=$(grep "/${bn}$" "$TMPDIR_DOCTOR/vault_paths.txt" 2>/dev/null | head -1)
                    [ -z "$note_path" ] && continue
                    old_tags=$(extract_fm_field "$note_path" "tags")
                    new_tags=$(echo "$old_tags" | tr '[:upper:]' '[:lower:]' | \
                        sed 's/[^a-z0-9 #_-]//g' | tr -s ' ' | \
                        awk '{for(i=1;i<=NF;i++){w=$i; if(substr(w,1,1)!="#")w="#"w; printf "%s ",w}} END{print ""}' | \
                        sed 's/ *$//')
                    echo "  Tags: $bn: '$old_tags' → '$new_tags'"
                    proceed=y
                    if [ "$FLAG_YES" -eq 0 ]; then
                        printf "  Normalize? [y/N] "
                        read -r proceed
                    fi
                    if [ "$proceed" = "y" ] || [ "$proceed" = "Y" ]; then
                        sed "s|^tags: .*|tags: \"$new_tags\"|" "$note_path" > "$TMPDIR_DOCTOR/note_fixed.md"
                        cp "$TMPDIR_DOCTOR/note_fixed.md" "$note_path"
                        echo "  Fixed: tags normalized in $bn"
                    fi
                    ;;
            esac
        done < "$WARNINGS_FILE"
    fi
fi

# --- Exit code ---
if [ "$ERROR_COUNT" -gt 0 ]; then
    exit 2
elif [ "$WARNING_COUNT" -gt 0 ]; then
    exit 1
else
    exit 0
fi
