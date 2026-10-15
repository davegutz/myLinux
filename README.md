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
│   ├── .config/
│   │   ├── alacritty/
│   │   │   └── alacritty.toml            # Alacritty terminal settings (Catppuccin Mocha, JetBrains Mono)
│   │   ├── fastfetch/
│   │   │   └── config.jsonc              # Fastfetch system information card
│   │   ├── gtk-3.0/
│   │   │   └── settings.ini              # GTK-3 dark mode enforcement
│   │   └── gtk-4.0/
│   │       └── settings.ini              # GTK-4 dark mode enforcement
│   └── .local/
│       └── bin/
│           ├── gg                        # Launcher for Dave G's custom git_gui from myComputer
│           ├── sys-update                # Universal package & flatpak updater (Arch + Ubuntu)
│           └── dotfiles                  # myLinux repository management CLI
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
| `mylinux-sync` / `dotfiles sync` | Pulls latest Git commits and re-stows all configurations |
| `mylinux-update` / `dotfiles update` | Pulls Git changes, re-stows, and runs a full system update (`pacman`/`paru` or `apt` + `flatpaks`) |
| `sys-update` | Runs the distribution-aware system updater directly |
| `gg` | Launches Dave G's custom `git_gui.py` GUI tool from `myComputer` |
| `reload` | Reloads `~/.bashrc` in the active shell |
| `suspend` | Calls `suspend_until 14:30` |
| `movmov` | Moves staged media to `/media/daveg/Lib/Movies` |
| `cdmylinux` / `cdcomp` | Quickly changes directory to `myLinux` or `myComputer` |
| `gs`, `ga`, `gc`, `gp`, `gl`, `gd` | Standard Git shortcuts (`status`, `add`, `commit`, `push`, `pull`, `diff`) |

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
