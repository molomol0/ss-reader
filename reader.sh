#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/.reader_data"
NOVELS_FILE="$DATA_DIR/novels"         # id|name|site:slug,site:slug,...
ACTIVE_FILE="$DATA_DIR/active_novel"   # current novel id
CATALOG_CACHE="$DATA_DIR/catalog"      # cached ReaderNovel catalog

mkdir -p "$DATA_DIR"

# =====================================================================
#  Site drivers
#  Each supported site knows how to: build its novel/chapter URLs,
#  parse a chapter index (number|locator|title), and crop chapter text.
#  "locator" is whatever a site needs to address a chapter in its URL.
# =====================================================================

# Map a site id to its base URL
site_base() {
    case "$1" in
        readernovel) echo "https://www.readernovel.net" ;;
        asura)       echo "https://asurascans.com" ;;
        *)           echo "" ;;
    esac
}

site_label() {
    case "$1" in
        readernovel) echo "ReaderNovel" ;;
        asura)       echo "Asura Scans" ;;
        *)           echo "$1" ;;
    esac
}

# Detect "site:slug" from a pasted novel URL (or return empty)
detect_site_slug() {
    local url="$1"
    local slug
    if [[ "$url" == *readernovel.net/novel/* ]]; then
        slug=$(echo "$url" | sed -E 's#.*/novel/([^/?#]+).*#\1#')
        echo "readernovel:${slug}"
    elif [[ "$url" == *asura*/novels/* ]]; then
        slug=$(echo "$url" | sed -E 's#.*/novels/([^/?#]+).*#\1#')
        echo "asura:${slug}"
    else
        echo ""
    fi
}

site_novel_url() {
    local site="$1" slug="$2" base
    base=$(site_base "$site")
    case "$site" in
        readernovel) echo "${base}/novel/${slug}/" ;;
        asura)       echo "${base}/novels/${slug}" ;;
    esac
}

site_chapter_url() {
    local site="$1" slug="$2" locator="$3" base
    base=$(site_base "$site")
    case "$site" in
        readernovel) echo "${base}/read/${slug}/${locator}" ;;
        asura)       echo "${base}/novels/${slug}/chapter/${locator}" ;;
    esac
}

# Fetch a site's chapter index -> lines "number|locator|title" (unsorted)
site_fetch_index() {
    local site="$1" slug="$2" url page
    url=$(site_novel_url "$site" "$slug")
    page=$(curl -s -A "Mozilla/5.0" "$url")
    [[ -z "$page" ]] && return 1

    case "$site" in
        readernovel)
            echo "$page" | tr '\n' ' ' \
                | grep -oP "href=\"/read/${slug}/([^\"]+)\"[^>]*title=\"([^\"]+)\"" \
                | sed -E "s#href=\"/read/${slug}/([^\"]+)\"[^>]*title=\"([^\"]+)\"#\1|\2#" \
                | awk -F'|' 'BEGIN{OFS="|"}
                    { n=$1; sub(/.*-chapter-/,"",n); sub(/[^0-9].*/,"",n);
                      if (n=="") next; print n,$1,$2 }'
            ;;
        asura)
            echo "$page" | tr '\n' ' ' \
                | grep -oP "href=\"/novels/${slug}/chapter/[0-9]+\".*?</a>" \
                | sed -E "s#href=\"/novels/${slug}/chapter/([0-9]+)\"[^>]*>(.*)</a>#\1\t\2#" \
                | sed -E 's/<[^>]+>/ /g' \
                | sed -E 's/[[:space:]]+[0-9]+[a-z]+[[:space:]]+ago[[:space:]]*$//I; s/[[:space:]]+just now[[:space:]]*$//I' \
                | decode_entities \
                | sed 's/\xc2\xa0/ /g' \
                | awk -F'\t' 'BEGIN{OFS="|"}
                    $2 ~ /Chapter[[:space:]]+[0-9]/ {
                      gsub(/[[:space:]]+/," ",$2);
                      gsub(/^ +| +$/,"",$2);
                      print $1,$1,$2 }'
            ;;
    esac
}

# Real terminal width. tput cols returns 80 when stdout is a pipe (as it is
# when we feed a pager), so prefer bash's $COLUMNS, then query the tty directly.
get_term_width() {
    local w="${COLUMNS:-}"
    if [[ ! "$w" =~ ^[0-9]+$ || "$w" -lt 20 ]]; then
        w=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
    fi
    if [[ ! "$w" =~ ^[0-9]+$ || "$w" -lt 20 ]]; then
        w=$(tput cols 2>/dev/null)
    fi
    [[ "$w" =~ ^[0-9]+$ && "$w" -ge 20 ]] || w=80
    echo "$w"
}

# Crop a chapter's prose from raw HTML on stdin -> clean text on stdout
site_extract_content() {
    local site="$1"
    local term_width
    term_width=$(get_term_width)

    case "$site" in
        readernovel)
            sed -n '/<div id="chapter-container"/,/<\/div>/p' \
                | sed -E 's/<br\s*\/?>/\n/g' \
                | sed -E 's/<p[^>]*>/\n\n/g; s/<\/p>/\n/g' \
                | sed -E 's/<[^>]+>//g' \
                | decode_entities \
                | sed '/^\s*$/{ N; /^\s*\n\s*$/{ s/\n\s*//; }; }' \
                | fold -s -w "$term_width"
            ;;
        asura)
            # Prose paragraphs are uniquely tagged <p data-para="N" ...>
            tr '\n' ' ' \
                | grep -oP '<p data-para="[0-9]+"[^>]*>.*?</p>' \
                | sed -E 's/<br\s*\/?>/\n/g' \
                | sed -E 's/<[^>]+>//g' \
                | decode_entities \
                | awk 'NF{print; print ""} !NF{next}' \
                | fold -s -w "$term_width"
            ;;
    esac
}

