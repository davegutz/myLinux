#!/usr/bin/env bash
# scripts/tune_homed_encryption.sh - Optimize systemd-homed LUKS & mount I/O for eMMC/SSD
# Safely applies (or reverts) noatime and dm-crypt workqueue bypass for /home/daveg
# without touching LUKS keyslots or systemd-homed identity signatures.
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TARGET_USER="${SUDO_USER:-$USER}"
HOME_DIR="/home/$TARGET_USER"
MAPPER_NAME="home-$TARGET_USER"
MAPPER_DEV="/dev/mapper/$MAPPER_NAME"
MOUNT_UNIT="home-${TARGET_USER}.mount"
SERVICE_NAME="homed-io-tune-${TARGET_USER}.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

show_status() {
    echo -e "\n${BLUE}==> Current Mount Options ($HOME_DIR):${NC}"
    findmnt "$HOME_DIR" || true

    echo -e "\n${BLUE}==> Current dm-crypt Flags ($MAPPER_NAME):${NC}"
    if [ -e "$MAPPER_DEV" ]; then
        sudo dmsetup table "$MAPPER_NAME" || true
    else
        echo "  Mapper $MAPPER_DEV not found."
    fi

    echo -e "\n${BLUE}==> Persistent Systemd Service ($SERVICE_NAME):${NC}"
    if [ -f "$SERVICE_PATH" ]; then
        systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true
    else
        echo "  Not installed (default state)."
    fi
}

apply_tuning() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}   Applying eMMC / LUKS Encryption I/O Optimizations ($TARGET_USER)${NC}"
    echo -e "${BLUE}================================================================${NC}"

    if [ ! -e "$MAPPER_DEV" ]; then
        echo -e "${RED}Error: $MAPPER_DEV does not exist. Is $HOME_DIR mounted via systemd-homed?${NC}"
        exit 1
    fi

    echo -e "\n${YELLOW}==> BEFORE Optimization:${NC}"
    show_status

    echo -e "\n${GREEN}[1/3] Remounting $HOME_DIR with noatime (reduces metadata writes)...${NC}"
    sudo mount -o remount,noatime "$HOME_DIR"

    echo -e "\n${GREEN}[2/3] Enabling dm-crypt workqueue bypass (inline AES-NI) & discard...${NC}"
    CRYPTSETUP_BIN=$(command -v cryptsetup || echo "/sbin/cryptsetup")
    MOUNT_BIN=$(command -v mount || echo "/bin/mount")
    sudo "$CRYPTSETUP_BIN" refresh \
        --perf-no_read_workqueue \
        --perf-no_write_workqueue \
        --allow-discards \
        "$MAPPER_NAME"

    echo -e "\n${GREEN}[3/3] Installing fail-safe post-mount unit ($SERVICE_PATH)...${NC}"
    sudo tee "$SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=Optimize dm-crypt and mount flags for $HOME_DIR (eMMC)
After=$MOUNT_UNIT
BindsTo=$MOUNT_UNIT

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=-$MOUNT_BIN -o remount,noatime $HOME_DIR
ExecStart=-$CRYPTSETUP_BIN refresh --perf-no_read_workqueue --perf-no_write_workqueue --allow-discards $MAPPER_NAME

[Install]
WantedBy=$MOUNT_UNIT
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now "$SERVICE_NAME"

    echo -e "\n${YELLOW}==> AFTER Optimization:${NC}"
    show_status

    echo -e "\n${GREEN}================================================================${NC}"
    echo -e "${GREEN}   Optimization active!                                         ${NC}"
    echo -e "${GREEN}   To revert at any time, run:                                  ${NC}"
    echo -e "${YELLOW}   ~/Documents/GitHub/myLinux/scripts/tune_homed_encryption.sh --revert${NC}"
    echo -e "${GREEN}================================================================${NC}"
}

revert_tuning() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}   Reverting eMMC / LUKS Encryption I/O Optimizations ($TARGET_USER)${NC}"
    echo -e "${BLUE}================================================================${NC}"

    echo -e "\n${GREEN}[1/3] Removing persistent systemd unit ($SERVICE_NAME)...${NC}"
    if [ -f "$SERVICE_PATH" ]; then
        sudo systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
        sudo rm -f "$SERVICE_PATH"
        sudo systemctl daemon-reload
    fi

    echo -e "\n${GREEN}[2/3] Restoring default relatime mount option on $HOME_DIR...${NC}"
    sudo mount -o remount,relatime "$HOME_DIR" || true

    echo -e "\n${GREEN}[3/3] Restoring default dm-crypt kernel workqueues on $MAPPER_NAME...${NC}"
    CRYPTSETUP_BIN=$(command -v cryptsetup || echo "/sbin/cryptsetup")
    if [ -e "$MAPPER_DEV" ]; then
        sudo "$CRYPTSETUP_BIN" refresh --allow-discards "$MAPPER_NAME" || true
    fi

    echo -e "\n${YELLOW}==> Status AFTER Revert (back to stock defaults):${NC}"
    show_status

    echo -e "\n${GREEN}All settings have been reverted to stock defaults.${NC}"
}

case "${1:---apply}" in
    --apply|apply)
        apply_tuning
        ;;
    --revert|revert|--undo|undo)
        revert_tuning
        ;;
    --status|status)
        show_status
        ;;
    *)
        echo "Usage: $0 [--apply | --revert | --status]"
        exit 1
        ;;
esac
