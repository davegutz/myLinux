#!/usr/bin/env bash
# scripts/clean_root.sh - Reclaim root (/) filesystem space on Lubuntu/Ubuntu & CachyOS
# Also configures APT to use /home for package downloads if root (/) is small/tight.
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Root (/) Filesystem Cleanup & APT Cache Relief   ${NC}"
echo -e "${BLUE}====================================================${NC}"

echo -e "\n${YELLOW}==> Disk space BEFORE cleanup:${NC}"
df -h / "$HOME" 2>/dev/null || df -h

if [ -f /etc/debian_version ]; then
    echo -e "\n${GREEN}[1/6] Cleaning APT package cache (/var/cache/apt/archives)...${NC}"
    sudo apt-get clean
    sudo rm -rf /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/* 2>/dev/null || true

    echo -e "\n${GREEN}[2/6] Removing orphaned packages and old kernels...${NC}"
    sudo apt-get autoremove --purge -y || true
elif [ -f /etc/arch-release ]; then
    echo -e "\n${GREEN}[1/6] Cleaning pacman package cache...${NC}"
    if command -v paccache >/dev/null 2>&1; then
        sudo paccache -rk1
        sudo paccache -ruk0
    else
        sudo pacman -Sc --noconfirm
    fi
fi

echo -e "\n${GREEN}[3/6] Vacuuming systemd journal and rotated logs in /var/log...${NC}"
if command -v journalctl >/dev/null 2>&1; then
    sudo journalctl --vacuum-size=50M || true
fi
sudo find /var/log -type f \( -name "*.gz" -o -name "*.[0-9]" -o -name "*.old" \) -delete 2>/dev/null || true
sudo rm -rf /var/crash/* 2>/dev/null || true

echo -e "\n${GREEN}[4/6] Cleaning snapd download cache and disabled snap revisions...${NC}"
if [ -d /var/lib/snapd/cache ]; then
    sudo rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
fi
if command -v snap >/dev/null 2>&1; then
    sudo snap set system refresh.retain=2 2>/dev/null || true
    snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
        if [ -n "$snapname" ] && [ -n "$revision" ]; then
            echo -n "  Purging old superseded revision: $snapname (rev $revision)... "
            if sudo snap remove "$snapname" --revision="$revision" >/dev/null 2>&1; then
                echo "done"
            else
                echo "skipped"
            fi
        fi
    done
fi

echo -e "\n${GREEN}[5/6] Cleaning active user caches (~/.cache/rclone, Trash, thumbnails)...${NC}"
rm -rf "$HOME/.cache/rclone" \
       "$HOME/.cache/thumbnails" \
       "$HOME/.local/share/Trash/files/"* \
       "$HOME/.local/share/Trash/info/"* 2>/dev/null || true

echo -e "\n${GREEN}[6/6] Trimming loopback / SSD free blocks (fstrim on $HOME and /)...${NC}"
# Especially critical when $HOME is a systemd-homed loopback file (/home/daveg.home) on /
sudo fstrim -v "$HOME" 2>/dev/null || true
sudo fstrim -v / 2>/dev/null || true

if [ -f /home/daveg.home ]; then
    echo "  /home/daveg.home allocated vs apparent size:"
    ls -lh --block-size=M -s /home/daveg.home 2>/dev/null || true
fi

echo -e "\n${YELLOW}==> Disk space AFTER cleanup:${NC}"
df -h / "$HOME" 2>/dev/null || df -h

echo -e "\n${BLUE}==> Largest directories on Root (/) filesystem (/dev/mmcblk0p2):${NC}"
sudo du -xh --max-depth=2 / 2>/dev/null | sort -hr | head -n 20 || true

