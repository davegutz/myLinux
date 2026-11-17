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
CYAN='\033[0;36m'
BOLD='\033[1m'
RED='\033[0;31m'
NC='\033[0m'

# Configurable Host, Port, and Monitor URL for MotionEye Web Dashboard & Recording access
MOTIONEYE_PORT="${MOTIONEYE_PORT:-8765}"
MOTIONEYE_HOST="${MOTIONEYE_HOST:-$(hostname)}"
MONITOR_URL="${MONITOR_URL:-http://${MOTIONEYE_HOST}:${MOTIONEYE_PORT}}"

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Automated Security Camera Setup (motionEye)      ${NC}"
echo -e "${BLUE}====================================================${NC}"

# Check for sudo/root permissions
if [ "$EUID" -ne 0 ] && ! sudo -v >/dev/null 2>&1; then
    echo -e "${RED}Error: Root or passwordless sudo access is required to configure system services.${NC}"
    exit 1
fi

# 1. Install System Dependencies
echo -e "\n${GREEN}[Step 1/7] Installing system dependencies (motion, ffmpeg, v4l-utils)...${NC}"

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
echo -e "\n${GREEN}[Step 2/7] Configuring service users and runtime directories...${NC}"

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
echo -e "\n${GREEN}[Step 3/7] Setting up motionEye in dedicated virtual environment (/opt/motioneye)...${NC}"

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

# Ensure motionEye subprocesses (like background cleanup) locate the config directory
sudo mkdir -p /opt/motioneye/etc
sudo ln -sf /etc/motioneye /opt/motioneye/etc/motioneye

# Detect installed virtualenv Python version
PY_VER=$(find /opt/motioneye/lib -maxdepth 1 -type d -name "python3.*" 2>/dev/null | head -n 1 | xargs -r basename)

# Create compatibility symlinks for alternate python versions so legacy configs resolve
if [ -n "$PY_VER" ]; then
    for legacy_py in python3.10 python3.11 python3.12 python3.13 python3.14; do
        if [ "$legacy_py" != "$PY_VER" ] && [ ! -e "/opt/motioneye/lib/$legacy_py" ]; then
            sudo ln -sf "/opt/motioneye/lib/$PY_VER" "/opt/motioneye/lib/$legacy_py"
        fi
    done
fi

# 4. Deploy motionEye configuration & systemd service
echo -e "\n${GREEN}[Step 4/7] Configuring motionEye and motion settings...${NC}"

# Deploy base motioneye.conf if not present
if [ ! -f "/etc/motioneye/motioneye.conf" ]; then
    echo "Generating /etc/motioneye/motioneye.conf..."
    sudo tee /etc/motioneye/motioneye.conf >/dev/null << EOF
conf_path /etc/motioneye
run_path /run/motioneye
log_path /var/log/motioneye
media_path /var/lib/motioneye
log_level info
listen 0.0.0.0
port ${MOTIONEYE_PORT}
motion_control_localhost true
motion_control_port 7999
motion_check_interval 10
motion_restart_on_errors false
cleanup_interval 43200
add_remove_cameras true
EOF
    sudo chown motion:motion /etc/motioneye/motioneye.conf
fi

# Configure monitor URL for email notification links
echo "Configuring camera monitor URL link: $MONITOR_URL"
echo "$MONITOR_URL" | sudo tee /etc/motioneye/monitor_url >/dev/null
sudo chown motion:motion /etc/motioneye/monitor_url
sudo chmod 644 /etc/motioneye/monitor_url

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

# Ensure camera configs use the active python version in event hooks (sendmail, relayevent)
if [ -n "$PY_VER" ]; then
    echo "Adapting camera event hook paths to active virtualenv Python ($PY_VER)..."
    for conf in /etc/motioneye/camera-*.conf; do
        if [ -f "$conf" ]; then
            sudo sed -i -E "s|/opt/motioneye/lib/python3\.[0-9]+/|/opt/motioneye/lib/${PY_VER}/|g" "$conf"
        fi
    done
fi

# Inject monitoring URL link into motionEye email transmission
echo "Injecting monitoring URL link ($MONITOR_URL) into motionEye sendmail..."
sudo /opt/motioneye/bin/python3 -c "
import glob

patch_code = '''    # Append configured monitor URL for viewing recordings
    if 'View recordings & live monitor:' not in message:
        monitor_url = None
        url_file = '/etc/motioneye/monitor_url'
        if os.path.isfile(url_file):
            try:
                with open(url_file, 'r') as f:
                    monitor_url = f.read().strip()
            except Exception:
                pass
        if not monitor_url:
            p = getattr(settings, 'PORT', 8765)
            monitor_url = f'http://{socket.gethostname()}:{p}'
        message = message.strip() + f'\\\\n\\\\nView recordings & live monitor:\\\\n{monitor_url}\\\\n'
'''

for sendmail_path in glob.glob('/opt/motioneye/lib/python*/site-packages/motioneye/sendmail.py'):
    with open(sendmail_path, 'r') as f:
        content = f.read()
    if 'View recordings & live monitor:' not in content:
        target = '    email = MIMEMultipart()'
        if target in content:
            new_content = content.replace(target, patch_code + '\n' + target, 1)
            with open(sendmail_path, 'w') as f:
                f.write(new_content)
            print(f'Patched {sendmail_path} with monitor link')
"

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
echo -e "\n${GREEN}[Step 5/7] Creating user capture directories and local configs...${NC}"

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

# 6. Ensure Tailscale is installed and connected
echo -e "\n${GREEN}[Step 6/7] Ensuring Tailscale mesh VPN is installed and configured...${NC}"

if ! command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale not detected. Installing Tailscale via official installer..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# Ensure tailscaled service is enabled and started
sudo systemctl enable tailscaled
sudo systemctl start tailscaled