# =====================================================================
#  HTML entity decoding (shared by all sites)
# =====================================================================

decode_entities() {
    if command -v python3 &>/dev/null; then
        python3 -c 'import html,sys; sys.stdout.write(html.unescape(sys.stdin.read()))'
    else
        sed 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#0*39;/'"'"'/g; s/&apos;/'"'"'/g;
             s/&nbsp;/ /g; s/&lsquo;/‘/g; s/&rsquo;/’/g; s/&ldquo;/“/g; s/&rdquo;/”/g;
             s/&mdash;/—/g; s/&ndash;/–/g; s/&hellip;/…/g; s/&#8216;/‘/g; s/&#8217;/’/g;
             s/&#8220;/“/g; s/&#8221;/”/g; s/&#8211;/–/g; s/&#8212;/—/g; s/&#8230;/…/g;
             s/&amp;/\&/g'
    fi
}

# Pager for chapter text. By default we avoid less's "alternate screen"
# (-X) and quit if it fits on one screen (-F), so the chapter stays in the
# terminal and the mouse wheel / scrollback behave normally instead of
# looping on a frozen alternate screen. Override with $READER_PAGER, e.g.
#   READER_PAGER='less -R --mouse --wheel-lines=3'   (scroll inside less)
#   READER_PAGER='cat'                               (no pager at all)
page() {
    if [[ -n "$READER_PAGER" ]]; then
        eval "$READER_PAGER"
    elif command -v less &>/dev/null; then
        less -R --mouse --wheel-lines=3
    else
        cat
    fi
}

# =====================================================================
#  Library & active-novel management
#  A novel entry = id | name | comma-list of "site:slug" sources.
#  Progress is stored by CHAPTER NUMBER so it survives switching source.
# =====================================================================

get_active_novel() { [[ -f "$ACTIVE_FILE" ]] && cat "$ACTIVE_FILE" || echo ""; }
set_active_novel() { echo "$1" > "$ACTIVE_FILE"; }

novel_field() {  # novel_field <id> <field-number>
    grep "^${1}|" "$NOVELS_FILE" 2>/dev/null | head -1 | cut -d'|' -f"$2"
}
novel_name()    { novel_field "$1" 2; }
novel_sources() { novel_field "$1" 3 | tr ',' '\n' | sed '/^$/d'; }

