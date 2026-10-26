# myLinux Configuration & Environment Synchronization

A centralized dotfiles and configuration manager designed to keep diverse Linux distributions—specifically **CachyOS** (Arch-based / COSMIC / KDE) and **Lubuntu / Ubuntu** (Debian-based / LXQt / KDE)—visually identical and functionally aligned.

---

## ⚡ Quickstart

### 1. New Machine Onboarding (CachyOS or Lubuntu)
To set up a fresh Linux installation with full environment parity, configurations, and desktop widgets:

```bash
# 1. Clone the repository into your GitHub directory:
mkdir -p ~/Documents/GitHub && cd ~/Documents/GitHub
git clone https://github.com/davegutz/myLinux.git   # or: git clone git@github.com:davegutz/myLinux.git
cd myLinux

# 2. Run the automated bootstrap manager:
./scripts/bootstrap.sh

# 3. Reload your terminal shell:
source ~/.bashrc
```

---

### 2. Refreshing & Synchronizing Existing Machines
Whenever you make configuration changes on one machine, publish them to GitHub and sync across your other installations:

#### Step 1: Push Updates to GitHub (Handling 2FA)
Because GitHub accounts with **Two-Factor Authentication (2FA)** reject plain account passwords over HTTPS, use one of the standard GitHub authentication methods:

* **Option A: SSH Key Authentication (Recommended for terminal `git push`)**
  Configure SSH once on each machine so `git push` works seamlessly without credential prompts:
  1. Generate an SSH key if you haven't already:
     ```bash
     ssh-keygen -t ed25519 -C "davegutz@alum.mit.edu"
     ```
  2. Copy your public key to clipboard or terminal output:
     ```bash
     cat ~/.ssh/id_ed25519.pub
     ```
  3. Add the key on GitHub: **Settings** → **SSH and GPG keys** → **New SSH key**.
  4. Ensure your repository uses the SSH remote URL:
     ```bash
     git -C ~/Documents/GitHub/myLinux remote set-url origin git@github.com:davegutz/myLinux.git
     ```
  5. Commit and push normally:
     ```bash
     git add -A && git commit -m "Describe your update"
     git push
     ```

* **Option B: Personal Access Token (PAT) with Git Credential Helper**
  1. On GitHub: navigate to **Settings** → **Developer Settings** → **Personal access tokens** → **Tokens (classic)**.
  2. Generate a new token with the `repo` scope.
  3. Enable credential storage so you only enter the token once:
     ```bash
     git config --global credential.helper store
     ```
  4. Run `git push`, enter your GitHub username, and paste the Personal Access Token into the password prompt.

