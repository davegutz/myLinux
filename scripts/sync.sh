#!/usr/bin/env bash
# scripts/sync.sh - Synchronize configuration state across Linux machines
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}   Synchronizing myLinux Configurations       ${NC}"
echo -e "${BLUE}==============================================${NC}"

cd "$DOTFILES_DIR"

# 1. Pull latest changes from git
if [ -d .git ]; then
    echo -e "${GREEN}==> Fetching and rebasing from remote repository...${NC}"
    git pull --rebase || echo -e "${YELLOW}Warning: git pull failed or no remote configured yet.${NC}"
fi

# 2. Ensure target directories exist before stowing
mkdir -p "$HOME/.config/alacritty"
mkdir -p "$HOME/.config/fastfetch"
mkdir -p "$HOME/.config/gtk-3.0"
mkdir -p "$HOME/.config/gtk-4.0"
mkdir -p "$HOME/.config/autostart"
mkdir -p "$HOME/.config/systemd/user"
mkdir -p "$HOME/.config/rclone"
mkdir -p "$HOME/.local/state/rclone"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/bin"
mkdir -p "$HOME/Desktop"
mkdir -p "$HOME/.config/gnucash"
mkdir -p "$HOME/.local/share/applications"

# 3. Re-stow configurations
echo -e "${GREEN}==> Re-stowing common configurations into $HOME...${NC}"
stow -v -R -t "$HOME" common

# Detect and re-stow desktop-specific autostart files
DE_SESSION="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}"
DE_LOWER="$(echo "$DE_SESSION" | tr '[:upper:]' '[:lower:]')"
AUTOSTART_PKG=""

if [[ "$DE_LOWER" == *"cosmic"* ]]; then
    AUTOSTART_PKG="autostart-cosmic"
elif [[ "$DE_LOWER" == *"gnome"* ]]; then
    AUTOSTART_PKG="autostart-gnome"
elif [[ "$DE_LOWER" == *"kde"* || "$DE_LOWER" == *"plasma"* ]]; then
    AUTOSTART_PKG="autostart-plasma"
fi

if [ -n "$AUTOSTART_PKG" ] && [ -d "$DOTFILES_DIR/$AUTOSTART_PKG" ]; then
    echo -e "${GREEN}==> Re-stowing $AUTOSTART_PKG for $DE_SESSION...${NC}"
    stow -v -R -t "$HOME" "$AUTOSTART_PKG"
fi

echo -e "${GREEN}==> Re-stowing rclone daily copy daemon into $HOME...${NC}"
stow -v -R -t "$HOME" rclone-backup

chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
chmod +x "$HOME/bin/"*.sh "$HOME/bin/"*.py "$HOME/bin/Rclone" 2>/dev/null || true
chmod +x "$HOME/Desktop/"*.desktop "$HOME/.local/share/applications/"*.desktop 2>/dev/null || true

# Reload systemd user daemon & ensure timer is active
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now rclone-daily-backup.timer 2>/dev/null || true
fi

# 4. Optional full system package update
if [[ "$*" == *"--update"* ]]; then
    echo -e "${GREEN}==> Running full system update...${NC}"
    "$DOTFILES_DIR/common/.local/bin/sys-update"
fi

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   Configurations synchronized successfully!  ${NC}"
echo -e "${GREEN}   Run 'source ~/.bashrc' or restart terminal ${NC}"
echo -e "${GREEN}==============================================${NC}"