# Active "site:slug" for a novel (defaults to first source)
active_source_file() { echo "$DATA_DIR/${1}.source"; }
get_active_source() {
    local id="$1" f
    f=$(active_source_file "$id")
    if [[ -f "$f" ]]; then
        cat "$f"
    else
        novel_sources "$id" | head -1
    fi
}
set_active_source() { echo "$2" > "$(active_source_file "$1")"; }

# Split "site:slug" into globals SITE / SLUG
parse_source() { SITE="${1%%:*}"; SLUG="${1#*:}"; }

# Per-source chapter cache, per-novel progress
source_cache()   { echo "$DATA_DIR/${1}.${2}.chapters"; }  # id, site
progress_file()  { echo "$DATA_DIR/${1}.progress"; }       # id
load_progress()  { [[ -f "$(progress_file "$1")" ]] && cat "$(progress_file "$1")" || echo ""; }
save_progress()  { echo "$2" > "$(progress_file "$1")"; }

# Generate an unused library id from a slug
make_id() {
    local base="$1" id="$1" i=2
    while grep -q "^${id}|" "$NOVELS_FILE" 2>/dev/null; do
        id="${base}-${i}"; i=$((i + 1))
    done
    echo "$id"
}

# Append a source "site:slug" to an existing novel (if not already present)
add_source_to_novel() {
    local id="$1" src="$2" tmp
    if novel_sources "$id" | grep -qx "$src"; then
        return 1  # already present
    fi
    tmp=$(mktemp)
    awk -F'|' -v id="$id" -v src="$src" 'BEGIN{OFS="|"}
        $1==id { $3=($3==""?src:$3","src) } { print }' "$NOVELS_FILE" > "$tmp"
    mv "$tmp" "$NOVELS_FILE"
    return 0
}

# =====================================================================
#  Chapter index (fetch + cache, 1h TTL)
# =====================================================================

fetch_index() {  # fetch_index <id> <site> <slug>
    local id="$1" site="$2" slug="$3" cache
    cache=$(source_cache "$id" "$site")
    if [[ -f "$cache" && $(find "$cache" -mmin -60 2>/dev/null) ]]; then
        return 0
    fi
    echo "Fetching chapter list from $(site_label "$site")..."
    local lines
    lines=$(site_fetch_index "$site" "$slug")
    if [[ -z "$lines" ]]; then
        echo "Error: no chapters found on $(site_label "$site")."
        return 1
    fi
    # Sort by chapter number ascending, dedupe
    echo "$lines" | sort -t'|' -k1,1n | awk -F'|' '!seen[$1]++' > "$cache"
}

# =====================================================================
#  Chapter lookups & navigation (all keyed by chapter NUMBER)
# =====================================================================

locator_for_number() { grep -P "^${3}\|" "$(source_cache "$1" "$2")" 2>/dev/null | head -1 | cut -d'|' -f2; }
title_for_number()   { grep -P "^${3}\|" "$(source_cache "$1" "$2")" 2>/dev/null | head -1 | cut -d'|' -f3; }
max_number()         { cut -d'|' -f1 "$(source_cache "$1" "$2")" 2>/dev/null | sort -n | tail -1; }
min_number()         { cut -d'|' -f1 "$(source_cache "$1" "$2")" 2>/dev/null | sort -n | head -1; }
chapter_count()      { wc -l < "$(source_cache "$1" "$2")" 2>/dev/null | tr -d ' '; }

# =====================================================================
#  Reading
# =====================================================================

read_chapter() {  # read_chapter <id> <number>
    local id="$1" number="$2"
    [[ -z "$number" ]] && { echo "No chapter selected."; return 1; }

    local src site slug
    src=$(get_active_source "$id"); parse_source "$src"; site="$SITE"; slug="$SLUG"

    local locator title
    locator=$(locator_for_number "$id" "$site" "$number")
    # Asura addresses chapters directly by number, so fall back to that
    [[ -z "$locator" && "$site" == "asura" ]] && locator="$number"
    if [[ -z "$locator" ]]; then
        echo "Chapter $number not found on $(site_label "$site")."
        return 1
    fi
    title=$(title_for_number "$id" "$site" "$number")
    [[ -z "$title" ]] && title="Chapter $number"

    local url
    url=$(site_chapter_url "$site" "$slug" "$locator")

    echo ""
    echo "========================================"
    echo "  ${title}"
    echo "  ($(site_label "$site"))"
    echo "========================================"
    echo ""

    local html body
    html=$(curl -s -A "Mozilla/5.0" "$url")
    body=$(echo "$html" | site_extract_content "$site")

    if [[ -z "$(echo "$body" | tr -d '[:space:]')" ]]; then
        echo "(Could not extract text from this chapter — the site may be down"
        echo " or changed its layout. Try switching source with [o].)"
        return 1
    fi

    echo "$body"
    echo ""
    echo "========================================"
    save_progress "$id" "$number"
}

