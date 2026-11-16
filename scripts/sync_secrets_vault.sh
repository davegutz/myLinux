#!/usr/bin/env bash
# scripts/sync_secrets_vault.sh - Manage Cryptomator SecretsVault in myLinux for rclone.conf & secrets
# Safely stores encrypted secrets in Git/GitHub while keeping zero plaintext secrets in the repository.
set -e

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
DOTFILES_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

VAULT_STORAGE="${SECRETS_VAULT_STORAGE:-$DOTFILES_DIR/SecretsVault}"
VAULT_MOUNT="${SECRETS_VAULT_MOUNT:-$HOME/.local/share/Cryptomator/mnt/SecretsVault}"
UNLOCK_TIMEOUT="${SECRETS_UNLOCK_TIMEOUT:-120}"

RCLONE_CONF_LOCAL="$HOME/.config/rclone/rclone.conf"
MSMTPRC_LOCAL="$HOME/.msmtprc"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

notify() {
    local urgency="${1:-normal}"
    local title="$2"
    local body="$3"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" "$title" "$body" 2>/dev/null || true
    fi
}

is_cryptomator_installed() {
    if [ -x /usr/bin/cryptomator ] || [ -x /usr/local/bin/cryptomator ]; then
        return 0
    elif command -v flatpak >/dev/null 2>&1 && flatpak info org.cryptomator.Cryptomator >/dev/null 2>&1; then
        return 0
    elif command -v cryptomator >/dev/null 2>&1 && cryptomator --version >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

ensure_cryptomator_installed() {
    if is_cryptomator_installed; then
        return 0
    fi

    echo -e "${YELLOW}==> Cryptomator not found. Installing Cryptomator package...${NC}"
    if [ -f /etc/arch-release ]; then
        sudo pacman -S --needed --noconfirm cryptomator || true
    elif [ -f /etc/debian_version ]; then
        if command -v add-apt-repository >/dev/null 2>&1; then
            sudo add-apt-repository -y ppa:sebastian-stenzel/cryptomator 2>/dev/null || true
            sudo apt-get update 2>/dev/null || true
            sudo apt-get install -y cryptomator 2>/dev/null || true
        fi
        if ! is_cryptomator_installed && command -v flatpak >/dev/null 2>&1; then
            flatpak install -y flathub org.cryptomator.Cryptomator 2>/dev/null || true
        fi
    elif command -v flatpak >/dev/null 2>&1; then
        flatpak install -y flathub org.cryptomator.Cryptomator 2>/dev/null || true
    fi

    if is_cryptomator_installed; then
        echo -e "${GREEN}==> Cryptomator installed successfully.${NC}"
        return 0
    else
        echo -e "${RED}==> Warning: Could not automatically install Cryptomator.${NC}"
        return 1
    fi
}

is_cryptomator_running() {
    pgrep -x cryptomator >/dev/null 2>&1 || \
    pgrep -f "^/usr/bin/cryptomator|^/opt/cryptomator|org\.cryptomator\.Cryptomator" >/dev/null 2>&1
}

launch_cryptomator() {
    local vault_arg=""
    if [ -f "$VAULT_STORAGE/vault.cryptomator" ]; then
        vault_arg="$VAULT_STORAGE/vault.cryptomator"
    fi

    if ! is_cryptomator_running; then
        if command -v cryptomator >/dev/null 2>&1; then
            if [ -n "$vault_arg" ]; then
                env -u LD_PRELOAD cryptomator "$vault_arg" >/dev/null 2>&1 &
            else
                env -u LD_PRELOAD cryptomator >/dev/null 2>&1 &
            fi
        elif command -v flatpak >/dev/null 2>&1 && flatpak info org.cryptomator.Cryptomator >/dev/null 2>&1; then
            if [ -n "$vault_arg" ]; then
                env -u LD_PRELOAD flatpak run org.cryptomator.Cryptomator "$vault_arg" >/dev/null 2>&1 &
            else
                env -u LD_PRELOAD flatpak run org.cryptomator.Cryptomator >/dev/null 2>&1 &
            fi
        fi
    fi
}

cleanup_stale_mount() {
    if grep -q "$VAULT_MOUNT" /proc/mounts 2>/dev/null || [ -e "$VAULT_MOUNT" ] || [ -d "$VAULT_MOUNT" ]; then
        if ! stat -t "$VAULT_MOUNT" >/dev/null 2>&1; then
            echo -e "${YELLOW}[WARNING] Detected stale Cryptomator mount at $VAULT_MOUNT. Cleaning up...${NC}"
            fusermount -u -z "$VAULT_MOUNT" 2>/dev/null || fusermount3 -u -z "$VAULT_MOUNT" 2>/dev/null || true
            rmdir "$VAULT_MOUNT" 2>/dev/null || true
        elif [ -d "$VAULT_MOUNT" ] && ! is_cryptomator_running; then
            if ! mountpoint -q "$VAULT_MOUNT" 2>/dev/null; then
                rmdir "$VAULT_MOUNT" 2>/dev/null || true
            fi
        fi
    fi
}

detect_secrets_mount() {
    cleanup_stale_mount

    # 1. Direct mountpoint check on default path
    if mountpoint -q "$VAULT_MOUNT" 2>/dev/null; then
        echo "$VAULT_MOUNT"
        return 0
    fi
    if [ -d "$VAULT_MOUNT/rclone" ] || [ -f "$VAULT_MOUNT/rclone/rclone.conf" ] || [ -f "$VAULT_MOUNT/rclone.conf" ]; then
        echo "$VAULT_MOUNT"
        return 0
    fi

    # 2. Check /proc/mounts for active FUSE mount matching SecretsVault
    local proc_mnt
    proc_mnt="$(awk '$2 ~ /Cryptomator\/mnt\/SecretsVault/ {print $2; exit}' /proc/mounts 2>/dev/null || true)"
    if [ -n "$proc_mnt" ] && [ -d "$proc_mnt" ]; then
        echo "$proc_mnt"
        return 0
    fi

    # 3. Scan ~/.local/share/Cryptomator/mnt/* for any unlocked vault containing rclone/rclone.conf or named SecretsVault
    local mnt_base="$HOME/.local/share/Cryptomator/mnt"
    if [ -d "$mnt_base" ]; then
        for d in "$mnt_base"/*; do
            [ -d "$d" ] || continue
            if [ "$(basename "$d")" = "SecretsVault" ] && (mountpoint -q "$d" 2>/dev/null || [ -n "$(ls -A "$d" 2>/dev/null)" ]); then
                echo "$d"
                return 0
            fi
            if [ -f "$d/rclone/rclone.conf" ] || [ -f "$d/rclone.conf" ]; then
                echo "$d"
                return 0
            fi
        done
    fi

    return 1
}

wait_for_unlock() {
    local timeout="${1:-$UNLOCK_TIMEOUT}"
    local active_mnt=""

    if active_mnt="$(detect_secrets_mount)"; then
        VAULT_MOUNT="$active_mnt"
        return 0
    fi

    if ! ensure_cryptomator_installed; then
        echo -e "${YELLOW}==> Skipping SecretsVault unlock (Cryptomator unavailable).${NC}"
        return 1
    fi

    mkdir -p "$HOME/.local/share/Cryptomator/mnt"
    echo -e "${CYAN}==> Opening Cryptomator to unlock SecretsVault ($VAULT_STORAGE)...${NC}"
    echo -e "    Please unlock ${BOLD}SecretsVault${NC} in Cryptomator (waiting up to ${BOLD}${timeout}s${NC} before moving on)..."
    notify "normal" "Unlock Cryptomator SecretsVault" "Please unlock SecretsVault within ${timeout}s to sync rclone.conf."

    launch_cryptomator

    local elapsed=0
    local cryptomator_started=false
    while [ "$elapsed" -lt "$timeout" ]; do
        if active_mnt="$(detect_secrets_mount)"; then
            VAULT_MOUNT="$active_mnt"
            echo -e "${GREEN}==> SecretsVault unlocked at: $VAULT_MOUNT${NC}"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
        if is_cryptomator_running; then
            cryptomator_started=true
        fi
        if [ $((elapsed % 15)) -eq 0 ] && [ "$elapsed" -lt "$timeout" ]; then
            echo -e "${YELLOW}    Still waiting for SecretsVault unlock (${elapsed}s/${timeout}s)...${NC}"
        fi
        if [ "$cryptomator_started" = true ] && ! is_cryptomator_running; then
            echo -e "${YELLOW}==> Cryptomator was closed before SecretsVault was unlocked. Moving on...${NC}"
            return 1
        fi
    done

    echo -e "${YELLOW}==> Timeout (${timeout}s) reached without unlocking SecretsVault. Moving on without secure folder files.${NC}"
    notify "low" "SecretsVault Timeout" "Moved on without syncing files from SecretsVault."
    return 1
}

sync_files_with_vault() {
    local mnt="$1"
    mkdir -p "$mnt/rclone"
    mkdir -p "$(dirname "$RCLONE_CONF_LOCAL")"

    local vault_rclone="$mnt/rclone/rclone.conf"
    # Support flat fallback if user placed rclone.conf directly in root of vault
    if [ ! -f "$vault_rclone" ] && [ -f "$mnt/rclone.conf" ]; then
        cp -p "$mnt/rclone.conf" "$vault_rclone"
    fi

    # 1. Synchronize rclone/rclone.conf
    if [ -f "$vault_rclone" ] && [ -f "$RCLONE_CONF_LOCAL" ]; then
        if ! cmp -s "$vault_rclone" "$RCLONE_CONF_LOCAL"; then
            if [ "$vault_rclone" -nt "$RCLONE_CONF_LOCAL" ]; then
                cp -p "$vault_rclone" "$RCLONE_CONF_LOCAL"
                chmod 600 "$RCLONE_CONF_LOCAL"
                echo -e "${GREEN}  * Restored newer rclone.conf from SecretsVault -> ~/.config/rclone/rclone.conf${NC}"
            else
                cp -p "$RCLONE_CONF_LOCAL" "$vault_rclone"
                chmod 600 "$RCLONE_CONF_LOCAL"
                echo -e "${GREEN}  * Backed up newer local ~/.config/rclone/rclone.conf -> SecretsVault/rclone/rclone.conf${NC}"
            fi
        else
            chmod 600 "$RCLONE_CONF_LOCAL"
            echo -e "${GREEN}  * rclone.conf is already up to date with SecretsVault.${NC}"
        fi
    elif [ -f "$vault_rclone" ] && [ ! -f "$RCLONE_CONF_LOCAL" ]; then
        cp -p "$vault_rclone" "$RCLONE_CONF_LOCAL"
        chmod 600 "$RCLONE_CONF_LOCAL"
        echo -e "${GREEN}  * Installed rclone.conf from SecretsVault -> ~/.config/rclone/rclone.conf${NC}"
    elif [ ! -f "$vault_rclone" ] && [ -f "$RCLONE_CONF_LOCAL" ]; then
        cp -p "$RCLONE_CONF_LOCAL" "$vault_rclone"
        chmod 600 "$RCLONE_CONF_LOCAL"
        echo -e "${GREEN}  * Saved local ~/.config/rclone/rclone.conf -> SecretsVault/rclone/rclone.conf${NC}"
    else
        echo -e "${YELLOW}  * Note: rclone.conf not found in SecretsVault or ~/.config/rclone/rclone.conf yet.${NC}"
    fi

    # 2. Optional: If Google Drive is not mounted yet and rclone.conf is now available, mount it
    if [ -f "$RCLONE_CONF_LOCAL" ] && [ -x "$HOME/bin/Rclone" ]; then
        if ! mountpoint -q "$HOME/gdrive" 2>/dev/null; then
            echo -e "${BLUE}  * Mounting Google Drive via ~/bin/Rclone...${NC}"
            "$HOME/bin/Rclone" || echo -e "${YELLOW}  * Warning: Google Drive mount did not complete (check 'Rclone' output).${NC}"
        fi
    fi
}

cmd_unlock_and_sync() {
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BLUE}   Synchronizing Secure Files (SecretsVault)        ${NC}"
    echo -e "${BLUE}====================================================${NC}"

    if [ ! -f "$VAULT_STORAGE/vault.cryptomator" ]; then
        echo -e "${YELLOW}==> SecretsVault is not initialized in $VAULT_STORAGE yet.${NC}"
        echo -e "    To create it and store rclone/rclone.conf for Git/GitHub:"
        echo -e "    Run: ${CYAN}myLinux secrets setup${NC}"
        return 0
    fi

    if wait_for_unlock "$UNLOCK_TIMEOUT"; then
        sync_files_with_vault "$VAULT_MOUNT"
        cmd_lock
    fi
    return 0
}

cmd_push() {
    ensure_cryptomator_installed
    if [ ! -f "$VAULT_STORAGE/vault.cryptomator" ]; then
        echo -e "${RED}Error: SecretsVault not found at $VAULT_STORAGE.${NC}"
        echo -e "Run '${CYAN}myLinux secrets setup${NC}' first to create the vault in Cryptomator."
        exit 1
    fi

    if wait_for_unlock "$UNLOCK_TIMEOUT"; then
        mkdir -p "$VAULT_MOUNT/rclone"
        if [ -f "$RCLONE_CONF_LOCAL" ]; then
            cp -p "$RCLONE_CONF_LOCAL" "$VAULT_MOUNT/rclone/rclone.conf"
            echo -e "${GREEN}==> Copied ~/.config/rclone/rclone.conf -> $VAULT_MOUNT/rclone/rclone.conf${NC}"
            cmd_lock
            echo -e "    You can now commit and push the encrypted vault to GitHub:"
            echo -e "    ${CYAN}git -C $DOTFILES_DIR add SecretsVault && git -C $DOTFILES_DIR commit -m 'Update SecretsVault' && git -C $DOTFILES_DIR push${NC}"
        else
            cmd_lock
            echo -e "${RED}Error: Local file $RCLONE_CONF_LOCAL does not exist.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Error: SecretsVault was not unlocked within ${UNLOCK_TIMEOUT}s.${NC}"
        exit 1
    fi
}

cmd_pull() {
    ensure_cryptomator_installed
    if [ ! -f "$VAULT_STORAGE/vault.cryptomator" ]; then
        echo -e "${RED}Error: SecretsVault not found at $VAULT_STORAGE.${NC}"
        exit 1
    fi

    if wait_for_unlock "$UNLOCK_TIMEOUT"; then
        local vault_rclone="$VAULT_MOUNT/rclone/rclone.conf"
        [ ! -f "$vault_rclone" ] && [ -f "$VAULT_MOUNT/rclone.conf" ] && vault_rclone="$VAULT_MOUNT/rclone.conf"
        if [ -f "$vault_rclone" ]; then
            mkdir -p "$(dirname "$RCLONE_CONF_LOCAL")"
            cp -p "$vault_rclone" "$RCLONE_CONF_LOCAL"
            chmod 600 "$RCLONE_CONF_LOCAL"
            echo -e "${GREEN}==> Restored $vault_rclone -> $RCLONE_CONF_LOCAL (chmod 600)${NC}"
            cmd_lock
            if [ -x "$HOME/bin/Rclone" ]; then
                "$HOME/bin/Rclone" || true
            fi
        else
            cmd_lock
            echo -e "${YELLOW}Warning: rclone/rclone.conf not found inside unlocked SecretsVault.${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}==> SecretsVault unlock timed out after ${UNLOCK_TIMEOUT}s. Moving on.${NC}"
    fi
}

cmd_lock() {
    local active_mnt=""
    if active_mnt="$(detect_secrets_mount)"; then
        echo -e "${BLUE}==> Auto-locking SecretsVault at $active_mnt...${NC}"
        sync -f "$active_mnt" 2>/dev/null || sync
        fusermount -u -z "$active_mnt" 2>/dev/null || fusermount3 -u -z "$active_mnt" 2>/dev/null || true
        rmdir "$active_mnt" 2>/dev/null || true
        # Also close Cryptomator if FinanceVault is not actively mounted
        local fin_mnt="$HOME/.local/share/Cryptomator/mnt/FinanceVault"
        if ! mountpoint -q "$fin_mnt" 2>/dev/null; then
            flatpak kill org.cryptomator.Cryptomator 2>/dev/null || pkill -TERM -x cryptomator 2>/dev/null || true
        fi
        echo -e "${GREEN}==> SecretsVault flushed, unmounted, and locked.${NC}"
    else
        echo -e "${GREEN}==> SecretsVault is already locked.${NC}"
    fi
}

cmd_status() {
    echo -e "${BLUE}=== Cryptomator SecretsVault Status ===${NC}"
    echo -e "  Encrypted Vault Dir : $VAULT_STORAGE"
    if [ -f "$VAULT_STORAGE/vault.cryptomator" ]; then
        echo -e "  Vault Initialized   : ${GREEN}YES${NC} (Tracked in Git for GitHub sync)"
    else
        echo -e "  Vault Initialized   : ${YELLOW}NO${NC} (Run 'myLinux secrets setup' to initialize)"
    fi

    local active_mnt=""
    if active_mnt="$(detect_secrets_mount)"; then
        echo -e "  Mount Status        : ${GREEN}UNLOCKED${NC} ($active_mnt)"
        if [ -f "$active_mnt/rclone/rclone.conf" ] || [ -f "$active_mnt/rclone.conf" ]; then
            echo -e "  Vault rclone.conf   : ${GREEN}PRESENT${NC}"
        else
            echo -e "  Vault rclone.conf   : ${YELLOW}MISSING${NC}"
        fi
    else
        echo -e "  Mount Status        : ${YELLOW}LOCKED${NC}"
    fi

    if [ -f "$RCLONE_CONF_LOCAL" ]; then
        echo -e "  Local rclone.conf   : ${GREEN}PRESENT${NC} ($RCLONE_CONF_LOCAL)"
    else
        echo -e "  Local rclone.conf   : ${RED}MISSING${NC} ($RCLONE_CONF_LOCAL)"
    fi
}

cmd_setup() {
    ensure_cryptomator_installed
    mkdir -p "$HOME/.local/share/Cryptomator/mnt"

    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${BLUE}   Cryptomator SecretsVault Setup (Git-Safe rclone.conf Storage)   ${NC}"
    echo -e "${BLUE}===================================================================${NC}"

    if [ -f "$VAULT_STORAGE/vault.cryptomator" ]; then
        echo -e "${GREEN}==> Existing SecretsVault detected at: $VAULT_STORAGE${NC}"
        echo -e "    In Cryptomator:"
        echo -e "      1. Click '${BOLD}+ Add Vault${NC}' -> '${BOLD}Open Existing Vault${NC}'"
        echo -e "      2. Select: ${CYAN}$VAULT_STORAGE/vault.cryptomator${NC}"
        echo -e "      3. In Vault Options -> Mounting, set Custom Mount Point (if needed) or default:"
        echo -e "         ${CYAN}$VAULT_MOUNT${NC}"
        echo -e "      4. Unlock the vault within ${UNLOCK_TIMEOUT}s to sync rclone/rclone.conf automatically!"
    else
        echo -e "${YELLOW}==> Initializing new SecretsVault in repository...${NC}"
        # Remove empty placeholder directory if present so Cryptomator can create SecretsVault cleanly
        if [ -d "$VAULT_STORAGE" ] && [ ! -f "$VAULT_STORAGE/vault.cryptomator" ]; then
            rm -f "$VAULT_STORAGE/.gitkeep" 2>/dev/null || true
            rmdir "$VAULT_STORAGE" 2>/dev/null || true
        fi
        echo -e "    In Cryptomator (launching now):"
        echo -e "      1. Click '${BOLD}+ Add Vault${NC}' -> '${BOLD}Create New Vault${NC}'"
        echo -e "      2. Vault Name: ${BOLD}SecretsVault${NC}"
        echo -e "      3. Custom Location: choose ${CYAN}$DOTFILES_DIR${NC}"
        echo -e "         (This creates ${CYAN}$VAULT_STORAGE${NC})"
        echo -e "      4. Choose a strong passphrase and unlock the vault."
        echo -e "      5. Once unlocked within ${UNLOCK_TIMEOUT}s, this script will automatically copy"
        echo -e "         ${CYAN}~/.config/rclone/rclone.conf${NC} into ${CYAN}SecretsVault/rclone/rclone.conf${NC}!"
    fi

    echo ""
    if wait_for_unlock "$UNLOCK_TIMEOUT"; then
        sync_files_with_vault "$VAULT_MOUNT"
        cmd_lock
        echo ""
        echo -e "${GREEN}==> SecretsVault is set up, synchronized, and locked!${NC}"
        echo -e "    To commit the encrypted vault to Git & GitHub, run:"
        echo -e "    ${CYAN}git -C $DOTFILES_DIR add SecretsVault && git -C $DOTFILES_DIR commit -m 'Add encrypted SecretsVault' && git -C $DOTFILES_DIR push${NC}"
    fi
}

case "${1:-sync}" in
    sync|unlock)
        cmd_unlock_and_sync
        ;;
    push|save)
        cmd_push
        ;;
    pull|restore)
        cmd_pull
        ;;
    lock)
        cmd_lock
        ;;
    status)
        cmd_status
        ;;
    setup|init)
        cmd_setup
        ;;
    -h|--help|help)
        echo "Usage: $(basename "$0") [sync|setup|push|pull|lock|status]"
        echo ""
        echo "Commands:"
        echo "  sync     Unlock SecretsVault (120s timeout) and sync rclone/rclone.conf (default)"
        echo "  setup    Initialize or add SecretsVault in Cryptomator and populate rclone/rclone.conf"
        echo "  push     Copy local ~/.config/rclone/rclone.conf into SecretsVault/rclone/rclone.conf"
        echo "  pull     Restore SecretsVault/rclone/rclone.conf to ~/.config/rclone/rclone.conf"
        echo "  lock     Unmount and lock SecretsVault"
        echo "  status   Show SecretsVault and local rclone.conf status"
        ;;
    *)
        echo "Unknown action: $1"
        exit 1
        ;;
esac
