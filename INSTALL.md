# Installing & Synchronizing myLinux

Quick reference guide for onboarding a new machine or synchronizing existing Linux installations.

---

## ⚡ 1. Fresh Machine Onboarding

To set up a fresh Linux machine (CachyOS, Lubuntu, Pop!_OS, or Ubuntu) with full configuration parity:

```bash
# 1. Clone into your standard GitHub directory:
mkdir -p ~/Documents/GitHub && cd ~/Documents/GitHub
git clone https://github.com/davegutz/myLinux.git
cd myLinux

# 2. Run the automated installer:
./install.sh
```

*(Note: On a bare-metal install without `stow`, run `sudo apt install stow` or `sudo pacman -S stow` first.)*

At the end of installation, a fresh shell is spawned automatically with all new commands (`myLinux`, aliases, and tools) active immediately.

---

## 🔄 2. Synchronizing Existing Machines

Whenever you push configuration updates from one machine, sync any other machine with:

```bash
myLinux sync
```
*(Or pull dotfiles and run full OS package upgrades at the same time: `myLinux update`)*

---

## 📋 3. Quick Command Reference

Type **`myLinux -h`** at any time to see the master command list:

| Command | Action |
|---------|--------|
| `myLinux -h` | Show help and available commands |
| `myLinux sync` | Pull latest dotfiles from GitHub (with clash guard) and re-stow |
| `myLinux update` | Pull dotfiles and run full OS package updates |
| `myLinux push ["msg"]` | Check GitHub for clashes, lock `SecretsVault`, commit, and push |
| `myLinux camera` | Install and configure Security Camera NVR (motionEye) |
| `myLinux camera-review` | Open interactive thumbnail viewer of today's captures |
| `myLinux clean` | Reclaim root `/` disk space, vacuum logs, and fstrim |
| `myLinux secrets [sync|setup|push|pull|lock|status]` | Manage Cryptomator `SecretsVault` (`rclone/rclone.conf` in Git) |
| `myLinux finance [status|unlock|lock|backup|setup]` | Manage Cryptomator FinanceVault & USB backups |
| `myLinux tune-io` | Optimize `systemd-homed` LUKS eMMC/SSD I/O performance |
| `myLinux status` | Check git status of the myLinux repository |
| `myLinux check` | Check if this machine is ahead or behind GitHub |
| `myLinux cd` | Jump to repository directory (`cd $(myLinux cd)`) |
| `reload` | Reload bash session (`source ~/.bashrc`) |

---

## 🛠️ Root Shortcuts in Repository

If you are working inside the `~/Documents/GitHub/myLinux` directory:
* `./install.sh` $\rightarrow$ Runs `scripts/bootstrap.sh`
* `./myLinux -h` $\rightarrow$ Runs `common/.local/bin/myLinux`
* `./sync.sh`    $\rightarrow$ Runs `scripts/sync.sh`