# =====================================================================
#  Adding novels & sources
# =====================================================================

# Fetch a novel's display name from its page
fetch_novel_name() {
    local site="$1" slug="$2" url page name
    url=$(site_novel_url "$site" "$slug")
    page=$(curl -s -A "Mozilla/5.0" "$url")
    name=$(echo "$page" | grep -oiP '<title>\K[^<]+' | head -1)
    case "$site" in
        asura)       name=$(echo "$name" | sed -E 's/\s*-\s*Asura Scans.*//I') ;;
        readernovel) name=$(echo "$name" | sed -E 's/\s*[-|].*//') ;;
    esac
    name=$(echo "$name" | sed -E 's/^\s+|\s+$//g')
    [[ -z "$name" ]] && name="$slug"
    echo "$name"
}

add_novel_by_url() {
    local url="$1" src
    src=$(detect_site_slug "$url")
    if [[ -z "$src" ]]; then
        echo "Unrecognized URL. Supported: readernovel.net/novel/... or asurascans.com/novels/..."
        return 1
    fi
    parse_source "$src"
    local name id
    echo "Looking up novel on $(site_label "$SITE")..."
    name=$(fetch_novel_name "$SITE" "$SLUG")
    id=$(make_id "$SLUG")
    echo "${id}|${name}|${src}" >> "$NOVELS_FILE"
    set_active_source "$id" "$src"
    set_active_novel "$id"
    echo "Added '$name' (source: $(site_label "$SITE"))."
}

# ReaderNovel catalog browse (fuzzy search) -> adds a readernovel source
fetch_catalog() {
    if [[ -f "$CATALOG_CACHE" && $(find "$CATALOG_CACHE" -mmin -1440 2>/dev/null) ]]; then
        return
    fi
    local base; base=$(site_base readernovel)
    echo ""
    echo "Fetching ReaderNovel catalog (all pages — may take a moment)..."
    local all="" page_num=1
    while true; do
        local page_html found
        page_html=$(curl -s -A "Mozilla/5.0" "${base}/browse?sort=date&status=0&p=${page_num}")
        found=$(echo "$page_html" | tr '\n' ' ' \
            | grep -oP 'href="/novel/([^"]+)"[^>]*title="([^"]+)"' \
            | sed -E 's#href="/novel/([^"]+)"[^>]*title="([^"]+)"#\1|\2#' \
            | sed 's#/$##')
        [[ -z "$found" ]] && break
        all="${all:+$all$'\n'}$found"
        echo "  Fetched page $page_num..."
        page_num=$((page_num + 1))
    done
    echo "$all" | awk -F'|' '!seen[$1]++' > "$CATALOG_CACHE"
    echo "Cached $(wc -l < "$CATALOG_CACHE") novels (valid for 24h)."
}

