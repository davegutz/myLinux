#!/usr/bin/env bash
# scripts/bootstrap.sh - Master bootstrap manager for myLinux
# Exit immediately if a command exits with a non-zero status
set -e

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
DOTFILES_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Starting myLinux System Synchronization Bootstrap ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. Detect Distribution & Install Core Tools
echo -e "\n${GREEN}[Step 1/6] Detecting distribution and installing core tools...${NC}"

if [ -f /etc/arch-release ]; then
    echo "Detected Arch-based system (CachyOS)."
    PACKAGES="git stow alacritty tmux zoxide curl base-devel msmtp rclone fuse3 libfido2 cryptomator"
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
    PACKAGES="git stow alacritty tmux zoxide curl build-essential msmtp msmtp-mta rclone fuse3 libfido2-1"
    MISSING_PKGS=""
    for pkg in $PACKAGES; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            MISSING_PKGS="$MISSING_PKGS $pkg"
        fi
    done

    if [ -n "$MISSING_PKGS" ]; then
        echo "Installing missing packages:$MISSING_PKGS"
        if [ -f "/home/${USER}.home" ]; then
            sudo fstrim "$HOME" 2>/dev/null || true
        fi
        sudo apt-get clean || true
        sudo apt update && sudo apt install -y $MISSING_PKGS
        sudo apt-get clean || true
    else
        echo "Core packages already installed."
    fi

    # Ensure Cryptomator is installed on Debian/Ubuntu for financial vault decryption
    if ! command -v cryptomator >/dev/null 2>&1 && ! dpkg -s cryptomator >/dev/null 2>&1; then
        echo "Configuring and installing Cryptomator..."
        if command -v add-apt-repository >/dev/null 2>&1; then
            sudo add-apt-repository -y ppa:sebastian-stenzel/cryptomator 2>/dev/null || true
            sudo apt-get update 2>/dev/null || true
            sudo apt-get install -y cryptomator 2>/dev/null || true
        elif command -v flatpak >/dev/null 2>&1; then
            flatpak install -y flathub org.cryptomator.Cryptomator 2>/dev/null || true
        fi
    fi

    # Ensure Snap Firefox has u2f-devices access for YubiKey / FIDO2 WebAuthn
    if command -v snap >/dev/null 2>&1 && snap list firefox >/dev/null 2>&1; then
        sudo snap connect firefox:u2f-devices 2>/dev/null || true
    fi
else
    echo -e "${YELLOW}Notice: Unsupported or unrecognized distribution. Skipping package installation.${NC}"
fi

# 2. Back up conflicting existing files before stowing
echo -e "\n${GREEN}[Step 2/6] Checking and backing up existing conflicting dotfiles...${NC}"
"$DOTFILES_DIR/scripts/backup.sh"

# 3. Ensure target directories exist before Stow executes
echo -e "\n${GREEN}[Step 3/6] Pre-creating local target directory structure...${NC}"
mkdir -p "$HOME/.config/alacritty"
mkdir -p "$HOME/.config/fastfetch"
mkdir -p "$HOME/.config/gtk-3.0"
mkdir -p "$HOME/.config/gtk-4.0"
mkdir -p "$HOME/.config/pipewire/pipewire-pulse.conf.d"
mkdir -p "$HOME/.config/autostart"
mkdir -p "$HOME/.config/systemd/user"
mkdir -p "$HOME/.config/rclone"
mkdir -p "$HOME/.local/state/rclone"
mkdir -p "$HOME/.local/state/security-scan"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/bin"
mkdir -p "$HOME/Desktop"
mkdir -p "$HOME/.config/gnucash"
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/fonts"
mkdir -p "$HOME/.local/share/gnucash/books"
mkdir -p "$HOME/.local/share/Cryptomator/mnt"

# Deploy configurations via GNU Stow
echo "Symlinking common configurations via GNU Stow..."
cd "$DOTFILES_DIR"
stow -v -R -t "$HOME" common

# Detect and deploy environment-specific autostart files
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
    echo -e "Detected desktop environment: ${YELLOW}$DE_SESSION${NC} -> Stowing $AUTOSTART_PKG..."
    stow -v -R -t "$HOME" "$AUTOSTART_PKG"
