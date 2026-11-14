#!/usr/bin/env bash
# scripts/install_secure_cam.sh - Automated installer for security camera (motion + motionEye)
# Aligns system packages, /opt/motioneye virtual environment, systemd services,
# firewall rules, and motionEye configuration based on INSTALL_secure_cam.md.
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MYCOMPUTER_DIR="$(cd "$DOTFILES_DIR/../myComputer" 2>/dev/null && pwd || echo "$HOME/Documents/GitHub/myComputer")"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Automated Security Camera Setup (motionEye)      ${NC}"
echo -e "${BLUE}====================================================${NC}"

# Check for sudo/root permissions
if [ "$EUID" -ne 0 ] && ! sudo -v >/dev/null 2>&1; then
    echo -e "${RED}Error: Root or passwordless sudo access is required to configure system services.${NC}"
    exit 1
fi

# 1. Install System Dependencies
echo -e "\n${GREEN}[Step 1/6] Installing system dependencies (motion, ffmpeg, v4l-utils)...${NC}"

if [ -f /etc/debian_version ]; then
    DEBIAN_PKGS="motion ffmpeg v4l-utils feh python3-venv python3-pip python3-pil ca-certificates curl"
    MISSING_PKGS=""
    for pkg in $DEBIAN_PKGS; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            MISSING_PKGS="$MISSING_PKGS $pkg"
        fi
    done

    if [ -n "$MISSING_PKGS" ]; then
        echo "Installing missing Debian/Ubuntu packages:$MISSING_PKGS"
        sudo apt-get update
        sudo apt-get install -y --no-install-recommends $MISSING_PKGS
    else
        echo "System packages already installed."
    fi

elif [ -f /etc/arch-release ]; then
    ARCH_PKGS="motion ffmpeg v4l-utils feh python python-pip python-pillow curl"
    MISSING_PKGS=""
    for pkg in $ARCH_PKGS; do
        if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
            MISSING_PKGS="$MISSING_PKGS $pkg"
        fi
    done

    if [ -n "$MISSING_PKGS" ]; then
        echo "Installing missing Arch/CachyOS packages:$MISSING_PKGS"
        sudo pacman -Syu --needed --noconfirm $MISSING_PKGS
    else
        echo "System packages already installed."
    fi
else
    echo -e "${YELLOW}Notice: Unrecognized distribution. Skipping automated package manager installation.${NC}"
fi

# 2. Setup motion system user, groups, and runtime directories
echo -e "\n${GREEN}[Step 2/6] Configuring service users and runtime directories...${NC}"

# Ensure motion user/group exists
if ! id -u motion >/dev/null 2>&1; then
    echo "Creating system user 'motion'..."
    sudo useradd -r -s /usr/sbin/nologin -d /var/lib/motion motion || true
fi

# Add target user to motion group and video group
TARGET_USER="${SUDO_USER:-$USER}"
sudo usermod -a -G video,motion "$TARGET_USER" 2>/dev/null || true

# Create motioneye system directories
sudo mkdir -p /etc/motioneye
sudo mkdir -p /var/lib/motioneye/Camera1
sudo mkdir -p /var/log/motioneye
sudo chown -R motion:motion /etc/motioneye /var/lib/motioneye /var/log/motioneye
sudo chmod 755 /var/lib/motioneye /var/lib/motioneye/Camera1

# 3. Setup motionEye virtual environment
echo -e "\n${GREEN}[Step 3/6] Setting up motionEye in dedicated virtual environment (/opt/motioneye)...${NC}"

if [ ! -x "/opt/motioneye/bin/meyectl" ]; then
    echo "Creating Python virtual environment in /opt/motioneye..."
    sudo python3 -m venv --upgrade-deps /opt/motioneye
    sudo /opt/motioneye/bin/pip install --upgrade pip setuptools wheel
    echo "Installing motioneye via pip..."
    sudo /opt/motioneye/bin/pip install motioneye
fi

# Create symlink so meyectl is globally accessible
if [ ! -L "/usr/local/bin/meyectl" ]; then
    echo "Creating symlink /usr/local/bin/meyectl..."
    sudo ln -sf /opt/motioneye/bin/meyectl /usr/local/bin/meyectl
fi

# 4. Deploy motionEye configuration & systemd service
echo -e "\n${GREEN}[Step 4/6] Configuring motionEye and motion settings...${NC}"

# Deploy base motioneye.conf if not present
if [ ! -f "/etc/motioneye/motioneye.conf" ]; then
    echo "Generating /etc/motioneye/motioneye.conf..."
    sudo tee /etc/motioneye/motioneye.conf >/dev/null << 'EOF'
