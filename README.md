# Shadow Slave Reader

A terminal-based reader for the Shadow Slave web novel.

## Requirements

- **Bash** (4.0+)
- **curl** — for fetching chapters
- **less** — for paging through chapter text
- **GNU coreutils** — `sed`, `grep`, `paste`, `tac`, `fold`, `cut`, `wc`, `head`, `find`
- **ncurses** — for `tput` (terminal width detection)

### Install on Debian/Ubuntu

```bash
sudo apt install curl less coreutils ncurses-bin
```

### Install on Arch

```bash
sudo pacman -S curl less coreutils ncurses
```

### Install on macOS

```bash
brew install coreutils
```

> Most dependencies come pre-installed on Linux. macOS users need GNU coreutils since the script uses GNU-specific options (e.g. `grep -P`).

## Usage

```bash
chmod +x reader.sh
./reader.sh
```

### Commands

| Key | Action |
|-----|--------|
| `n` | Read next chapter |
| `p` | Read previous chapter |
| `c` | Re-read current chapter |
| `g` | Jump to a specific chapter number |
| `l` | List chapters around current position |
| `q` | Quit |

Your reading progress is saved automatically between sessions.
