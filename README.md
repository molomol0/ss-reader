# Novel Reader

A terminal-based reader for web novels from [readernovel.net](https://www.readernovel.net). Supports multiple novels with independent progress tracking.

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
| `s` | Switch to another saved novel |
| `a` | Browse & add a new novel from the catalog |
| `q` | Quit |

While reading (`less`): **Space** to scroll, **q** to go back to the menu.

## Data & caching

All data is stored in `.reader_data/` next to the script (or install dir):

| File | Description | TTL |
|------|-------------|-----|
| `catalog` | Full novel catalog from the site | 24 hours |
| `<slug>.chapters` | Chapter list per novel | 1 hour |
| `<slug>.progress` | Reading position per novel | permanent |
| `novels` | Your saved library | permanent |

On first launch you'll be prompted to browse and pick a novel.
Progress and library are tracked independently per novel across sessions.