browse_readernovel() {
    fetch_catalog
    [[ ! -s "$CATALOG_CACHE" ]] && { echo "No catalog available."; return; }

    local sel_slug sel_name
    if command -v fzf &>/dev/null; then
        local selection
        selection=$(cut -d'|' -f2 "$CATALOG_CACHE" \
            | fzf --header="Search ReaderNovel — Enter to select, Esc to cancel" \
                  --height=40% --reverse)
        [[ -z "$selection" ]] && return
        sel_name="$selection"
        sel_slug=$(grep "|${sel_name}$" "$CATALOG_CACHE" | head -1 | cut -d'|' -f1)
    else
        read -rp "Search: " search_term
        [[ -z "$search_term" ]] && return
        local matches; matches=$(grep -i "$search_term" "$CATALOG_CACHE")
        [[ -z "$matches" ]] && { echo "No matches."; return; }
        local i=1 slugs=() names=()
        while IFS='|' read -r slug name; do
            slugs+=("$slug"); names+=("$name"); echo "  [$i] $name"; i=$((i + 1))
        done <<< "$matches"
        read -rp "Select a novel number (or 0 to cancel): " choice
        [[ "$choice" == "0" || -z "$choice" ]] && return
        local idx=$((choice - 1))
        [[ $idx -lt 0 || $idx -ge ${#slugs[@]} ]] && { echo "Invalid selection."; return; }
        sel_slug="${slugs[$idx]}"; sel_name="${names[$idx]}"
    fi
    sel_slug="${sel_slug%/}"

    local src="readernovel:${sel_slug}" id
    id=$(make_id "$sel_slug")
    echo "${id}|${sel_name}|${src}" >> "$NOVELS_FILE"
    set_active_source "$id" "$src"
    set_active_novel "$id"
    echo "Added '$sel_name' (source: ReaderNovel)."
}

add_novel() {
    echo ""
    echo "Add a novel:"
    echo "  [u] Paste a novel URL (Asura Scans or ReaderNovel)"
    echo "  [b] Browse the ReaderNovel catalog"
    echo "  [c] Cancel"
    read -rp "> " how
    case "$how" in
        u|U) read -rp "Novel URL: " url; add_novel_by_url "$url" ;;
        b|B) browse_readernovel ;;
        *)   return 1 ;;
    esac
}

# =====================================================================
#  Source switching (for the current novel)
# =====================================================================