* **Option C: GitHub Web UI (Quick edits without terminal auth)**
  For quick script or config tweaks, edit the file directly on [github.com/davegutz/myLinux](https://github.com/davegutz/myLinux) in your browser and click **Commit changes**.

#### Step 2: Pull and Apply Updates on Other Machines
On any of your other computers, pull the latest commits and automatically re-stow all configurations:

```bash
dotfiles sync         # (or 'mylinux-sync')
```

> [!TIP]
> **What `dotfiles sync` does automatically:**
> * Pulls latest commits (`git pull --rebase`).
> * Pre-creates any required directories (`~/.config/gnucash`, `~/Desktop`, `~/.local/share/applications`).
> * Re-stows configurations and desktop shortcuts cleanly via GNU Stow.
> * Preserves permissions (`chmod +x` on scripts and desktop launchers).
> * Runs `update-desktop-database` so application menus and desktop icons refresh immediately without requiring a logout or reboot.

```bash
# Useful inspection commands on any machine:
dotfiles check            # See if remote GitHub updates are waiting without pulling
gnucash-refresh --status  # Check GnuCash book & spreadsheet sync states and cloud locks
```

---

### 3. GnuCash Joint Desktop Widget & Process Monitor
The desktop launcher (`~/Desktop/GnuCash-Joint.desktop`) manages bidirectional synchronization with Google Drive (`gdrive:Finance remote/Gutz_joint_gnucash`):

* **Launch**: Double-click **GnuCash (Joint)** on your desktop or run `gnucash-refresh` in any terminal.
* **Integrated Process Monitor**: Automatically opens inside your terminal emulator (`konsole` on CachyOS, `qterminal` on Lubuntu) with live PID display and timestamped save logs.
* **Minimize**: You can minimize the monitor window to your taskbar/panel while working; desktop notifications keep you informed on every save.
* **Auto-Sync on Save (Ctrl+S)**: Every local save is debounced (5s) and pushed to Google Drive in the background.
* **Closing**: Closing the monitor window (or GnuCash) triggers a final exit sync, releases the cloud `.session_lock`, and leaves zero zombie processes.
* **Right-Click Desktop Menu**:
  * *Launch Silently (No Terminal)*
  * *Refresh from Google Drive Only*
  * *Open GnuCash Folder*
  * *Open Budget Spreadsheets (.ods)*
  * *Release Cloud Lock*

---

### 4. Google Drive & Rclone Setup (`rclone.conf`)
The `~/bin/Rclone` mount and daily backup rely on an active `gdrive:` remote configured in `~/.config/rclone/rclone.conf`.

> [!IMPORTANT]
> **Why `rclone.conf` is NOT included in this repository:**
> `rclone.conf` contains sensitive authentication secrets—including active OAuth access tokens, refresh tokens, and private client secrets. Because GitHub repositories must never store credentials or private tokens, `rclone.conf` is intentionally excluded from the `myLinux` configuration and must be set up or copied locally on each machine.

#### Keeping vs. Updating `token =` in `rclone.conf`:
* **Default Setup (No Custom Client ID)**: **Keep** `token = ...`. It holds your Google OAuth login session and refresh token. Without it, Rclone cannot authenticate.
* **Custom Google Cloud Client ID (Recommended to avoid 403 Rate Limits)**: You **cannot reuse the old token**, as Google OAuth tokens are strictly bound to the specific Client ID that created them.
  1. Add your custom credentials to `~/.config/rclone/rclone.conf`:
     ```ini
     [gdrive]
     type = drive
     scope = drive
     client_id = your_client_id.apps.googleusercontent.com
     client_secret = your_client_secret
     ```
  2. Run the reconnect command (note the trailing colon `:`):
     ```bash
     rclone config reconnect gdrive:
     ```
     *(Omitting the trailing `:` treats `gdrive` as a local path and triggers `Error: backend doesn't support reconnect or authorize`)*.
  3. Complete authorization in your browser. Rclone will **automatically overwrite `token = ...`** with a new, valid token linked to your Client ID.
  4. Restart your active mount so it loads the new token:
     ```bash
     fusermount3 -u ~/gdrive && Rclone
     ```
     *(Rclone does not reload tokens while actively mounted. If you skip restarting the mount, existing file operations like `ls` or `rm` will fail with `Input/output error` / HTTP 401)*.

#### Thunar File Manager Quick Fixes (Sluggish or Freezing Mounts):
If browsing `~/gdrive` in Thunar is slow or hangs:
* **Disable Thumbnails in Thunar**: Thunar's thumbnail daemon (`tumblerd`) attempts to download pieces of remote video/image files across FUSE to render previews, which blocks the UI.
  * In Thunar: go to **Edit** → **Preferences** → **Display** tab.
  * Set **Show thumbnails** to **Never** (or **Local files only**).
* **Tune Rclone Mount Options (`~/bin/Rclone`)**:
  * Once a personal Google Client ID is configured, remove `--tpslimit 5` and `--tpslimit-burst 5` (which bottlenecks requests to 5 per second).
  * Use `--attr-timeout 1s` and `--no-checksum` for quick directory responsiveness while keeping file updates/locks synchronized across machines.
* **Alternative File Managers**:
  * On KDE Plasma, **Dolphin** (`sudo apt install dolphin`) handles remote network I/O asynchronously in worker threads and will not lock the window.
  * **PCManFM-Qt** (`pcmanfm-qt ~/gdrive`) is already installed on the system and is significantly lighter.

---

## Key Objectives

1. **Visual Parity**: Maintain an identical look and feel (terminal colors, fonts, prompt, window padding, GTK/Qt dark themes) across all laptops, workstations, and dual-boot instances.
2. **Workflow Consistency**: Share aliases, git shortcuts, custom scripts (`gg`, `suspend`, `movmov`), tmux profiles, and CLI tools across machines.
3. **Distribution Independence**: Automatically adapt package installation and system maintenance commands to Arch (`pacman`/`paru`) or Debian/Ubuntu (`apt`).
4. **Safety & Non-Destructive Deployment**: Pre-backup any existing dotfiles before symlinking so no configuration is ever clobbered.

---

## Repository Architecture

```text
myLinux/
├── common/                               # Configurations shared across all builds (stowed to $HOME)
│   ├── .bashrc                           # Unified interactive bash setup (git-aware prompt, colors, paths)
│   ├── .bash_aliases                     # Global aliases, shortcuts, and repo quick-jumps
│   ├── .tmux.conf                        # Unified tmux multiplexer theme and configuration
│   ├── bin/                              # User binaries stowed to ~/bin (in PATH)
│   │   ├── encodeLinux.sh                # DVD transcode automation (outputs to ~/Videos/encodeLinux)
│   │   ├── Fast 480p30.json              # HandBrakeCLI encoding preset
│   │   ├── fetch_subtitles.py            # Automated English subtitle fetcher
│   │   ├── jobStat.sh                    # Transcode progress status reporter
│   │   ├── Rclone                        # Google Drive mount and VFS cache refresh automation
│   │   ├── run_time.sh                   # Video duration / ffprobe inspector
│   │   └── stripit.sh                    # Video filename sanitization tool
│   ├── Desktop/
│   │   └── GnuCash-Joint.desktop         # Desktop launcher/widget for GnuCash Joint with cloud refresh
│   ├── .config/
│   │   ├── alacritty/
│   │   │   └── alacritty.toml            # Alacritty terminal settings (Catppuccin Mocha, JetBrains Mono)
│   │   ├── autostart/
│   │   │   └── rclone.desktop            # Universal Google Drive mount on login (~/bin/Rclone)
│   │   ├── fastfetch/
│   │   │   └── config.jsonc              # Fastfetch system information card
│   │   ├── gnucash/
│   │   │   └── refresh-joint.conf        # Configuration for GnuCash Joint Google Drive sync
│   │   ├── gtk-3.0/
│   │   │   └── settings.ini              # GTK-3 dark mode enforcement
│   │   └── gtk-4.0/
│   │       └── settings.ini              # GTK-4 dark mode enforcement
│   └── .local/
│       ├── bin/
│       │   ├── gg                        # Launcher for Dave G's custom git_gui from myComputer
│       │   ├── gnucash-refresh           # Safe cloud refresh engine & launcher for GnuCash & budget ODS
│       │   ├── sys-update                # Universal package & flatpak updater (Arch + Ubuntu)
│       │   └── dotfiles                  # myLinux repository management CLI (sync, daemon, autostart)
│       └── share/
│           ├── applications/
│           │   └── GnuCash-Joint.desktop # App menu launcher & pinned panel widget
│           └── gnucash/                  # GnuCash shared book settings
│               └── books/
│                   └── Gutz_joint.gnucash.gcm
├── autostart-cosmic/                     # CachyOS COSMIC desktop startup files (stowed to $HOME)
│   └── .config/
│       └── autostart/
│           └── caffeine.desktop          # Idle sleep / screensaver prevention for COSMIC
├── autostart-gnome/                      # Lubuntu / Ubuntu GNOME startup files (stowed to $HOME)
│   └── .config/
│       └── autostart/
│           └── gnome-session-init.desktop # GNOME-specific session autostart hooks
├── autostart-plasma/                     # Lubuntu KDE Plasma startup files (stowed to $HOME)
│   └── .config/
│       └── autostart/
│           ├── firefox.desktop           # Firefox autostart for Plasma session
│           └── thunar.desktop            # File manager autostart for Plasma session
├── rclone-backup/                        # Daily automated rclone copy daemon (stowed to $HOME)
│   ├── .config/
│   │   ├── rclone/
│   │   │   └── daily-copy.conf           # Config file for daily copy sources, destination, and flags
│   │   └── systemd/
│   │       └── user/
│   │           ├── rclone-daily-backup.service # Oneshot systemd user service executing copy
│   │           └── rclone-daily-backup.timer   # Systemd user timer triggering daily (Persistent=true)
│   └── .local/
│       └── bin/
│           └── rclone-daily-backup       # Safe copy runner with flock, timeout, logs, & notifications
├── scripts/
│   ├── bootstrap.sh                      # Main idempotent onboarding & setup script
│   ├── sync.sh                           # Sync changes from Git, re-stow, and optional package upgrade
│   ├── backup.sh                         # Safety backup engine for existing non-symlink dotfiles
│   ├── install_fonts.sh                  # Installs JetBrains Mono Nerd Font cross-platform
│   ├── setup_appearance.sh               # Enforces dark mode (GTK, KDE Plasma, LXQt)
│   └── link_mycomputer.sh                # Verifies and links resources with the myComputer repo
└── README.md
```

---

## Initial Setup & Deployment

To configure a new Linux install (or align an existing one):

```bash
# 1. Clone the repository into your standard GitHub directory:
mkdir -p ~/Documents/GitHub
cd ~/Documents/GitHub
git clone https://github.com/davegutz/myLinux.git   # or: git clone git@github.com:davegutz/myLinux.git
cd myLinux

# 2. Run the bootstrap manager:
./scripts/bootstrap.sh
```

### What Bootstrap Automates:
1. **Package Discovery & Installation**: Installs `git`, `stow`, `alacritty`, `tmux`, `zoxide`, `curl`, and build tools using `pacman` on CachyOS/Arch or `apt` on Lubuntu/Ubuntu.
2. **Safe Dotfile Backup**: Detects any existing unmanaged files in `$HOME` (e.g. `.bashrc`, `.bash_aliases`) and backs them up to `~/.dotfiles_backup/backup_<timestamp>/`.
3. **Target Structure Creation**: Creates essential local directories (`~/.config/alacritty`, `~/.local/bin`, etc.) so GNU Stow symlinks individual configuration files rather than entire directory hierarchies.
4. **GNU Stow Symlinking**: Links `common/*` cleanly into `$HOME`.
5. **Font Installation**: Installs `JetBrains Mono Nerd Font` and rebuilds the font cache for consistent rendering and icon glyphs.
6. **Dark Theme Enforcement**: Applies dark mode settings across GTK (`gsettings` / `settings.ini`), KDE Plasma (`plasma-apply-colorscheme BreezeDark`), and LXQt.

---

## Daily Operations & Commands

Once deployed, the following utilities and aliases are available in any terminal:

| Command / Alias | Action |
|-----------------|--------|
| `encodeLinux.sh` | Transcodes DVD discs to `.m4v` and fetches `.en.srt` subtitles into `~/Videos/encodeLinux` |
| `mylinux-sync` / `dotfiles sync` | Pulls latest Git commits and re-stows configurations & active autostart profile |
| `mylinux-update` / `dotfiles update` | Pulls Git changes, re-stows, and runs a full system update (`pacman`/`paru` or `apt` + `flatpaks`) |
| `dotfiles check` | Queries GitHub to see if remote commits or updates are available |
| `dotfiles autostart [DE]` | Stow or switch autostart profile (`cosmic`, `gnome`, `plasma`, `detect`, or `status`) |
| `dotfiles daemon [action]` | Control daily rclone copy daemon (`status`, `enable`, `disable`, `run`, `logs`) |
| `sys-update` | Runs the distribution-aware system updater directly |
| `gg` | Launches Dave G's custom `git_gui.py` GUI tool from `myComputer` |
| `reload` | Reloads `~/.bashrc` in the active shell |
| `suspend` | Calls `suspend_until 14:30` |
| `movmov` | Moves staged media to `/media/daveg/Lib/Movies` |
| `gnucash-refresh` / `gnucash-joint` | Refreshes `Gutz_joint.gnucash` and budget `.ods` files from Google Drive and opens GnuCash |
| `Rclone` | Mounts Google Drive (`gdrive:`) to `~/gdrive` with 50GB VFS cache and warms directory tree |
| `cdmylinux` / `cdcomp` | Quickly changes directory to `myLinux` or `myComputer` |
| `gs`, `ga`, `gc`, `gp`, `gl`, `gd` | Standard Git shortcuts (`status`, `add`, `commit`, `push`, `pull`, `diff`) |

---

## Auto-Startup Management Across Desktop Environments

Linux desktop environments follow the [XDG Desktop Autostart Specification](https://specifications.freedesktop.org/autostart-spec/latest/). Files in `~/.config/autostart/*.desktop` are read and launched on user login.

GNU Stow manages autostart entries modularly so you can maintain common items across all machines while isolating DE-specific applications:

1. **Shared Autostart (`common/`)**:
   - `common/.config/autostart/rclone.desktop`: Mounts Google Drive (`~/bin/Rclone`) to `~/gdrive` across all systems.
2. **CachyOS COSMIC (`autostart-cosmic/`)**:
   - `autostart-cosmic/.config/autostart/caffeine.desktop`: Desktop idle lock / sleep inhibitor.
   - Restricted with `OnlyShowIn=COSMIC;`.
3. **Lubuntu GNOME (`autostart-gnome/`)**:
   - `autostart-gnome/.config/autostart/gnome-session-init.desktop`: GNOME session startup hooks.
   - Restricted with `OnlyShowIn=GNOME;`.
4. **Lubuntu KDE Plasma (`autostart-plasma/`)**:
   - `autostart-plasma/.config/autostart/firefox.desktop`: Auto-launches Firefox on session login.
   - `autostart-plasma/.config/autostart/thunar.desktop`: File manager helper.
   - Restricted with `OnlyShowIn=KDE;`.

### Stowing or Switching Autostart Profiles
- **Automatic**: `scripts/bootstrap.sh` and `scripts/sync.sh` automatically detect `$XDG_CURRENT_DESKTOP` or `$DESKTOP_SESSION` and stow the matching profile.
- **Manual CLI**:
  ```bash
  # Check current stowed autostart links:
  dotfiles autostart status

  # Switch or re-stow for a specific DE:
  dotfiles autostart plasma
  dotfiles autostart cosmic
  dotfiles autostart gnome
  ```

---

## Daily Rclone Copy Daemon (`rclone-backup`)

The repository includes a stowed systemd user daemon that performs an automated, optimized `rclone copy` once daily.

### How It Works:
- **Package**: `rclone-backup` is stowed directly into `$HOME`.
- **Systemd User Timer** (`~/.config/systemd/user/rclone-daily-backup.timer`): Triggers daily with `Persistent=true` (if the computer was suspended or powered down at the scheduled time, it triggers immediately upon the next wake/boot).
- **Systemd User Service** (`~/.config/systemd/user/rclone-daily-backup.service`): Runs the backup script at a low CPU/IO priority (`nice 15`, `best-effort 7`) so it never impacts desktop responsiveness.
- **Runner Script** (`~/.local/bin/rclone-daily-backup`):
  - Enforces a single-instance lock (`flock`) to prevent overlapping backup runs.
  - Verifies network connectivity to the rclone remote before starting.
  - Sends desktop notifications on completion or errors via `notify-send`.
  - Appends detailed timestamped logs to `~/.local/state/rclone/daily-backup.log`.

### Customizing Backup Sources and Targets:
Edit `~/.config/rclone/daily-copy.conf` (or create `~/.config/rclone/daily-copy.conf.local` for machine-specific overrides):
```bash
# Target remote and destination directory
RCLONE_REMOTE="gdrive"
RCLONE_DEST="gdrive:DailyBackup"

# Folders to copy daily
BACKUP_SOURCES=(
    "$HOME/Documents"
    # "$HOME/Pictures"
    # "/media/daveg/Lib/Movies"
)

# Tuned transfer parameters
RCLONE_FLAGS=(
    --drive-chunk-size 128M
    --transfers 4
    --checkers 8
    --retries 3
    --stats 30s
    --fast-list
)
```

### Daemon Management Commands:
```bash
# View timer schedule and service status:
dotfiles daemon status

# Run a backup immediately on demand:
dotfiles daemon run

# View live / recent backup execution logs:
dotfiles daemon logs

# Enable or disable the daily timer:
dotfiles daemon enable
dotfiles daemon disable
```

> [!TIP]
> If you want the daily timer to execute even when you are logged out of your graphical desktop session, enable systemd user lingering:
> ```bash
> loginctl enable-linger $USER
> ```

---

## GnuCash Joint Auto-Refresh Desktop Widget

A desktop widget / launcher and bidirectional synchronization engine maintained via GNU Stow under `common/`. It manages local copies of the joint accounting book and budget spreadsheets from Google Drive before, during, and after GnuCash runs.

### Features:
- **Cloud Synchronization**: Pulls latest versions before launch and automatically pushes saves back to Google Drive (`gdrive:Finance remote/Gutz_joint_gnucash`).
- **Dedicated Remote Folder**: Directly targets `Finance remote/Gutz_joint_gnucash` with no searching or scanning across other cloud directories.
- **In-Session Save Watcher**: While GnuCash is running, a supervisor monitor watches for local saves (Ctrl+S) and automatically pushes changes to Google Drive after a 5-second write debounce.
- **Post-Session Exit Sync**: On closing GnuCash, a guaranteed final sync flushes any updated files to Google Drive.
- **Zombie-Free Process Lifecycle**: The watcher process is strictly bound to GnuCash's PID with signal traps (`SIGTERM`, `SIGINT`, `EXIT`), ensuring no orphaned daemons or zombie processes linger after closing.
- **Cloud Session Lock (`.session_lock`)**: Prevents conflicting edits between dual-boot or separate Linux distributions. Alerts the user if another machine currently has GnuCash open and offers override/cancel options.
- **Safety Pre-Backups**: Automatically creates timestamped copies of local files in `~/Documents/Gutz_joint_gnucash/.backups/` and cloud backups in `gdrive:.../.backups/` before applying changes (retaining 10 backups).
- **Concurrency & Stale Lock Protection**: Detects local running instances and cleans up stale `.LCK` files left by power loss or crashes.
- **Integrated Process Monitor**: Automatically launches inside your desktop's terminal emulator (`konsole` on CachyOS, `qterminal` on Lubuntu) with live PID display and timestamped save logs. Minimize anytime while working, or close the terminal to safely save and exit.
- **Desktop Widget & Actions**:
  - Direct launcher on the Desktop (`~/Desktop/GnuCash-Joint.desktop`).
  - System application menu launcher (`~/.local/share/applications/GnuCash-Joint.desktop`).
  - Right-click desktop actions:
    - **Launch Silently (No Terminal)** (runs background sync without a visible window)
    - **Refresh from Google Drive Only** (pull without launching)
    - **Open GnuCash Folder** (opens local directory in file manager)
    - **Open Budget Spreadsheets** (opens both `.ods` files in LibreOffice Calc)
    - **Release Cloud Lock** (1-click unlock for stale cloud tokens)

### Configuration (`~/.config/gnucash/refresh-joint.conf`):
```bash
# Target local directory and files
LOCAL_DIR="$HOME/Documents/Gutz_joint_gnucash"
GNUCASH_FILE="Gutz_joint.gnucash"
SPREADSHEET_FILES=(
    "budget avg less invest.ods"
    "categories_as_budget_20220101-20240301.ods"
)

# Dedicated remote folder on Google Drive
GDRIVE_MOUNT="$HOME/gdrive"
REMOTE_BASE_PATH="Finance remote"
REMOTE_FOLDER="Gutz_joint_gnucash"

# Safety backups & cloud tokens
CREATE_BACKUP=true
BACKUP_DIR="$LOCAL_DIR/.backups"
MAX_BACKUPS=10
REMOTE_BACKUP=true
REMOTE_LOCK_ENABLED=true
STALE_LOCK_HOURS=6

# Bidirectional sync settings
SYNC_ON_SAVE=true
DEBOUNCE_SECONDS=5
SYNC_ON_EXIT=true
NOTIFY=true

# Terminal process monitor settings
TERMINAL_MONITOR=true
HOLD_TERMINAL=true
HOLD_SECONDS=3
HOLD_ON_ERROR=true
```
Create `~/.config/gnucash/refresh-joint.conf.local` for machine-specific overrides.

### CLI Usage:
```bash
# Check current local vs remote synchronization & cloud lock status:
gnucash-refresh --status

# Launch with integrated process monitor:
gnucash-refresh

# Run silently in background without terminal window:
gnucash-refresh --no-terminal

# Simulate refresh without writing files:
gnucash-refresh --dry-run

# Refresh cloud files without opening GnuCash:
gnucash-refresh --refresh-only

# Force release any stale cloud session lock:
gnucash-refresh --unlock

# Open the two budget spreadsheets in LibreOffice Calc:
gnucash-refresh --open-ods

# Open the local documents directory:
gnucash-refresh --open-folder
```

---

## Machine-Specific Customization (`.bashrc.local`)

To add machine-specific exports, unique API tokens, or hardware-specific aliases without committing them to the shared repository:

1. Create a `~/.bashrc.local` file:
   ```bash
   nano ~/.bashrc.local
   ```
2. Add your machine-specific settings (e.g., custom environment variables, special monitor settings).
3. The shared `common/.bashrc` automatically detects and sources `~/.bashrc.local` if it exists.

---

## Adding New Dotfiles to `common/`

To add a new shared configuration (for example, `~/.nanorc` or `~/.config/htop/htoprc`):

1. Mirror the path inside `common/`:
   ```bash
   mkdir -p ~/Documents/GitHub/myLinux/common/.config/htop
   cp ~/.config/htop/htoprc ~/Documents/GitHub/myLinux/common/.config/htop/
   ```
2. Back up or remove the original file in `$HOME` so Stow can link it:
   ```bash
   rm ~/.config/htop/htoprc
   ```
3. Re-run Stow:
   ```bash
   cd ~/Documents/GitHub/myLinux
   stow -v -R -t "$HOME" common
   ```
4. Commit and push the changes:
   ```bash
   git add common/.config/htop/htoprc
   git commit -m "Add htop configuration to common dotfiles"
   git push
   ```

---

## Cross-Linking with `myComputer`

This repository works in tandem with [`myComputer`](../myComputer/README.md). While `myComputer` contains machine-level installation runbooks, hardware notes, and firmware settings, `myLinux` provides the living configuration state deployed onto each active Linux operating system.
