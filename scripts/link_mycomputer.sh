#!/usr/bin/env bash
# scripts/link_mycomputer.sh - Verify and establish linkage with myComputer repository
set -e

MYCOMPUTER_DIR="$HOME/Documents/GitHub/myComputer"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==> Checking linkage with myComputer repository...${NC}"

if [ -d "$MYCOMPUTER_DIR" ]; then
    echo -e "${GREEN}✓ Found myComputer at: $MYCOMPUTER_DIR${NC}"
    
    # Check for git_gui.py
    if [ -f "$MYCOMPUTER_DIR/git_gui.py" ]; then
        echo -e "${GREEN}✓ Found git_gui.py in myComputer.${NC}"
    else
        echo -e "${YELLOW}! git_gui.py not found in myComputer.${NC}"
    fi

    # Check for suspend_until
    if [ -f "$MYCOMPUTER_DIR/suspend_until" ]; then
        echo -e "${GREEN}✓ Found suspend_until in myComputer.${NC}"
        # Ensure ~/bin has suspend_until
        mkdir -p "$HOME/bin"
        if [ ! -f "$HOME/bin/suspend_until" ]; then
            echo "Symlinking suspend_until into ~/bin..."
            ln -sf "$MYCOMPUTER_DIR/suspend_until" "$HOME/bin/suspend_until"
            chmod +x "$HOME/bin/suspend_until"
        fi
    fi
else
    echo -e "${YELLOW}Warning: myComputer directory not found at $MYCOMPUTER_DIR.${NC}"
fi
