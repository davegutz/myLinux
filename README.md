# myLinux Configuration & Environment Synchronization

A centralized dotfiles and configuration manager designed to keep diverse Linux distributions—specifically **CachyOS** (Arch-based / COSMIC / KDE) and **Lubuntu / Ubuntu** (Debian-based / LXQt / KDE)—visually identical and functionally aligned.

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
git clone https://github.com/davegutz/myLinux.git   # or your remote path
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

A desktop widget / launcher and synchronization engine maintained via GNU Stow under `common/`. It refreshes local copies of the joint accounting book and budget spreadsheets from Google Drive before launching GnuCash.

### Features:
- **Cloud Synchronization**: Safely pulls latest versions of:
  - `~/Documents/Gutz_joint_gnucash/Gutz_joint.gnucash`
  - `budget avg less invest.ods`
  - `categories_as_budget_20220101-20240301.ods`
  from Google Drive (`~/gdrive/Finance remote/` or direct rclone).
- **Automatic Directory Discovery**: Auto-detects the active/newest remote folder containing `Gutz_joint.gnucash` (e.g. `GnuCash 2026-0926-1015 remote` or `Gutz_joint_gnucash`). Can also be explicitly configured.
- **Safety Pre-Backups**: Automatically creates timestamped copies of local files in `~/Documents/Gutz_joint_gnucash/.backups/` before applying any remote changes (retaining the 10 most recent backups).
- **Concurrency & Stale Lock Protection**: Detects if GnuCash is actively running to prevent file corruption, and cleans up stale `.LCK` lock files left over from ungraceful shutdowns or system crashes.
- **Desktop Widget & Actions**:
  - Direct launcher on the Desktop (`~/Desktop/GnuCash-Joint.desktop`).
  - System application menu launcher (`~/.local/share/applications/GnuCash-Joint.desktop`).
  - Right-click desktop actions:
    - **Refresh from Google Drive Only** (sync without launching)
    - **Open GnuCash Folder** (opens local directory in file manager)
    - **Open Budget Spreadsheets** (opens both `.ods` files in LibreOffice Calc)

### Configuration (`~/.config/gnucash/refresh-joint.conf`):
```bash
# Target local directory and files
LOCAL_DIR="$HOME/Documents/Gutz_joint_gnucash"
GNUCASH_FILE="Gutz_joint.gnucash"
SPREADSHEET_FILES=(
    "budget avg less invest.ods"
    "categories_as_budget_20220101-20240301.ods"
)

# Remote location on Google Drive
GDRIVE_MOUNT="$HOME/gdrive"
REMOTE_BASE_PATH="Finance remote"
# Leave REMOTE_FOLDER empty to auto-detect newest folder
REMOTE_FOLDER=""

# Safety backups & notifications
CREATE_BACKUP=true
BACKUP_DIR="$LOCAL_DIR/.backups"
MAX_BACKUPS=10
NOTIFY=true
```
Create `~/.config/gnucash/refresh-joint.conf.local` for machine-specific overrides.

### CLI Usage:
```bash
# Check current local vs remote synchronization status:
gnucash-refresh --status

# Simulate refresh without writing files:
gnucash-refresh --dry-run

# Refresh cloud files without opening GnuCash:
gnucash-refresh --refresh-only

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