else
    echo -e "${YELLOW}Notice: Desktop environment '$DE_SESSION' did not match a specific autostart package.${NC}"
    echo -e "You can manually stow your target environment: ${YELLOW}stow -v -R -t \"\$HOME\" autostart-[cosmic|gnome|plasma]${NC}"
fi

# Deploy daily rclone copy daemon package
echo "Symlinking rclone daily copy daemon via GNU Stow..."
stow -v -R -t "$HOME" rclone-backup

# Ensure scripts in ~/.local/bin and ~/bin are executable
chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
chmod +x "$HOME/bin/"*.sh "$HOME/bin/"*.py "$HOME/bin/Rclone" 2>/dev/null || true
chmod +x "$HOME/Desktop/"*.desktop "$HOME/.local/share/applications/"*.desktop 2>/dev/null || true

# Secure msmtp mailer permissions (msmtp requires 0600 on config file)
if [ -f "$HOME/.msmtprc" ]; then
    chmod 600 "$HOME/.msmtprc" 2>/dev/null || true
elif [ -f "$DOTFILES_DIR/common/.msmtprc.example" ]; then
    cp "$DOTFILES_DIR/common/.msmtprc.example" "$HOME/.msmtprc"
    chmod 600 "$HOME/.msmtprc" 2>/dev/null || true
fi

# Refresh desktop database for application menus
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# Enable and start the systemd user timer for daily rclone copy
if command -v systemctl >/dev/null 2>&1; then
    echo "Registering and enabling rclone daily copy timer..."
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now rclone-daily-backup.timer 2>/dev/null || true
fi

# 4. Install and configure fonts
echo -e "\n${GREEN}[Step 4/6] Installing and verifying fonts...${NC}"
"$DOTFILES_DIR/scripts/install_fonts.sh"

# 5. Align desktop appearance and dark mode
echo -e "\n${GREEN}[Step 5/6] Aligning desktop appearance and theme...${NC}"
"$DOTFILES_DIR/scripts/setup_appearance.sh"

# 6. Unlock Cryptomator SecretsVault (120s timeout) to restore rclone/rclone.conf
echo -e "\n${GREEN}[Step 6/6] Synchronizing secure files (rclone/rclone.conf) via Cryptomator SecretsVault...${NC}"
"$DOTFILES_DIR/scripts/sync_secrets_vault.sh" sync || true

# Optional: Security camera NVR installation (if requested via argument)
if [[ "$*" == *"--with-secure-cam"* ]] || [[ "$*" == *"--camera"* ]]; then
    echo -e "\n${GREEN}[Optional] Installing security camera NVR (motion + motionEye)...${NC}"
    "$DOTFILES_DIR/scripts/install_secure_cam.sh"
fi

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}   System configurations aligned successfully!       ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Next steps:"
echo -e "  1. Reload your current shell session:"
echo -e "     ${YELLOW}reload${NC} (or ${YELLOW}source ~/.bashrc${NC})"
echo -e "  2. Launch Alacritty to test the unified terminal:"
echo -e "     ${YELLOW}alacritty &${NC}"
echo -e "  3. To synchronize updates in the future, run:"
echo -e "     ${YELLOW}myLinux sync${NC} (or ${YELLOW}myLinux -h${NC} for help)"
echo -e "  4. To set up the Security Camera NVR (motion + motionEye):"
echo -e "     ${YELLOW}./scripts/install_secure_cam.sh${NC} (or ${YELLOW}myLinux camera${NC})"
echo -e "  5. Set up Cryptomator FinanceVault (GnuCash Joint):"
echo -e "     • Open Cryptomator: ${YELLOW}cryptomator &${NC}"
echo -e "     • Add existing vault: select ${YELLOW}~/gdrive/FinanceVault${NC}"
echo -e "     • Unlock vault with your passphrase (mounts to ~/.local/share/Cryptomator/mnt/FinanceVault)"
echo -e "     • (Tip) In Cryptomator Vault Options, enable 'Save Password' and 'Unlock automatically when Cryptomator starts'"
echo -e "     • Launch GnuCash (Joint) from desktop launcher or terminal: ${YELLOW}gnucash-refresh${NC}"

# Auto-refresh interactive terminal session so all new aliases and commands work immediately
if [ -t 0 ] && [ -n "${BASH_VERSION:-}" ]; then
    echo -e "\n${GREEN}==> Refreshing terminal session with all new commands active...${NC}"
    exec bash
fi
