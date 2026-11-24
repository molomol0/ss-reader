# Novel Reader

A terminal-based reader for web novels. Supports multiple novels with independent progress tracking, and **multiple sites per novel** so you can switch source if one goes down.

## Supported sites

| Site | Add a novel |
|------|-------------|
| [readernovel.net](https://www.readernovel.net) | Browse the built-in catalog, or paste a novel URL |
| [asurascans.com](https://asurascans.com) | Paste a novel URL (e.g. `https://asurascans.com/novels/shadow-slave`) |

Each novel can hold several sources. Because both sites number chapters as "Chapter N", switching source **keeps your place by chapter number** — if Asura is down, switch to ReaderNovel (or vice-versa) and carry on from the same chapter.

## Requirements

- **Bash** 4.0+
- **curl** — fetching chapters and the novel catalog
- **less** — paging through chapter text
- **GNU coreutils** — `sed`, `grep`, `tac`, `fold`, `cut`, `wc`, `head`, `find`, `awk`
- **ncurses** — `tput` for terminal width detection
- **fzf** *(optional)* — real-time fuzzy search when browsing novels

### Install dependencies

**Debian/Ubuntu**
```bash
sudo apt install curl less coreutils ncurses-bin fzf
```

**Arch**
```bash
sudo pacman -S curl less coreutils ncurses fzf
```

**macOS**
```bash
brew install coreutils fzf
```

> macOS users need GNU coreutils — the script uses GNU-specific options (`grep -P`, `tac`).

## Installation

### One-liner

```bash
bash <(curl -s https://raw.githubusercontent.com/molomol0/ss-reader/main/install.sh)
```

This will:
- Clone the repo to `~/.ss-reader`
- Symlink `ss-reader` into `~/.local/bin`

### Uninstall

```bash
rm -rf ~/.ss-reader ~/.local/bin/ss-reader
```

## Usage

```bash
ss-reader
```

Or run directly without installing:

```bash
chmod +x reader.sh
./reader.sh
```

## Commands

| Key | Action |
|-----|--------|
| `n` | Read next chapter |
| `p` | Read previous chapter |
| `c` | Re-read current chapter |
| `g` | Jump to a specific chapter number |
| `l` | List chapters around current position |
| `o` | Switch site / add a backup source for the current novel |
| `s` | Switch to another saved novel |
| `a` | Add a new novel (paste a URL, or browse the ReaderNovel catalog) |
| `q` | Quit |

While reading: scroll with your terminal (mouse wheel / scrollback) as usual, or **Space** to page down and **q** to go back to the menu.

By default chapters are shown without `less`'s alternate screen, so the text stays in your terminal and normal scrolling works. Override the pager with `READER_PAGER`:

```bash
READER_PAGER='less -R --mouse --wheel-lines=3' ss-reader   # scroll inside less
READER_PAGER='cat' ss-reader                               # no pager at all
```

### Adding a backup source

1. Make the novel active (`s` to switch to it).
2. Press `o` → `a`, then paste the novel's URL on another site.
3. Choose whether to switch to it now. You keep your current chapter number.

Later, press `o` any time to flip between sources — handy when one site is down.

## Data & caching

All data is stored in `.reader_data/` next to the script (or install dir):

| File | Description | TTL |
|------|-------------|-----|
| `catalog` | Full ReaderNovel catalog | 24 hours |
| `<id>.<site>.chapters` | Chapter list per novel, per source | 1 hour |
| `<id>.progress` | Reading position (chapter **number**) per novel | permanent |
| `<id>.source` | Active source (`site:slug`) for a novel | permanent |
| `novels` | Your library — `id\|name\|site:slug,site:slug,…` | permanent |

Progress is stored by **chapter number** so it stays valid when you switch a novel's source. Older single-site libraries are migrated automatically on first launch (progress and chapter caches are converted; `.chapters` backed up as `.chapters.bak`).

On first launch you'll be prompted to add a novel.
Progress and library are tracked independently per novel across sessions.