conf_path /etc/motioneye
run_path /run/motioneye
log_path /var/log/motioneye
media_path /var/lib/motioneye
log_level info
listen 0.0.0.0
port 8765
motion_control_localhost true
motion_control_port 7999
motion_check_interval 10
motion_restart_on_errors false
cleanup_interval 43200
add_remove_cameras true
EOF
    sudo chown motion:motion /etc/motioneye/motioneye.conf
fi

# Check for backup config tarball from myComputer
if [ -f "$MYCOMPUTER_DIR/motioneye-config.tar.gz" ]; then
    echo "Found motioneye-config.tar.gz in myComputer. Restoring..."
    sudo tar -zxvf "$MYCOMPUTER_DIR/motioneye-config.tar.gz" -C /etc/motioneye/
    sudo chown -R motion:motion /etc/motioneye/
fi

# Ensure camera-1.conf uses validated working codec (mp4 / software x264, not hardware v4l2m2m)
if [ -f "/etc/motioneye/camera-1.conf" ]; then
    echo "Verifying camera-1.conf codec compatibility..."
    sudo sed -i 's/movie_codec mp4:h264_v4l2m2m/movie_codec mp4/' /etc/motioneye/camera-1.conf
    sudo sed -i 's/movie_codec mp4:h264_omx/movie_codec mp4/' /etc/motioneye/camera-1.conf
fi

# Deploy systemd service unit
if [ ! -f "/etc/systemd/system/motioneye.service" ]; then
    echo "Creating /etc/systemd/system/motioneye.service..."
    sudo tee /etc/systemd/system/motioneye.service >/dev/null << 'EOF'
[Unit]
Description=motionEye Server
After=network.target local-fs.target remote-fs.target

[Service]
User=motion
RuntimeDirectory=motioneye
LogsDirectory=motioneye
StateDirectory=motioneye
ExecStart=/usr/local/bin/meyectl startserver -c /etc/motioneye/motioneye.conf
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF
fi

# 5. User-level local captures and standalone motion setup
echo -e "\n${GREEN}[Step 5/6] Creating user capture directories and local configs...${NC}"

USER_HOME=$(eval echo "~$TARGET_USER")
mkdir -p "$USER_HOME/camera_captures"
mkdir -p "$USER_HOME/.local"

# Generate motion mask if PIL is available
if python3 -c "from PIL import Image, ImageDraw" 2>/dev/null && [ ! -f "$USER_HOME/.local/mask.pgm" ]; then
    echo "Generating camera detection mask at $USER_HOME/.local/mask.pgm..."
    python3 -c "from PIL import Image, ImageDraw; img = Image.new('L', (1280, 720), 0); draw = ImageDraw.Draw(img); draw.rectangle([427, 0, 1280, 720], fill=255); img.save('$USER_HOME/.local/mask.pgm')"
fi

# Deploy standalone secure_cam.conf if not present
if [ ! -f "$USER_HOME/.local/secure_cam.conf" ]; then
    echo "Creating standalone fallback config at $USER_HOME/.local/secure_cam.conf..."
    cat << EOF > "$USER_HOME/.local/secure_cam.conf"
# Input device
video_device /dev/video0
width 1280
height 720
framerate 10

# Motion detection & capture rate
threshold 1500
minimum_motion_frames 3
event_gap 30

# Picture capture
picture_output off
picture_filename %Y%m%d_%H%M%S-%q

# Movie capture
movie_output on
movie_codec mp4
movie_filename %Y%m%d_%H%M%S

# Destination directory
target_dir $USER_HOME/camera_captures

# Mask to stop spurious trips
mask_file $USER_HOME/.local/mask.pgm
EOF
fi

# 6. Firewall & Service Activation
echo -e "\n${GREEN}[Step 6/6] Configuring firewall and activating motionEye service...${NC}"

# Open port 8765 if ufw is active
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -qw "active"; then
    echo "Opening firewall port 8765/tcp in ufw..."
    sudo ufw allow 8765/tcp comment 'motionEye Web Interface' || true
fi

# Reload systemd and enable/start motioneye
sudo systemctl daemon-reload
sudo systemctl enable motioneye
sudo systemctl restart motioneye

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}   Security Camera (motionEye) Installed!           ${NC}"
echo -e "${GREEN}====================================================${NC}"
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
echo -e "Web Dashboard URL:"
echo -e "  Local:        ${YELLOW}http://localhost:8765${NC} or ${YELLOW}http://${LOCAL_IP}:8765${NC}"
if command -v tailscale >/dev/null 2>&1; then
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
    if [ -n "$TS_IP" ]; then
        echo -e "  Tailscale:    ${YELLOW}http://${TS_IP}:8765${NC}"
    fi
fi
echo -e "\nQuick CLI Tools:"
echo -e "  Browse media:    ${YELLOW}camera-review${NC} (or: ${YELLOW}camera-review --vlc${NC})"
echo -e "  Daily timelapse: ${YELLOW}camera-timelapse${NC}"
