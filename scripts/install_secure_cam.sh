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
NTFY_TOPIC="${NTFY_TOPIC:-gutz_camera_alerts}"
SURVEILLANCE_USER="${SURVEILLANCE_USER:-user}"
SURVEILLANCE_PASSWORD="${SURVEILLANCE_PASSWORD:-}"

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

# Configure ntfy.sh push notification topic
echo "Configuring ntfy push notification topic: $NTFY_TOPIC"
echo "$NTFY_TOPIC" | sudo tee /etc/motioneye/ntfy_topic >/dev/null
sudo chown motion:motion /etc/motioneye/ntfy_topic
sudo chmod 644 /etc/motioneye/ntfy_topic

# Store surveillance viewer password for auto-login URL generation if provided
if [ -n "$SURVEILLANCE_PASSWORD" ]; then
    echo "Configuring surveillance viewer credentials in /etc/motioneye/surveillance_password..."
    echo "$SURVEILLANCE_PASSWORD" | sudo tee /etc/motioneye/surveillance_password >/dev/null
    sudo chown motion:motion /etc/motioneye/surveillance_password
    sudo chmod 600 /etc/motioneye/surveillance_password
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

# Ensure camera configs use the active python version in event hooks (sendmail, relayevent)
if [ -n "$PY_VER" ]; then
    echo "Adapting camera event hook paths to active virtualenv Python ($PY_VER)..."
    for conf in /etc/motioneye/camera-*.conf; do
        if [ -f "$conf" ]; then
            sudo sed -i -E "s|/opt/motioneye/lib/python3\.[0-9]+/|/opt/motioneye/lib/${PY_VER}/|g" "$conf"
        fi
    done
fi

# Inject monitoring URL link and ntfy push notification into motionEye alert transmission
echo "Injecting monitor URL link ($MONITOR_URL) and ntfy push alerts ($NTFY_TOPIC) into motionEye..."
sudo /opt/motioneye/bin/python3 -c "
import glob

patch_code = '''    # Append configured monitor URL for viewing recordings
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

    # Check for surveillance auto-login password
    autologin_url = monitor_url
    pass_file = '/etc/motioneye/surveillance_password'
    if os.path.isfile(pass_file):
        try:
            with open(pass_file, 'r') as f:
                s_pass = f.read().strip()
            if s_pass:
                import urllib.parse
                s_user = 'user'
                sep = '&' if '?' in monitor_url else '?'
                autologin_url = f'{monitor_url}/{sep}user={urllib.parse.quote(s_user)}&pass={urllib.parse.quote(s_pass)}'
        except Exception:
            pass

    if 'View recordings & live monitor:' not in message:
        message = message.strip() + f'\\\\n\\\\nView recordings & live monitor:\\\\n{autologin_url}\\\\n'

    # Dispatch push notification to ntfy.sh if topic is configured
    try:
        ntfy_topic = None
        topic_file = '/etc/motioneye/ntfy_topic'
        if os.path.isfile(topic_file):
            try:
                with open(topic_file, 'r') as f:
                    ntfy_topic = f.read().strip()
            except Exception:
                pass
        if not ntfy_topic:
            ntfy_topic = 'gutz_camera_alerts'

        if ntfy_topic:
            import urllib.request
            ntfy_headers = {
                'Title': str(subject).strip(),
                'Priority': 'default',
                'Tags': 'video_camera,warning',
            }
            if autologin_url:
                ntfy_headers['Click'] = autologin_url
            ntfy_body = message.strip().encode('utf-8')
            ntfy_req = urllib.request.Request(
                f'https://ntfy.sh/{ntfy_topic}',
                data=ntfy_body,
                headers=ntfy_headers,
                method='POST',
            )
            with urllib.request.urlopen(ntfy_req, timeout=5) as ntfy_resp:
                logging.info(f'ntfy notification sent to {ntfy_topic} (HTTP {ntfy_resp.status})')
    except Exception as ntfy_err:
        logging.warning(f'ntfy notification failed: {ntfy_err}')
'''

for sendmail_path in glob.glob('/opt/motioneye/lib/python*/site-packages/motioneye/sendmail.py'):
    with open(sendmail_path, 'r') as f:
        content = f.read()

    marker = '    # Append configured monitor URL for viewing recordings'
    target = '    email = MIMEMultipart()'
    if marker in content:
        idx1 = content.find(marker)
        idx2 = content.find(target)
        if idx1 != -1 and idx2 != -1 and idx1 < idx2:
            content = content[:idx1] + patch_code + '\n' + content[idx2:]
            with open(sendmail_path, 'w') as f:
                f.write(content)
            print(f'Updated {sendmail_path} with ntfy push notification integration')
    elif target in content:
        content = content.replace(target, patch_code + '\n' + target, 1)
        with open(sendmail_path, 'w') as f:
            f.write(content)
        print(f'Patched {sendmail_path} with monitor link & ntfy push alerts')
"

# Enable URL Parameter Auto-Login (?user=...&pass=...) in MainHandler
echo "Enabling URL parameter auto-login in motionEye MainHandler..."
sudo /opt/motioneye/bin/python3 -c "
import glob

