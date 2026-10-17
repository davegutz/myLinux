#!/usr/bin/env bash
# scripts/bootstrap.sh - Master bootstrap manager for myLinux
# Exit immediately if a command exits with a non-zero status
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Starting myLinux System Synchronization Bootstrap ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. Detect Distribution & Install Core Tools
echo -e "\n${GREEN}[Step 1/5] Detecting distribution and installing core tools...${NC}"

if [ -f /etc/arch-release ]; then
    echo "Detected Arch-based system (CachyOS)."
    PACKAGES="git stow alacritty tmux zoxide curl base-devel"
    # Check if packages are missing before running pacman
    MISSING_PKGS=""
    for pkg in $PACKAGES; do
        if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
            MISSING_PKGS="$MISSING_PKGS $pkg"
        fi
    done

    if [ -n "$MISSING_PKGS" ]; then
        echo "Installing missing packages:$MISSING_PKGS"
        sudo pacman -Syu --needed --noconfirm $MISSING_PKGS
    else
        echo "Core packages already installed."
    fi

elif [ -f /etc/debian_version ]; then
    echo "Detected Debian/Ubuntu-based system (Lubuntu/Ubuntu)."
    PACKAGES="git stow alacritty tmux zoxide curl build-essential"
    MISSING_PKGS=""
    for pkg in $PACKAGES; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            MISSING_PKGS="$MISSING_PKGS $pkg"
        fi
    done

    if [ -n "$MISSING_PKGS" ]; then
        echo "Installing missing packages:$MISSING_PKGS"
        sudo apt update && sudo apt install -y $MISSING_PKGS
    else
        echo "Core packages already installed."
    fi
else
    echo -e "${YELLOW}Notice: Unsupported or unrecognized distribution. Skipping package installation.${NC}"
fi

# 2. Back up conflicting existing files before stowing
echo -e "\n${GREEN}[Step 2/5] Checking and backing up existing conflicting dotfiles...${NC}"
"$DOTFILES_DIR/scripts/backup.sh"

# 3. Ensure target directories exist before Stow executes
echo -e "\n${GREEN}[Step 3/5] Pre-creating local target directory structure...${NC}"
mkdir -p "$HOME/.config/alacritty"
mkdir -p "$HOME/.config/fastfetch"
mkdir -p "$HOME/.config/gtk-3.0"
mkdir -p "$HOME/.config/gtk-4.0"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/bin"
mkdir -p "$HOME/.local/share/fonts"
mkdir -p "$HOME/.local/share/gnucash/books"

# Deploy common dotfiles via GNU Stow
echo "Symlinking common configurations via GNU Stow..."
cd "$DOTFILES_DIR"
stow -v -R -t "$HOME" common

# Ensure scripts in ~/.local/bin and ~/bin are executable
chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
chmod +x "$HOME/bin/"*.sh "$HOME/bin/"*.py "$HOME/bin/Rclone" 2>/dev/null || true

# 4. Install and configure fonts
echo -e "\n${GREEN}[Step 4/5] Installing and verifying fonts...${NC}"
"$DOTFILES_DIR/scripts/install_fonts.sh"

# 5. Align desktop appearance and dark mode
echo -e "\n${GREEN}[Step 5/5] Aligning desktop appearance and theme...${NC}"
"$DOTFILES_DIR/scripts/setup_appearance.sh"

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}   System configurations aligned successfully!       ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Next steps:"
echo -e "  1. Reload your current shell session:"
echo -e "     ${YELLOW}source ~/.bashrc${NC}"
echo -e "  2. Launch Alacritty to test the unified terminal:"
echo -e "     ${YELLOW}alacritty &${NC}"
echo -e "  3. To synchronize updates in the future, run:"
echo -e "     ${YELLOW}mylinux-sync${NC} or ${YELLOW}dotfiles sync${NC}"
