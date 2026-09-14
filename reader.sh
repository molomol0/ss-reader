#!/bin/bash

SITE_URL="https://www.readernovel.net"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/.reader_data"
NOVELS_FILE="$DATA_DIR/novels"         # slug|name per line
ACTIVE_FILE="$DATA_DIR/active_novel"   # current novel slug
CATALOG_CACHE="$DATA_DIR/catalog"     # cached full novel catalog from site

mkdir -p "$DATA_DIR"

# --- Novel management ---

# Get active novel slug
get_active_novel() {
    if [[ -f "$ACTIVE_FILE" ]]; then
        cat "$ACTIVE_FILE"
    else
        echo ""
    fi
}

set_active_novel() {
    echo "$1" > "$ACTIVE_FILE"
}

# Per-novel paths
novel_progress_file() {
    echo "$DATA_DIR/${1}.progress"
}

novel_chapter_cache() {
    echo "$DATA_DIR/${1}.chapters"
}

# Migrate old single-novel data if present
migrate_old_data() {
    local old_progress="$SCRIPT_DIR/.ss_reader_progress"
    local old_chapters="$SCRIPT_DIR/.ss_reader_chapters"
    local slug="shadow-slave-62"

    if [[ -f "$old_chapters" || -f "$old_progress" ]]; then
        echo "Migrating old Shadow Slave data..."
        # Register the novel
        if ! grep -q "^${slug}|" "$NOVELS_FILE" 2>/dev/null; then
            echo "${slug}|Shadow Slave" >> "$NOVELS_FILE"
        fi
        # Move files
        [[ -f "$old_chapters" ]] && mv "$old_chapters" "$(novel_chapter_cache "$slug")"
        [[ -f "$old_progress" ]] && mv "$old_progress" "$(novel_progress_file "$slug")"
        # Set as active if none
        [[ ! -f "$ACTIVE_FILE" ]] && set_active_novel "$slug"
        echo "Done."
    fi
}

# Load saved chapter for a novel
load_progress() {
    local novel_slug="$1"
    local pfile
    pfile=$(novel_progress_file "$novel_slug")
    if [[ -f "$pfile" ]]; then
        cat "$pfile"
    else
        echo ""
    fi
}

# Save current chapter slug for a novel
save_progress() {
    local novel_slug="$1"
    local chapter_slug="$2"
    echo "$chapter_slug" > "$(novel_progress_file "$novel_slug")"
}

# Fetch and cache the chapter list for the active novel
fetch_chapter_list() {
    local novel_slug="$1"
    local cache
    cache=$(novel_chapter_cache "$novel_slug")

    if [[ -f "$cache" && $(find "$cache" -mmin -60 2>/dev/null) ]]; then
        return
    fi
    echo "Fetching chapter list for $novel_slug..."
    local novel_url="${SITE_URL}/novel/${novel_slug}/"
    local page
    page=$(curl -s "$novel_url")
    if [[ -z "$page" ]]; then
        echo "Error: could not fetch novel page."
        return 1
    fi

    # Extract chapter slug and title pairs
    # Pattern: href="/read/<novel-slug>/<chapter-slug>" ... title="<title>"
    local combined
    combined=$(echo "$page" | tr '\n' ' ' \
        | grep -oP "href=\"/read/${novel_slug}/([^\"]+)\"[^>]*title=\"([^\"]+)\"" \
        | sed -E "s#href=\"/read/${novel_slug}/([^\"]+)\"[^>]*title=\"([^\"]+)\"#\1|\2#")

    if [[ -z "$combined" ]]; then
        echo "Error: no chapters found."
        return 1
    fi

    # Reverse (site lists newest first) and deduplicate
    echo "$combined" | tac | awk -F'|' '!seen[$1]++' > "$cache"
}

# --- Chapter navigation ---

get_chapter_lines() {
    local novel_slug="$1"
    cat "$(novel_chapter_cache "$novel_slug")"
}

get_slug_for_chapter() {
    local novel_slug="$1"
    local chapter_num="$2"
    local cache
    cache=$(novel_chapter_cache "$novel_slug")
    grep -iP "\|Chapter\s+${chapter_num}(:|$|\s*$)" "$cache" | head -1 | cut -d'|' -f1
}

get_adjacent_slug() {
    local novel_slug="$1"
    local current_slug="$2"
    local direction="$3"  # "next" or "prev"
    local cache
    cache=$(novel_chapter_cache "$novel_slug")
    local line_num
    line_num=$(grep -n "^${current_slug}|" "$cache" | head -1 | cut -d: -f1)
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
    sed -n "${line_num}p" "$cache" | cut -d'|' -f1
}

