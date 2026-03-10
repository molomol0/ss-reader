#!/bin/bash

BASE_URL="https://www.readernovel.net/read/shadow-slave-62"
NOVEL_URL="https://www.readernovel.net/novel/shadow-slave-62/"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAVE_FILE="$SCRIPT_DIR/.ss_reader_progress"
CHAPTER_CACHE="$SCRIPT_DIR/.ss_reader_chapters"

# Load saved chapter
load_progress() {
    if [[ -f "$SAVE_FILE" ]]; then
        cat "$SAVE_FILE"
    else
        echo ""
    fi
}

# Save current chapter slug
save_progress() {
    echo "$1" > "$SAVE_FILE"
}

# Fetch and cache the chapter list (slug -> display name)
fetch_chapter_list() {
    if [[ -f "$CHAPTER_CACHE" && $(find "$CHAPTER_CACHE" -mmin -60 2>/dev/null) ]]; then
        return
    fi
    echo "Fetching chapter list..."
    local page
    page=$(curl -s "$NOVEL_URL")
    local slugs titles
    slugs=$(echo "$page" | grep -oP '(?<=href="/read/shadow-slave-62/)[^"]+')
    titles=$(echo "$page" | grep -A1 'href="/read/shadow-slave-62/' | grep -oP '(?<=title=")[^"]+')
    paste -d'|' <(echo "$slugs") <(echo "$titles") | tac > "$CHAPTER_CACHE"
}

# Get slug for a chapter number
get_slug_for_chapter() {
    local chapter_num="$1"
    # Match "Chapter <num>" (possibly followed by colon and title)
    grep -iP "\|Chapter\s+${chapter_num}(:|$|\s*$)" "$CHAPTER_CACHE" | head -1 | cut -d'|' -f1
}

# Get chapter number from slug
get_chapter_num_from_slug() {
    local slug="$1"
    grep "^${slug}|" "$CHAPTER_CACHE" | head -1 | cut -d'|' -f2 | grep -oP '\d+'
}

# Get next/previous slug
get_adjacent_slug() {
    local current_slug="$1"
    local direction="$2"  # "next" or "prev"
    local line_num
    line_num=$(grep -n "^${current_slug}|" "$CHAPTER_CACHE" | head -1 | cut -d: -f1)
    if [[ -z "$line_num" ]]; then
        echo ""
        return
    fi
    if [[ "$direction" == "next" ]]; then
        line_num=$((line_num + 1))
    else
        line_num=$((line_num - 1))
    fi
    if [[ "$line_num" -lt 1 ]]; then
        echo ""
        return
    fi
    sed -n "${line_num}p" "$CHAPTER_CACHE" | cut -d'|' -f1
}

# Fetch and display a chapter
read_chapter() {
    local slug="$1"
    if [[ -z "$slug" ]]; then
        echo "No chapter selected."
        return 1
    fi

    local url="${BASE_URL}/${slug}"
    local chapter_name
    chapter_name=$(grep "^${slug}|" "$CHAPTER_CACHE" | head -1 | cut -d'|' -f2)

    echo ""
    echo "========================================"
    echo "  ${chapter_name:-$slug}"
    echo "========================================"
    echo ""

    local term_width
    term_width=$(tput cols 2>/dev/null || echo 80)

    curl -s "$url" \
        | sed -n '/<div id="chapter-container"/,/<\/div>/p' \
        | sed -E 's/<br\s*\/?>/\n/g' \
        | sed -E 's/<p[^>]*>/\n\n/g; s/<\/p>/\n/g' \
        | sed -E 's/<[^>]+>//g' \
        | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g; s/&nbsp;/ /g' \
        | sed '/^\s*$/{ N; /^\s*\n\s*$/{ s/\n\s*//; }; }' \
        | fold -s -w "$term_width"

    echo ""
    echo "========================================"
    save_progress "$slug"
}

# Main menu
main() {
    fetch_chapter_list

    local total
    total=$(wc -l < "$CHAPTER_CACHE")
    local current_slug
    current_slug=$(load_progress)

    echo ""
    echo "=== Shadow Slave Reader ==="
    echo "Total chapters available: $total"

    if [[ -n "$current_slug" ]]; then
        local current_name
        current_name=$(grep "^${current_slug}|" "$CHAPTER_CACHE" | head -1 | cut -d'|' -f2)
        echo "Last read: ${current_name:-$current_slug}"
    else
        echo "No reading progress saved."
    fi
    echo ""

    while true; do
        echo "Commands:"
        echo "  [n]ext     - Read next chapter"
        echo "  [p]rev     - Read previous chapter"
        echo "  [c]urrent  - Re-read current chapter"
        echo "  [g]oto     - Jump to a specific chapter number"
        echo "  [l]ist     - List chapters around current position"
        echo "  [q]uit     - Exit"
        echo ""
        read -rp "> " cmd

        case "$cmd" in
            n|next)
                if [[ -z "$current_slug" ]]; then
                    # Start from the first chapter
                    current_slug=$(head -1 "$CHAPTER_CACHE" | cut -d'|' -f1)
                else
                    local next_slug
                    next_slug=$(get_adjacent_slug "$current_slug" "next")
                    if [[ -z "$next_slug" ]]; then
                        echo "No next chapter available."
                        continue
                    fi
                    current_slug="$next_slug"
                fi
                read_chapter "$current_slug" | less -R
                ;;
            p|prev)
                if [[ -z "$current_slug" ]]; then
                    echo "No current chapter. Use 'goto' first."
                    continue
                fi
                local prev_slug
                prev_slug=$(get_adjacent_slug "$current_slug" "prev")
                if [[ -z "$prev_slug" ]]; then
                    echo "No previous chapter available."
                    continue
                fi
                current_slug="$prev_slug"
                read_chapter "$current_slug" | less -R
                ;;
            c|current)
                if [[ -z "$current_slug" ]]; then
                    echo "No current chapter. Use 'goto' first."
                    continue
                fi
                read_chapter "$current_slug" | less -R
                ;;
            g|goto)
                read -rp "Enter chapter number: " chapter_num
                local slug
                slug=$(get_slug_for_chapter "$chapter_num")
                if [[ -z "$slug" ]]; then
                    echo "Chapter $chapter_num not found."
                    continue
                fi
                current_slug="$slug"
                read_chapter "$current_slug" | less -R
                ;;
            l|list)
                local current_line=0
                if [[ -n "$current_slug" ]]; then
                    current_line=$(grep -n "^${current_slug}|" "$CHAPTER_CACHE" | head -1 | cut -d: -f1)
                fi
                local start=$((current_line - 5))
                [[ "$start" -lt 1 ]] && start=1
                local end=$((current_line + 5))
                echo ""
                sed -n "${start},${end}p" "$CHAPTER_CACHE" | while IFS='|' read -r slug name; do
                    if [[ "$slug" == "$current_slug" ]]; then
                        echo "  >> $name  <<<"
                    else
                        echo "     $name"
                    fi
                done
                echo ""
                ;;
            q|quit)
                echo "Goodbye! Progress saved."
                exit 0
                ;;
            *)
                echo "Unknown command: $cmd"
                ;;
        esac
    done
}

main
