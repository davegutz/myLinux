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
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/bin"

# 3. Re-stow configurations
echo -e "${GREEN}==> Re-stowing dotfiles into $HOME...${NC}"
stow -v -R -t "$HOME" common
chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
chmod +x "$HOME/bin/"*.sh "$HOME/bin/"*.py 2>/dev/null || true

# 4. Optional full system package update
if [[ "$*" == *"--update"* ]]; then
    echo -e "${GREEN}==> Running full system update...${NC}"
    "$DOTFILES_DIR/common/.local/bin/sys-update"
fi

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   Configurations synchronized successfully!  ${NC}"
echo -e "${GREEN}   Run 'source ~/.bashrc' or restart terminal ${NC}"
echo -e "${GREEN}==============================================${NC}"