# Decode all HTML entities (named like &mdash; and numeric like &#8217;),
# whether standalone or inside a word
decode_entities() {
    if command -v python3 &>/dev/null; then
        python3 -c 'import html,sys; sys.stdout.write(html.unescape(sys.stdin.read()))'
    else
        # Fallback: common entities only
        sed 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#0*39;/'"'"'/g; s/&apos;/'"'"'/g;
             s/&nbsp;/ /g; s/&lsquo;/‘/g; s/&rsquo;/’/g; s/&ldquo;/“/g; s/&rdquo;/”/g;
             s/&mdash;/—/g; s/&ndash;/–/g; s/&hellip;/…/g; s/&#8216;/‘/g; s/&#8217;/’/g;
             s/&#8220;/“/g; s/&#8221;/”/g; s/&#8211;/–/g; s/&#8212;/—/g; s/&#8230;/…/g;
             s/&amp;/\&/g'
    fi
}

# Fetch and display a chapter
read_chapter() {
    local novel_slug="$1"
    local chapter_slug="$2"
    if [[ -z "$chapter_slug" ]]; then
        echo "No chapter selected."
        return 1
    fi

    local url="${SITE_URL}/read/${novel_slug}/${chapter_slug}"
    local cache
    cache=$(novel_chapter_cache "$novel_slug")
    local chapter_name
    chapter_name=$(grep "^${chapter_slug}|" "$cache" | head -1 | cut -d'|' -f2)

    echo ""
    echo "========================================"
    echo "  ${chapter_name:-$chapter_slug}"
    echo "========================================"
    echo ""

    local term_width
    term_width=$(tput cols 2>/dev/null || echo 80)

    curl -s "$url" \
        | sed -n '/<div id="chapter-container"/,/<\/div>/p' \
        | sed -E 's/<br\s*\/?>/\n/g' \
        | sed -E 's/<p[^>]*>/\n\n/g; s/<\/p>/\n/g' \
        | sed -E 's/<[^>]+>//g' \
        | decode_entities \
        | sed '/^\s*$/{ N; /^\s*\n\s*$/{ s/\n\s*//; }; }' \
        | fold -s -w "$term_width"

    echo ""
    echo "========================================"
    save_progress "$novel_slug" "$chapter_slug"
}

# --- Browse novels from the site ---

# Fetch and cache the full novel catalog (24h TTL)
fetch_catalog() {
    if [[ -f "$CATALOG_CACHE" && $(find "$CATALOG_CACHE" -mmin -1440 2>/dev/null) ]]; then
        return
    fi
    echo ""
    echo "Fetching novel catalog from ${SITE_URL}..."
    echo "(This fetches all pages — may take a moment)"
    echo ""

    local all_novels=""
    local page_num=1

    while true; do
        local url="${SITE_URL}/browse?sort=date&status=0&p=${page_num}"
        local page_html
        page_html=$(curl -s "$url")

        local found
        found=$(echo "$page_html" | tr '\n' ' ' \
            | grep -oP 'href="/novel/([^"]+)"[^>]*title="([^"]+)"' \
            | sed -E 's#href="/novel/([^"]+)"[^>]*title="([^"]+)"#\1|\2#' \
            | sed 's#/$##')

        if [[ -z "$found" ]]; then
            break
        fi

        if [[ -z "$all_novels" ]]; then
            all_novels="$found"
        else
            all_novels="$all_novels"$'\n'"$found"
        fi

        echo "  Fetched page $page_num..."
        page_num=$((page_num + 1))
    done

    # Deduplicate and save
    echo "$all_novels" | awk -F'|' '!seen[$1]++' > "$CATALOG_CACHE"
    local total
    total=$(wc -l < "$CATALOG_CACHE")
    echo "Cached $total novels (valid for 24h)."
}

