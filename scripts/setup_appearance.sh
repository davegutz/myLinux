#!/usr/bin/env bash
# scripts/setup_appearance.sh - Align desktop appearance, theme, and styling across builds
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}   Aligning Desktop Appearance & Dark Theme   ${NC}"
echo -e "${BLUE}==============================================${NC}"

# 1. GTK / GNOME / COSMIC settings via gsettings (if available)
if command -v gsettings >/dev/null 2>&1; then
    echo -e "${GREEN}==> Setting GTK dark mode preferences via gsettings...${NC}"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
fi

# 2. KDE Plasma Dark Theme (if running Plasma)
if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    echo -e "${GREEN}==> Setting KDE Plasma color scheme to BreezeDark...${NC}"
    plasma-apply-colorscheme BreezeDark 2>/dev/null || true
fi

# 3. LXQt (Lubuntu 4GB instances)
if [ -d "$HOME/.config/lxqt" ]; then
    echo -e "${GREEN}==> Configuring LXQt dark theme options...${NC}"
    mkdir -p "$HOME/.config/lxqt"
    if [ -f "$HOME/.config/lxqt/lxqt.conf" ]; then
        sed -i 's/^theme=.*/theme=Vala-Dark/' "$HOME/.config/lxqt/lxqt.conf" 2>/dev/null || true
    fi
fi

# 4. Set default terminal emulator to Alacritty (if available)
if command -v update-alternatives >/dev/null 2>&1 && [ -x /usr/bin/alacritty ]; then
    if sudo -n true 2>/dev/null; then
        sudo update-alternatives --set x-terminal-emulator /usr/bin/alacritty 2>/dev/null || true
    fi
fi

echo -e "${GREEN}==> Appearance settings aligned successfully!${NC}"