manage_sources() {  # operates on current novel id ($1)
    local id="$1"
    local active; active=$(get_active_source "$id")

    echo ""
    echo "Sources for '$(novel_name "$id")':"
    local i=1 srcs=()
    while IFS= read -r s; do
        srcs+=("$s")
        parse_source "$s"
        local marker=""; [[ "$s" == "$active" ]] && marker=" (active)"
        echo "  [$i] $(site_label "$SITE")${marker}"
        i=$((i + 1))
    done < <(novel_sources "$id")

    echo "  [a] Add a backup source (paste URL)"
    echo "  [0] Cancel"
    read -rp "> " choice

    if [[ "$choice" == "a" || "$choice" == "A" ]]; then
        read -rp "Backup source URL: " url
        local src; src=$(detect_site_slug "$url")
        [[ -z "$src" ]] && { echo "Unrecognized URL."; return 1; }
        if add_source_to_novel "$id" "$src"; then
            echo "Added backup source: $(site_label "${src%%:*}")."
            read -rp "Switch to it now? [y/N] " yn
            [[ "$yn" == "y" || "$yn" == "Y" ]] || return 1
            set_active_source "$id" "$src"
        else
            echo "That source is already attached."
            return 1
        fi
    elif [[ "$choice" == "0" || -z "$choice" ]]; then
        return 1
    else
        local idx=$((choice - 1))
        [[ $idx -lt 0 || $idx -ge ${#srcs[@]} ]] && { echo "Invalid selection."; return 1; }
        set_active_source "$id" "${srcs[$idx]}"
    fi

    parse_source "$(get_active_source "$id")"
    echo "Active source: $(site_label "$SITE"). Re-fetching chapter list (keeping your place by chapter number)..."
    fetch_index "$id" "$SITE" "$SLUG"
    return 0
}

# =====================================================================
#  Switch between saved novels
# =====================================================================

switch_novel() {
    [[ ! -s "$NOVELS_FILE" ]] && { echo "No novels saved. Use [a]dd first."; return 1; }
    local active; active=$(get_active_novel)

    echo ""
    echo "Your novels:"
    local i=1 ids=()
    while IFS='|' read -r id name sources; do
        ids+=("$id")
        parse_source "$(get_active_source "$id")"
        local marker=""; [[ "$id" == "$active" ]] && marker=" (active)"
        local prog; prog=$(load_progress "$id")
        local info=""
        [[ -n "$prog" ]] && info=" — last read: Chapter ${prog}"
        echo "  [$i] ${name} [$(site_label "$SITE")]${marker}${info}"
        i=$((i + 1))
    done < "$NOVELS_FILE"

    read -rp "Select a novel number (or 0 to cancel): " choice
    [[ "$choice" == "0" || -z "$choice" ]] && return 1
    local idx=$((choice - 1))
    [[ $idx -lt 0 || $idx -ge ${#ids[@]} ]] && { echo "Invalid selection."; return 1; }

    set_active_novel "${ids[$idx]}"
    echo "Active novel: $(novel_name "${ids[$idx]}")"
    return 0
}

# =====================================================================
#  One-time migration from the old single-site data model
# =====================================================================

migrate_old_data() {
    # 1) Legacy single-novel dotfiles (very old installs)
    local old_progress="$SCRIPT_DIR/.ss_reader_progress"
    local old_chapters="$SCRIPT_DIR/.ss_reader_chapters"
    if [[ -f "$old_chapters" || -f "$old_progress" ]]; then
        local slug="shadow-slave-62"
        grep -q "^${slug}|" "$NOVELS_FILE" 2>/dev/null || \
            echo "${slug}|Shadow Slave|readernovel:${slug}" >> "$NOVELS_FILE"
        [[ -f "$old_chapters" ]] && mv "$old_chapters" "$DATA_DIR/${slug}.chapters"
        [[ -f "$old_progress" ]] && mv "$old_progress" "$DATA_DIR/${slug}.progress"
        [[ ! -f "$ACTIVE_FILE" ]] && set_active_novel "$slug"
    fi

    # 2) novels file: upgrade old "slug|name" lines to "id|name|readernovel:slug"
    if [[ -f "$NOVELS_FILE" ]] && grep -qvE '^[^|]+\|[^|]+\|[^|]+' "$NOVELS_FILE" 2>/dev/null; then
        local tmp; tmp=$(mktemp)
        awk -F'|' 'BEGIN{OFS="|"}
            NF>=3 { print; next }
            NF==2 { print $1,$2,"readernovel:"$1; next }
            { print }' "$NOVELS_FILE" > "$tmp"
        mv "$tmp" "$NOVELS_FILE"
        echo "Upgraded library to multi-source format."
    fi

    # 3) Per-novel data: old "{id}.chapters" (locator|title, ReaderNovel)
    #    -> "{id}.readernovel.chapters" (number|locator|title),
    #    and progress slug -> chapter number.
    [[ ! -f "$NOVELS_FILE" ]] && return
    while IFS='|' read -r id name sources; do
        local old_cache="$DATA_DIR/${id}.chapters"
        local new_cache="$DATA_DIR/${id}.readernovel.chapters"
        if [[ -f "$old_cache" && ! -f "$new_cache" ]]; then
            awk -F'|' 'BEGIN{OFS="|"}
                { n=$1; sub(/.*-chapter-/,"",n); sub(/[^0-9].*/,"",n);
                  if (n=="") next; print n,$1,$2 }' "$old_cache" \
                | sort -t'|' -k1,1n | awk -F'|' '!seen[$1]++' > "$new_cache"
            mv "$old_cache" "${old_cache}.bak"
        fi
        # progress slug -> number
        local pf="$DATA_DIR/${id}.progress"
        if [[ -f "$pf" ]]; then
            local cur; cur=$(cat "$pf")
            if [[ "$cur" == *-chapter-* ]]; then
                local num; num=$(echo "$cur" | sed -E 's/.*-chapter-([0-9]+).*/\1/')
                [[ -n "$num" ]] && echo "$num" > "$pf"
            fi
        fi
    done < "$NOVELS_FILE"
}

# =====================================================================
#  Main
# =====================================================================

print_status() {
    local id="$1"
    parse_source "$(get_active_source "$id")"
    local total cur
    total=$(chapter_count "$id" "$SITE")
    cur=$(load_progress "$id")
    echo ""
    echo "Active novel: $(novel_name "$id")  [$(site_label "$SITE")]"
    echo "Total chapters available: ${total:-?}"
    if [[ -n "$cur" ]]; then
        echo "Last read: Chapter ${cur}"
    else
        echo "No reading progress saved."
    fi
    echo ""
}

main() {
    migrate_old_data

    local id; id=$(get_active_novel)
    if [[ -z "$id" ]]; then
        echo ""
        echo "=== Novel Reader ==="
        echo "No novel selected. Let's add one!"
        add_novel
        id=$(get_active_novel)
        [[ -z "$id" ]] && { echo "No novel selected. Exiting."; exit 0; }
    fi

    parse_source "$(get_active_source "$id")"
    fetch_index "$id" "$SITE" "$SLUG" || { echo "Failed to fetch chapter list."; exit 1; }

    local current; current=$(load_progress "$id")

    echo ""
    echo "=== Novel Reader ==="
    print_status "$id"

    while true; do
        echo "Commands:"
        echo "  [n]ext     - Read next chapter"
        echo "  [p]rev     - Read previous chapter"
        echo "  [c]urrent  - Re-read current chapter"
        echo "  [g]oto     - Jump to a specific chapter number"
        echo "  [l]ist     - List chapters around current position"
        echo "  [o] source - Switch site / add a backup source"
        echo "  [s]witch   - Switch to another saved novel"
        echo "  [a]dd      - Add a new novel"
        echo "  [q]uit     - Exit"
        echo ""
        read -rp "> " cmd

        parse_source "$(get_active_source "$id")"  # refresh active site/slug

        case "$cmd" in
            n|next)
                if [[ -z "$current" ]]; then
                    current=$(min_number "$id" "$SITE")
                    [[ -z "$current" ]] && current=1
                else
                    local maxn; maxn=$(max_number "$id" "$SITE")
                    if [[ -n "$maxn" && "$current" -ge "$maxn" ]]; then
                        echo "No next chapter available."; continue
                    fi
                    current=$((current + 1))
                fi
                read_chapter "$id" "$current" | page
                ;;
            p|prev)
                [[ -z "$current" ]] && { echo "No current chapter. Use 'goto' first."; continue; }
                if [[ "$current" -le 1 ]]; then echo "No previous chapter."; continue; fi
                current=$((current - 1))
                read_chapter "$id" "$current" | page
                ;;
            c|current)
                [[ -z "$current" ]] && { echo "No current chapter. Use 'goto' first."; continue; }
                read_chapter "$id" "$current" | page
                ;;
            g|goto)
                read -rp "Enter chapter number: " num
                [[ ! "$num" =~ ^[0-9]+$ ]] && { echo "Invalid number."; continue; }
                current="$num"
                read_chapter "$id" "$current" | page
                ;;
            l|list)
                local cache; cache=$(source_cache "$id" "$SITE")
                [[ ! -f "$cache" ]] && { echo "No chapter list."; continue; }
                local cur_line=0
                [[ -n "$current" ]] && cur_line=$(grep -nP "^${current}\|" "$cache" | head -1 | cut -d: -f1)
                [[ -z "$cur_line" ]] && cur_line=0
                local start=$((cur_line - 5)); [[ "$start" -lt 1 ]] && start=1
                local end=$((cur_line + 5))
                echo ""
                sed -n "${start},${end}p" "$cache" | while IFS='|' read -r n loc title; do
                    if [[ "$n" == "$current" ]]; then echo "  >> $title  <<<"; else echo "     $title"; fi
                done
                echo ""
                ;;
            o|source)
                if manage_sources "$id"; then
                    parse_source "$(get_active_source "$id")"
                    print_status "$id"
                fi
                ;;
            s|switch)
                if switch_novel; then
                    id=$(get_active_novel)
                    parse_source "$(get_active_source "$id")"
                    fetch_index "$id" "$SITE" "$SLUG"
                    current=$(load_progress "$id")
                    print_status "$id"
                fi
                ;;
            a|add)
                add_novel
                local new_id; new_id=$(get_active_novel)
                if [[ "$new_id" != "$id" ]]; then
                    id="$new_id"
                    parse_source "$(get_active_source "$id")"
                    fetch_index "$id" "$SITE" "$SLUG"
                    current=$(load_progress "$id")
                    print_status "$id"
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