browse_novels() {
    fetch_catalog

    if [[ ! -f "$CATALOG_CACHE" || ! -s "$CATALOG_CACHE" ]]; then
        echo "No catalog available. Check your internet connection."
        return
    fi

    local selection

    if command -v fzf &>/dev/null; then
        # fzf mode: show novel names, fuzzy search in real time
        selection=$(cut -d'|' -f2 "$CATALOG_CACHE" \
            | fzf --header="Type to search novels — Enter to select, Esc to cancel" \
                  --height=40% --reverse \
                  --preview-window=hidden)

        if [[ -z "$selection" ]]; then
            return
        fi

        local sel_slug sel_name
        sel_name="$selection"
        sel_slug=$(grep "|${sel_name}$" "$CATALOG_CACHE" | head -1 | cut -d'|' -f1)
        sel_slug="${sel_slug%/}"
    else
        # Fallback: manual search
        local total
        total=$(wc -l < "$CATALOG_CACHE")
        echo ""
        echo "$total novels available. Enter a search term to filter:"
        echo "(Install fzf for real-time fuzzy search)"
        read -rp "Search: " search_term

        if [[ -z "$search_term" ]]; then
            echo "No search term entered."
            return
        fi

        local matches
        matches=$(grep -i "$search_term" "$CATALOG_CACHE")

        if [[ -z "$matches" ]]; then
            echo "No novels matching '$search_term'."
            return
        fi

        echo ""
        echo "Matching novels:"
        local i=1
        local slugs=()
        local names=()
        while IFS='|' read -r slug name; do
            slug="${slug%/}"
            slugs+=("$slug")
            names+=("$name")
            echo "  [$i] $name"
            i=$((i + 1))
        done <<< "$matches"

        echo ""
        read -rp "Select a novel number (or 0 to cancel): " choice

        if [[ "$choice" == "0" || -z "$choice" ]]; then
            return
        fi

        local idx=$((choice - 1))
        if [[ $idx -lt 0 || $idx -ge ${#slugs[@]} ]]; then
            echo "Invalid selection."
            return
        fi

        local sel_slug="${slugs[$idx]}"
        local sel_name="${names[$idx]}"
    fi

    # Register novel if not already saved
    if ! grep -q "^${sel_slug}|" "$NOVELS_FILE" 2>/dev/null; then
        echo "${sel_slug}|${sel_name}" >> "$NOVELS_FILE"
        echo "Added '$sel_name' to your library."
    else
        echo "'$sel_name' is already in your library."
    fi

    # Set as active
    set_active_novel "$sel_slug"
    echo "Active novel set to: $sel_name"
}

# --- Switch between saved novels ---

switch_novel() {
    if [[ ! -f "$NOVELS_FILE" || ! -s "$NOVELS_FILE" ]]; then
        echo "No novels saved. Use [a]dd to browse and add one."
        return 1
    fi

    local active
    active=$(get_active_novel)

    echo ""
    echo "Your novels:"
    local i=1
    local slugs=()
    while IFS='|' read -r slug name; do
        slugs+=("$slug")
        local progress_slug
        progress_slug=$(load_progress "$slug")
        local marker=""
        [[ "$slug" == "$active" ]] && marker=" (active)"

        local progress_info=""
        if [[ -n "$progress_slug" ]]; then
            local cache
            cache=$(novel_chapter_cache "$slug")
            if [[ -f "$cache" ]]; then
                local chap_name
                chap_name=$(grep "^${progress_slug}|" "$cache" | head -1 | cut -d'|' -f2)
                progress_info=" — last read: ${chap_name:-$progress_slug}"
            fi
        fi

        echo "  [$i] ${name}${marker}${progress_info}"
        i=$((i + 1))
    done < "$NOVELS_FILE"

    echo ""
    read -rp "Select a novel number (or 0 to cancel): " choice

    if [[ "$choice" == "0" || -z "$choice" ]]; then
        return 1
    fi

    local idx=$((choice - 1))
    if [[ $idx -lt 0 || $idx -ge ${#slugs[@]} ]]; then
        echo "Invalid selection."
        return 1
    fi

    set_active_novel "${slugs[$idx]}"
    local sel_name
    sel_name=$(grep "^${slugs[$idx]}|" "$NOVELS_FILE" | head -1 | cut -d'|' -f2)
    echo "Active novel set to: $sel_name"
    return 0
}

# --- Main ---

main() {
    migrate_old_data

    local novel_slug
    novel_slug=$(get_active_novel)

    # If no novel is set, prompt to add one
    if [[ -z "$novel_slug" ]]; then
        echo ""
        echo "=== Novel Reader ==="
        echo "No novel selected. Let's add one!"
        browse_novels
        novel_slug=$(get_active_novel)
        if [[ -z "$novel_slug" ]]; then
            echo "No novel selected. Exiting."
            exit 0
        fi
    fi

    fetch_chapter_list "$novel_slug"

    local cache
    cache=$(novel_chapter_cache "$novel_slug")
    if [[ ! -f "$cache" ]]; then
        echo "Failed to fetch chapter list. Check your internet connection."
        exit 1
    fi

    local total
    total=$(wc -l < "$cache")
    local current_slug
    current_slug=$(load_progress "$novel_slug")

    local novel_name
    novel_name=$(grep "^${novel_slug}|" "$NOVELS_FILE" | head -1 | cut -d'|' -f2)

    echo ""
    echo "=== Novel Reader ==="
    echo "Active novel: ${novel_name:-$novel_slug}"
    echo "Total chapters available: $total"

    if [[ -n "$current_slug" ]]; then
        local current_name
        current_name=$(grep "^${current_slug}|" "$cache" | head -1 | cut -d'|' -f2)
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
        echo "  [s]witch   - Switch to another saved novel"
        echo "  [a]dd      - Browse & add a new novel"
        echo "  [q]uit     - Exit"
        echo ""
        read -rp "> " cmd

        case "$cmd" in
            n|next)
                if [[ -z "$current_slug" ]]; then
                    current_slug=$(head -1 "$cache" | cut -d'|' -f1)
                else
                    local next_slug
                    next_slug=$(get_adjacent_slug "$novel_slug" "$current_slug" "next")
                    if [[ -z "$next_slug" ]]; then
                        echo "No next chapter available."
                        continue
                    fi
                    current_slug="$next_slug"
                fi
                read_chapter "$novel_slug" "$current_slug" | less -R
                ;;
            p|prev)
                if [[ -z "$current_slug" ]]; then
                    echo "No current chapter. Use 'goto' first."
                    continue
                fi
                local prev_slug
                prev_slug=$(get_adjacent_slug "$novel_slug" "$current_slug" "prev")
                if [[ -z "$prev_slug" ]]; then
                    echo "No previous chapter available."
                    continue
                fi
                current_slug="$prev_slug"
                read_chapter "$novel_slug" "$current_slug" | less -R
                ;;
            c|current)
                if [[ -z "$current_slug" ]]; then
                    echo "No current chapter. Use 'goto' first."
                    continue
                fi
                read_chapter "$novel_slug" "$current_slug" | less -R
                ;;
            g|goto)
                read -rp "Enter chapter number: " chapter_num
                local slug
                slug=$(get_slug_for_chapter "$novel_slug" "$chapter_num")
                if [[ -z "$slug" ]]; then
                    echo "Chapter $chapter_num not found."
                    continue
                fi
                current_slug="$slug"
                read_chapter "$novel_slug" "$current_slug" | less -R
                ;;
            l|list)
                local current_line=0
                if [[ -n "$current_slug" ]]; then
                    current_line=$(grep -n "^${current_slug}|" "$cache" | head -1 | cut -d: -f1)
                fi
                local start=$((current_line - 5))
                [[ "$start" -lt 1 ]] && start=1
                local end=$((current_line + 5))
                echo ""
                sed -n "${start},${end}p" "$cache" | while IFS='|' read -r slug name; do
                    if [[ "$slug" == "$current_slug" ]]; then
                        echo "  >> $name  <<<"
                    else
                        echo "     $name"
                    fi
                done
                echo ""
                ;;
            s|switch)
                if switch_novel; then
                    novel_slug=$(get_active_novel)
                    fetch_chapter_list "$novel_slug"
                    cache=$(novel_chapter_cache "$novel_slug")
                    current_slug=$(load_progress "$novel_slug")
                    novel_name=$(grep "^${novel_slug}|" "$NOVELS_FILE" | head -1 | cut -d'|' -f2)
                    total=$(wc -l < "$cache")
                    echo ""
                    echo "Active novel: ${novel_name:-$novel_slug}"
                    echo "Total chapters available: $total"
                    if [[ -n "$current_slug" ]]; then
                        local cname
                        cname=$(grep "^${current_slug}|" "$cache" | head -1 | cut -d'|' -f2)
                        echo "Last read: ${cname:-$current_slug}"
                    else
                        echo "No reading progress for this novel."
                    fi
                    echo ""
                fi
                ;;
            a|add)
                browse_novels
                # If the user added and activated a new one, switch context
                local new_slug
                new_slug=$(get_active_novel)
                if [[ "$new_slug" != "$novel_slug" ]]; then
                    novel_slug="$new_slug"
                    fetch_chapter_list "$novel_slug"
                    cache=$(novel_chapter_cache "$novel_slug")
                    current_slug=$(load_progress "$novel_slug")
                    novel_name=$(grep "^${novel_slug}|" "$NOVELS_FILE" | head -1 | cut -d'|' -f2)
                    total=$(wc -l < "$cache")
                    echo ""
                    echo "Active novel: ${novel_name:-$novel_slug}"
                    echo "Total chapters available: $total"
                    if [[ -n "$current_slug" ]]; then
                        local cname2
                        cname2=$(grep "^${current_slug}|" "$cache" | head -1 | cut -d'|' -f2)
                        echo "Last read: ${cname2:-$current_slug}"
                    else
                        echo "No reading progress for this novel."
                    fi
                    echo ""
                fi
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
