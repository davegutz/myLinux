#!/usr/bin/env bash
# scripts/install_fonts.sh - Install JetBrains Mono Nerd Font for uniform terminal rendering
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}   Configuring Fonts for Unified Terminal UI  ${NC}"
echo -e "${BLUE}==============================================${NC}"

FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"

# 1. Check if JetBrainsMono Nerd Font is already installed
if fc-list : family | grep -iq "JetBrainsMono Nerd Font"; then
    echo -e "${GREEN}==> JetBrainsMono Nerd Font is already installed and available!${NC}"
    exit 0
fi

echo -e "${YELLOW}==> JetBrainsMono Nerd Font not found. Installing...${NC}"

# If Arch/CachyOS and non-interactive sudo is available, try pacman
installed=false
if [ -f /etc/arch-release ] && sudo -n true 2>/dev/null; then
    echo "Installing via pacman..."
    if sudo pacman -S --needed --noconfirm ttf-jetbrains-mono-nerd; then
        installed=true
    fi
fi

# Fallback or standard user-level installation (works without root/sudo)
if [ "$installed" = false ]; then
    mkdir -p "$FONT_DIR"
    echo "Downloading JetBrains Mono Nerd Font (~7MB)..."
    TEMP_DIR=$(mktemp -d)
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
    
    if command -v curl >/dev/null 2>&1; then
        if curl -fL --progress-bar -o "$TEMP_DIR/JetBrainsMono.tar.xz" "$FONT_URL"; then
            tar -xf "$TEMP_DIR/JetBrainsMono.tar.xz" -C "$FONT_DIR/"
            echo "Extracted fonts to $FONT_DIR"
            installed=true
        fi
    fi
    rm -rf "$TEMP_DIR"
fi

# 2. Rebuild user font cache
echo -e "${GREEN}==> Updating font cache...${NC}"
fc-cache -f "$HOME/.local/share/fonts" 2>/dev/null || true

if fc-list : family | grep -iq "JetBrainsMono Nerd Font"; then
    echo -e "${GREEN}==> JetBrainsMono Nerd Font installed successfully!${NC}"
else
    echo -e "${YELLOW}Notice: Font cache updated. Fallback fonts (Hack/DejaVu) remain active.${NC}"
fi