# Check if authenticated into a tailnet
ACTUAL_USER="${SUDO_USER:-$USER}"
if ! tailscale ip -4 >/dev/null 2>&1; then
    echo -e "${YELLOW}Tailscale is installed but not connected to your account.${NC}"
    if [ -t 0 ]; then
        echo -e "Starting Tailscale login. Open the URL in your browser to sign in (e.g. davegutz2006@gmail.com):"
        sudo tailscale up --operator="$ACTUAL_USER" || true
    else
        echo -e "${YELLOW}Non-interactive terminal detected. Run 'sudo tailscale up --operator=$ACTUAL_USER' to log in.${NC}"
    fi
fi

# 7. Firewall & Service Activation
echo -e "\n${GREEN}[Step 7/7] Configuring firewall and activating motionEye service...${NC}"

# Open port if ufw is active
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -qw "active"; then
    echo "Opening firewall port ${MOTIONEYE_PORT}/tcp in ufw..."
    sudo ufw allow "${MOTIONEYE_PORT}/tcp" comment 'motionEye Web Interface' || true
fi

# Reload systemd and enable/start motioneye
sudo systemctl daemon-reload
sudo systemctl enable motioneye
sudo systemctl restart motioneye

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}   Security Camera (motionEye) Installed!           ${NC}"
echo -e "${GREEN}====================================================${NC}"
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
TS_IP=""
if command -v tailscale >/dev/null 2>&1; then
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
fi

echo -e "${BOLD}Web Dashboard / Monitor URL:${NC}"
echo -e "  Configured:   ${YELLOW}${MONITOR_URL}${NC}"
echo -e "  Local:        ${YELLOW}http://localhost:${MOTIONEYE_PORT}${NC} or ${YELLOW}http://${LOCAL_IP}:${MOTIONEYE_PORT}${NC}"
if [ -n "$TS_IP" ]; then
    echo -e "  Tailscale:    ${YELLOW}http://${TS_IP}:${MOTIONEYE_PORT}${NC}"
fi

echo -e "\n${GREEN}--- Phone Setup (Tailscale Remote Access) ---${NC}"
echo -e "  1. Install ${BOLD}Tailscale${NC} from the Google Play Store or Apple App Store."
echo -e "  2. Sign in as designated Tailscale user: ${CYAN}davegutz2006@gmail.com${NC}"
echo -e "  3. Toggle the Tailscale VPN switch to ${BOLD}Connected${NC}."
if [ -n "$TS_IP" ]; then
    echo -e "  4. In your phone browser, open: ${YELLOW}http://${TS_IP}:${MOTIONEYE_PORT}${NC} (or ${YELLOW}${MONITOR_URL}${NC})"
else
    echo -e "  4. In your phone browser, open: ${YELLOW}${MONITOR_URL}${NC}"
fi
echo -e "  5. Log in with viewer account (username: ${CYAN}user${NC}, password set in motionEye General Settings)."
echo -e "     ${YELLOW}Tip:${NC} In mobile Chrome, tap menu (⋮) -> 'Add to Home screen' for 1-tap app access."

echo -e "\n${GREEN}--- Gmail Motion Notification Filters ---${NC}"
echo -e "  Targeted recipient emails (from motioneye-config.tar.gz):"
echo -e "    • ${CYAN}davegutz2006@gmail.com${NC}"
echo -e "    • ${CYAN}kpeanes@gmail.com${NC}"
echo -e "  To prevent inbox clutter and organize motion alerts in Gmail for each account:"
echo -e "  1. Open Gmail -> Settings (gear icon) -> ${BOLD}'See all settings'${NC} -> ${BOLD}'Filters and Blocked Addresses'${NC}."
echo -e "  2. Click ${BOLD}'Create a new filter'${NC} and configure:"
echo -e "     - From: ${CYAN}davegutz2006@gmail.com${NC}"
echo -e "     - Subject / Has words: ${CYAN}motion_start${NC} (or ${CYAN}Camera1${NC})"
echo -e "  3. Click ${BOLD}'Create filter'${NC} and select:"
echo -e "     • ${YELLOW}Apply the label:${NC} create a label (e.g. 'Camera-Alerts')"
echo -e "     • ${YELLOW}Skip the Inbox (Archive it)${NC} (optional, to keep main inbox clean)"
echo -e "     • ${YELLOW}Never send it to Spam${NC}"

echo -e "\n${GREEN}--- Gmail App Token Note ---${NC}"
echo -e "  Designated SMTP sending user: ${CYAN}davegutz2006@gmail.com${NC}"
echo -e "  Google requires a 16-character ${BOLD}App Password${NC} (not your standard account password):"
echo -e "  1. Ensure 2-Step Verification is turned on for ${CYAN}davegutz2006@gmail.com${NC}."
echo -e "  2. Go to: ${CYAN}https://myaccount.google.com/apppasswords${NC}"
echo -e "  3. Create an app password named 'motionEye' and copy the 16-character token."
echo -e "  4. Configure in motionEye -> Settings -> Motion Notifications (or camera-1.conf):"
echo -e "     - SMTP Server: ${YELLOW}smtp.gmail.com:587${NC} (TLS: ON)"
echo -e "     - From / Username: ${CYAN}davegutz2006@gmail.com${NC}"
echo -e "     - Password: ${YELLOW}<16-character app token>${NC}"

echo -e "\n${GREEN}--- Quick CLI Tools ---${NC}"
echo -e "  Browse media:    ${YELLOW}camera-review${NC} (or: ${YELLOW}camera-review --vlc${NC})"
echo -e "  Daily timelapse: ${YELLOW}camera-timelapse${NC}"
