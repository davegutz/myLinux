#!/usr/bin/env bash
# scripts/backup.sh - Backup existing configurations before applying Stow
set -e

BACKUP_ROOT="$HOME/.dotfiles_backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/backup_$TIMESTAMP"
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==> Checking for existing dotfiles to back up...${NC}"

# List of managed paths relative to $HOME
MANAGED_FILES=(
    ".bashrc"
    ".bash_aliases"
    ".tmux.conf"
    ".config/alacritty/alacritty.toml"
    ".config/fastfetch/config.jsonc"
    ".config/gtk-3.0/settings.ini"
    ".config/gtk-4.0/settings.ini"
)

backed_up_count=0

for rel_path in "${MANAGED_FILES[@]}"; do
    target="$HOME/$rel_path"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        if [ $backed_up_count -eq 0 ]; then
            mkdir -p "$BACKUP_DIR"
        fi
        dest_dir="$BACKUP_DIR/$(dirname "$rel_path")"
        mkdir -p "$dest_dir"
        cp -a "$target" "$dest_dir/"
        echo -e "${YELLOW}  * Backed up: $target -> $dest_dir/$(basename "$rel_path")${NC}"
        
        # Remove the conflicting regular file so Stow can create a symlink
        rm -rf "$target"
        backed_up_count=$((backed_up_count + 1))
    elif [ -L "$target" ]; then
        # Check if symlink is broken or pointing elsewhere
        link_target=$(readlink -f "$target" || true)
        if [[ "$link_target" != *"$DOTFILES_DIR"* ]]; then
            echo -e "${YELLOW}  * Existing symlink points outside myLinux: $target -> $link_target (replacing)${NC}"
            rm "$target"
        fi
    fi
done

if [ $backed_up_count -gt 0 ]; then
    echo -e "${GREEN}==> $backed_up_count file(s) safely backed up to: $BACKUP_DIR${NC}"
else
    echo -e "${GREEN}==> No conflicting files found. Ready for Stow.${NC}"
fi