patch_main = '''class MainHandler(BaseHandler):
    def get(self):
        # Auto-login via URL parameters (?user=...&pass=... or ?username=...&password=...)
        username = self.get_argument('user', self.get_argument('username', None))
        password = self.get_argument('pass', self.get_argument('password', None))
        if username and password is not None:
            try:
                from motioneye.handlers.login import (
                    verify_argon2_password,
                    verify_legacy_sha1_password,
                    should_use_secure_cookie,
                )
                from motioneye.handlers.base import create_session
                from motioneye.utils.authstate import build_password_hash_state

                main_config = config.get_main()
                hash_state = build_password_hash_state(main_config)
                user_type = None
                stored_hash = ''
                hash_type = ''

                if username == main_config.get('@admin_username'):
                    user_type = 'admin'
                    stored_hash = main_config.get('@admin_password') or ''
                    hash_type = hash_state.admin.hash_type
                elif username == main_config.get('@normal_username'):
                    user_type = 'normal'
                    stored_hash = main_config.get('@normal_password') or ''
                    hash_type = hash_state.normal.hash_type

                if user_type:
                    valid = False
                    if hash_type == 'argon2':
                        valid = verify_argon2_password(stored_hash, password)
                    elif hash_type == 'legacy':
                        valid = (password == stored_hash) or verify_legacy_sha1_password(stored_hash, password)
                    elif hash_type == 'missing':
                        valid = (password == '')

                    if valid:
                        session_id = create_session(user_type)
                        self.set_secure_cookie(
                            'user',
                            session_id,
                            expires_days=30,
                            httponly=True,
                            secure=should_use_secure_cookie(self),
                            samesite='Strict',
                        )
                        self.current_user = user_type
            except Exception as e:
                import logging
                logging.warning(f'URL parameter auto-login failed: {e}')

        # additional config'''

for main_path in glob.glob('/opt/motioneye/lib/python*/site-packages/motioneye/handlers/main.py'):
    with open(main_path, 'r') as f:
        content = f.read()
    if 'Auto-login via URL parameters' not in content:
        target = '''class MainHandler(BaseHandler):
    def get(self):
        # additional config'''
        if target in content:
            content = content.replace(target, patch_main, 1)
            with open(main_path, 'w') as f:
                f.write(content)
            print(f'Patched {main_path} for URL parameter auto-login')
"

# Enable Automatic Guest / Viewer Mode (zero-login monitoring)
echo "Enabling automatic guest viewer mode for live monitor & recordings..."
sudo /opt/motioneye/bin/python3 -c "
import glob

# 1. Patch handlers/base.py so unauthenticated sessions default to 'normal' viewer
for base_path in glob.glob('/opt/motioneye/lib/python*/site-packages/motioneye/handlers/base.py'):
    with open(base_path, 'r') as f:
        content = f.read()
    target = '''            except (ValueError, TypeError):
                return None

        return None'''
    replacement = '''            except (ValueError, TypeError):
                return None

        # Guest viewer mode: default unauthenticated visitors to 'normal' viewer
        return 'normal\''''
    if target in content:
        with open(base_path, 'w') as f:
            f.write(content.replace(target, replacement, 1))
        print(f'Patched {base_path} for guest viewer mode')

# 2. Patch handlers/login.py to extend admin session cookie lifetime to 30 days
for login_path in glob.glob('/opt/motioneye/lib/python*/site-packages/motioneye/handlers/login.py'):
    with open(login_path, 'r') as f:
        content = f.read()
    if 'expires_days=1,' in content:
        with open(login_path, 'w') as f:
            f.write(content.replace('expires_days=1,', 'expires_days=30,', 1))
        print(f'Patched {login_path} for 30-day session lifetime')

# 3. Patch static/js/main.js so switch user button prompts admin login and ?admin=1 works
for js_path in glob.glob('/opt/motioneye/lib/python*/site-packages/motioneye/static/js/main.js'):
    with open(js_path, 'r') as f:
        content = f.read()
    target_logout = \"\"\"    /* logout button */
    \$('div.button.logout-button').on('click', doLogout);\"\"\"
    replacement_logout = \"\"\"    /* logout / switch user button */
    \$('div.button.logout-button').on('click', function() {
        if (isAdmin()) {
            doLogout();
        } else {
            runLoginDialog(function () {
                window._loginRetry = true;
                doAuth();
            });
        }
    });\"\"\"
    if target_logout in content:
        content = content.replace(target_logout, replacement_logout, 1)

    target_startup = '''    if(hasCurrentSession()) {
        doAuth();
    } else {
        runLoginDialog(function () {
            window._loginRetry = true;
            doAuth();
        });
    }'''
    replacement_startup = '''    var query = splitUrl().params;
    if ((query.admin || query.login) && !isAdmin()) {
        runLoginDialog(function () {
            window._loginRetry = true;
            doAuth();
        });
    } else if(hasCurrentSession()) {
        doAuth();
    } else {
        runLoginDialog(function () {
            window._loginRetry = true;
            doAuth();
        });
    }'''
    if target_startup in content:
        content = content.replace(target_startup, replacement_startup, 1)

    with open(js_path, 'w') as f:
        f.write(content)
    print(f'Patched {js_path} for seamless guest access & admin elevation')
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
echo -e "  5. The dashboard opens automatically in Guest Viewer mode (no password required)."
echo -e "     To manage settings: tap the top-left Switch User icon (or append ${YELLOW}?admin=1${NC}) to log in as ${CYAN}admin${NC}."
echo -e "     ${YELLOW}Tip:${NC} In mobile Chrome, tap menu (⋮) -> 'Add to Home screen' for 1-tap app access."

echo -e "\n${GREEN}--- Push Notifications (ntfy.sh) ---${NC}"
echo -e "  Dedicated Camera Topic: ${CYAN}${NTFY_TOPIC}${NC}"
echo -e "  1. Install ${BOLD}ntfy${NC} app on your phone (Android/iOS) or open in browser: ${YELLOW}https://ntfy.sh/${NTFY_TOPIC}${NC}"
echo -e "  2. Tap ${BOLD}'+'${NC} and subscribe to: ${CYAN}${NTFY_TOPIC}${NC}"
echo -e "  3. Every motion alert will ping your phone with a direct link to the camera monitor."

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
