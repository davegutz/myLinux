#!/usr/bin/env bash
# scripts/git_guard.sh - Concurrency lock, GitHub pre-flight check, and safe clash resolution for myLinux
set -e

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
DOTFILES_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
BACKUP_ROOT="$HOME/.dotfiles_backup"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 1. Local single-instance lock helper (prevents two terminals running sync/guard simultaneously)
acquire_guard_lock() {
    LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/mylinux-git-guard.lock"
    exec 201>"$LOCK_FILE"
    if ! flock -w 10 201; then
        echo -e "${YELLOW}[myLinux Guard] Another myLinux git operation is currently active. Waiting/skipping...${NC}" >&2
        return 1
    fi
    return 0
}

release_guard_lock() {
    flock -u 201 2>/dev/null || true
    exec 201>&- 2>/dev/null || true
}

# 2. Fast network-bounded git fetch (timeout 4s so offline machines never hang)
fast_fetch() {
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        return 1
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout 4s git -C "$DOTFILES_DIR" fetch origin --quiet 2>/dev/null || return 1
    else
        git -C "$DOTFILES_DIR" fetch origin --quiet 2>/dev/null || return 1
    fi
    return 0
}

# 3. Clean up any broken mid-rebase or mid-merge state left by a previous interrupted run
recover_interrupted_git_state() {
    if [ -d "$DOTFILES_DIR/.git/rebase-merge" ] || [ -d "$DOTFILES_DIR/.git/rebase-apply" ]; then
        echo -e "${YELLOW}==> [myLinux Guard] Detected unfinished git rebase in $DOTFILES_DIR. Aborting cleanly...${NC}"
        git -C "$DOTFILES_DIR" rebase --abort 2>/dev/null || true
    fi
    if [ -f "$DOTFILES_DIR/.git/MERGE_HEAD" ]; then
        echo -e "${YELLOW}==> [myLinux Guard] Detected unfinished git merge in $DOTFILES_DIR. Aborting cleanly...${NC}"
        git -C "$DOTFILES_DIR" merge --abort 2>/dev/null || true
    fi
}

# 4. Auto-discard benign GnuCash UI state noise (*.gcm) if it is the only dirty file blocking a pull
clean_benign_noise_if_behind() {
    local dirty_files
    dirty_files="$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null || true)"
    if [ -z "$dirty_files" ]; then
        return 0
    fi

    # Check if every modified line is just a .gcm metadata file
    local non_gcm
    non_gcm="$(echo "$dirty_files" | grep -v '\.gcm$' || true)"
    if [ -z "$non_gcm" ]; then
        echo -e "${BLUE}==> [myLinux Guard] Resetting benign GnuCash window metadata (.gcm) before syncing...${NC}"
        git -C "$DOTFILES_DIR" checkout -- "*.gcm" 2>/dev/null || true
    fi
}

# 5. Save full local backup snapshot before resolving any clash
backup_clash_state() {
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local clash_dir="$BACKUP_ROOT/clash_$ts"
    mkdir -p "$clash_dir"

    # Save git status, diff, and unpushed commit patches
    git -C "$DOTFILES_DIR" status > "$clash_dir/git_status.txt" 2>/dev/null || true
    git -C "$DOTFILES_DIR" diff HEAD > "$clash_dir/uncommitted.diff" 2>/dev/null || true
    git -C "$DOTFILES_DIR" format-patch "@{u}..HEAD" -o "$clash_dir" >/dev/null 2>&1 || true

    # Copy any modified or untracked working tree files
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local file_rel="${line:3}"
        # Strip quotes if present
        file_rel="${file_rel%\"}"
        file_rel="${file_rel#\"}"
        if [ -e "$DOTFILES_DIR/$file_rel" ]; then
            mkdir -p "$clash_dir/files/$(dirname "$file_rel")"
            cp -a "$DOTFILES_DIR/$file_rel" "$clash_dir/files/$file_rel" 2>/dev/null || true
        fi
    done < <(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)

    echo "$clash_dir"
}

# 6. Interactive Clash Resolver when auto-rebase encounters overlapping edits
resolve_clash_interactive() {
    local upstream_ref
    upstream_ref="$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo 'origin/master')"

    echo ""
    echo -e "${RED}${BOLD}===================================================================${NC}"
    echo -e "${RED}${BOLD}   ⚠️  CLASH DETECTED IN myLinux REPOSITORY                        ${NC}"
    echo -e "${RED}${BOLD}===================================================================${NC}"
    echo -e "Both GitHub (${CYAN}$upstream_ref${NC}) and this local machine have conflicting edits."
    echo ""
    echo -e "${YELLOW}${BOLD}Local Status:${NC}"
    git -C "$DOTFILES_DIR" status --short
    echo ""
    echo -e "${YELLOW}${BOLD}Incoming GitHub Commits:${NC}"
    git -C "$DOTFILES_DIR" log --oneline "HEAD..$upstream_ref" 2>/dev/null || true
    echo ""
    echo -e "${YELLOW}${BOLD}Unpushed Local Commits:${NC}"
    git -C "$DOTFILES_DIR" log --oneline "$upstream_ref..HEAD" 2>/dev/null || echo "  (none - uncommitted working tree edits only)"
    echo -e "${RED}${BOLD}===================================================================${NC}"

    # If non-interactive shell, do not clobber; back up and warn
    if [ ! -t 0 ]; then
        echo -e "${YELLOW}[myLinux Guard] Non-interactive session: leaving local files untouched. Run 'myLinux sync' in a terminal to resolve.${NC}"
        return 1
    fi

    echo ""
    echo -e "${BOLD}How would you like to resolve this clash?${NC}"
    echo -e "  ${GREEN}[1]${NC} ${BOLD}Accept GitHub version${NC} (backs up local edits to ~/.dotfiles_backup/clash_*, resets to GitHub)"
    echo -e "  ${GREEN}[2]${NC} ${BOLD}Keep Local version${NC}    (backs up state, rebases local changes on top of GitHub preferring local)"
    echo -e "  ${GREEN}[3]${NC} ${BOLD}Stash Local & Pull${NC}    (moves local uncommitted changes to 'git stash' and pulls GitHub)"
    echo -e "  ${GREEN}[4]${NC} ${BOLD}Show Diff & Abort${NC}     (prints full diff against GitHub and exits so you can inspect manually)"
    echo ""
    read -r -p "Select option [1-4] (default: 4): " choice

    case "${choice:-4}" in
        1)
            local bdir
            bdir="$(backup_clash_state)"
            echo -e "${BLUE}==> Local changes safely backed up to: ${CYAN}$bdir${NC}"
            git -C "$DOTFILES_DIR" reset --hard "$upstream_ref"
            git -C "$DOTFILES_DIR" clean -fd
            echo -e "${GREEN}==> Repository reset cleanly to GitHub ($upstream_ref).${NC}"
            return 0
            ;;
        2)
            local bdir
            bdir="$(backup_clash_state)"
            echo -e "${BLUE}==> State backed up to: ${CYAN}$bdir${NC}"
            # Commit any unstaged tracked changes first if needed, or stash and apply over upstream
            local had_dirty=false
            if [ -n "$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)" ]; then
                had_dirty=true
                git -C "$DOTFILES_DIR" stash push -u -m "mylinux-clash-local-$ bdir" >/dev/null 2>&1 || true
            fi
            # Rebase local commits preferring local ('-X theirs' in rebase means the commit being replayed—i.e. local!)
            if ! git -C "$DOTFILES_DIR" rebase -X theirs "$upstream_ref" 2>/dev/null; then
                git -C "$DOTFILES_DIR" rebase --abort 2>/dev/null || true
                git -C "$DOTFILES_DIR" reset --hard "$upstream_ref"
            fi
            if [ "$had_dirty" = true ]; then
                # Restore stashed local files on top, preferring stashed local copy if conflict
                if ! git -C "$DOTFILES_DIR" stash pop >/dev/null 2>&1; then
                    git -C "$DOTFILES_DIR" checkout --theirs . 2>/dev/null || true
                    git -C "$DOTFILES_DIR" reset HEAD . >/dev/null 2>&1 || true
                    git -C "$DOTFILES_DIR" stash drop >/dev/null 2>&1 || true
                fi
            fi
            echo -e "${GREEN}==> Local changes preserved on top of $upstream_ref.${NC}"
            echo -e "${YELLOW}    Remember to commit and push your changes so GitHub is updated!${NC}"
            return 0
            ;;
        3)
            local bdir
            bdir="$(backup_clash_state)"
            echo -e "${BLUE}==> State backed up to: ${CYAN}$bdir${NC}"
            git -C "$DOTFILES_DIR" stash push -u -m "mylinux-auto-stash-$(date +%Y%m%d_%H%M%S)"
            if ! git -C "$DOTFILES_DIR" pull --rebase origin master 2>/dev/null; then
                git -C "$DOTFILES_DIR" rebase --abort 2>/dev/null || true
                echo -e "${RED}==> Diverged commits still conflict. Use 'myLinux sync' and choose [1] or [2].${NC}"
                return 1
            fi
            echo -e "${GREEN}==> Local edits stashed ('git stash list') and GitHub updates pulled.${NC}"
            return 0
            ;;
        *)
            echo ""
            echo -e "${CYAN}=== Diff between Local Working Tree and $upstream_ref ===${NC}"
            git -C "$DOTFILES_DIR" diff "$upstream_ref" || true
            echo ""
            echo -e "${YELLOW}==> Aborted without modifying files. Resolve manually or re-run 'myLinux sync'.${NC}"
            return 1
            ;;
    esac
}

# 7. Safe Pull & Rebase (Used by sync.sh and auto-fast-forward)
cmd_safe_pull() {
    acquire_guard_lock || return 1
    trap release_guard_lock EXIT INT TERM HUP

    recover_interrupted_git_state

    echo -e "${GREEN}==> Checking GitHub remote status...${NC}"
    if ! fast_fetch; then
        echo -e "${YELLOW}Notice: Offline or GitHub unreachable. Proceeding with local repository state.${NC}"
        return 0
    fi

    local behind ahead dirty
    behind=$(git -C "$DOTFILES_DIR" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
    ahead=$(git -C "$DOTFILES_DIR" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)

    if [ "$behind" -gt 0 ]; then
        clean_benign_noise_if_behind
    fi

    dirty=$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null | wc -l)

    # Case 1: Already up to date with GitHub
    if [ "$behind" -eq 0 ]; then
        if [ "$ahead" -gt 0 ] || [ "$dirty" -gt 0 ]; then
            echo -e "${YELLOW}==> Local myLinux has unpushed/uncommitted changes ($ahead commit(s) ahead, $dirty modified file(s)).${NC}"
        else
            echo -e "${GREEN}==> myLinux is up to date with GitHub.${NC}"
        fi
        return 0
    fi

    # Case 2: Behind GitHub, and local is completely clean (0 ahead, 0 dirty) -> Fast-forward cleanly
    if [ "$ahead" -eq 0 ] && [ "$dirty" -eq 0 ]; then
        echo -e "${GREEN}==> Pulling $behind new commit(s) from GitHub (fast-forward)...${NC}"
        git -C "$DOTFILES_DIR" merge --ff-only "@{u}"
        return 0
    fi

    # Case 3: Behind GitHub AND local has changes (ahead > 0 or dirty > 0)
    echo -e "${YELLOW}==> GitHub has $behind new commit(s) while local has changes ($ahead commit(s) ahead, $dirty uncommitted file(s)).${NC}"

    # Do not auto-merge binary Cryptomator vault if both sides modified SecretsVault
    local remote_vault_changed local_vault_changed
    remote_vault_changed=$(git -C "$DOTFILES_DIR" diff --name-only HEAD..@{u} -- SecretsVault 2>/dev/null | wc -l)
    local_vault_changed=$(git -C "$DOTFILES_DIR" status --porcelain -- SecretsVault 2>/dev/null | wc -l)
    if [ "$local_vault_changed" -eq 0 ] && [ "$ahead" -gt 0 ]; then
        local_vault_changed=$(git -C "$DOTFILES_DIR" diff --name-only @{u}..HEAD -- SecretsVault 2>/dev/null | wc -l)
    fi

    if [ "$remote_vault_changed" -gt 0 ] && [ "$local_vault_changed" -gt 0 ]; then
        echo -e "${RED}==> Both GitHub and this machine modified SecretsVault! Avoiding automatic binary merge.${NC}"
        resolve_clash_interactive
        return $?
    fi

    # Attempt clean autostash rebase for non-overlapping files
    echo -e "${BLUE}==> Attempting safe autostash rebase...${NC}"
    if git -C "$DOTFILES_DIR" pull --rebase --autostash --quiet 2>/dev/null; then
        echo -e "${GREEN}==> Non-conflicting changes merged cleanly!${NC}"
        return 0
    else
        # Rebase or stash pop had a conflict! Immediately restore clean pre-rebase state
        recover_interrupted_git_state
        git -C "$DOTFILES_DIR" reset --merge 2>/dev/null || true
        resolve_clash_interactive
        return $?
    fi
}

# 8. Fast Pre-Flight Check run before general myLinux commands
cmd_preflight() {
    local subcmd="${1:-}"
    # Skip preflight for help, cd, diff, or recursive calls
    case "$subcmd" in
        ""|-h|--help|help|cd|diff|sync|update)
            return 0
            ;;
    esac

    if [ -n "${MYLINUX_PREFLIGHT_DONE:-}" ]; then
        return 0
    fi
    export MYLINUX_PREFLIGHT_DONE=1

    recover_interrupted_git_state

    # Silent 4s fetch; if offline, silently continue
    if ! fast_fetch; then
        return 0
    fi

    local behind ahead dirty
    behind=$(git -C "$DOTFILES_DIR" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
    ahead=$(git -C "$DOTFILES_DIR" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)

    if [ "$behind" -gt 0 ]; then
        clean_benign_noise_if_behind
    fi
    dirty=$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null | wc -l)

    if [ "$behind" -gt 0 ]; then
        if [ "$ahead" -eq 0 ] && [ "$dirty" -eq 0 ]; then
            echo -e "${YELLOW}==> [myLinux Guard] Local repo is behind GitHub by $behind commit(s). Auto-updating before running '$subcmd'...${NC}"
            if git -C "$DOTFILES_DIR" merge --ff-only "@{u}" >/dev/null 2>&1; then
                stow -R -t "$HOME" -d "$DOTFILES_DIR" common 2>/dev/null || true
                stow -R -t "$HOME" -d "$DOTFILES_DIR" rclone-backup 2>/dev/null || true
                echo -e "${GREEN}==> [myLinux Guard] Fast-forwarded and re-stowed latest commits from GitHub.${NC}"
            fi
        else
            echo -e "${RED}${BOLD}==> [myLinux Guard] WARNING: Potential clash detected!${NC}"
            echo -e "${YELLOW}    GitHub is $behind commit(s) ahead, and this machine has local changes ($ahead commit(s) ahead, $dirty modified file(s)).${NC}"
            if [ -t 0 ]; then
                read -r -p "    Resolve & sync with GitHub now before running 'myLinux $subcmd'? [Y/n]: " ans
                if [[ ! "${ans:-Y}" =~ ^[Nn]$ ]]; then
                    cmd_safe_pull
                fi
            else
                echo -e "${YELLOW}    Run 'myLinux sync' to resolve before making further edits.${NC}"
            fi
        fi
    elif [ "$ahead" -gt 0 ] || [ "$dirty" -gt 0 ]; then
        echo -e "${CYAN}==> [myLinux Guard] Note: Local repo has unpushed changes ($ahead ahead, $dirty uncommitted). Push when done to prevent clashes.${NC}"
    fi
}

# 9. Safe Commit & Push Helper ('myLinux push [msg]')
cmd_safe_push() {
    local msg="${*:-Update myLinux configurations on $(hostname)}"

    # First ensure we are synced with GitHub and have no clashes
    cmd_safe_pull

    # Ensure SecretsVault is locked before staging
    if [ -x "$DOTFILES_DIR/scripts/sync_secrets_vault.sh" ]; then
        "$DOTFILES_DIR/scripts/sync_secrets_vault.sh" lock >/dev/null 2>&1 || true
    fi

    git -C "$DOTFILES_DIR" add -A
    if [ -n "$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)" ]; then
        git -C "$DOTFILES_DIR" commit -m "$msg"
    fi

    local ahead
    ahead=$(git -C "$DOTFILES_DIR" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
    if [ "$ahead" -gt 0 ]; then
        echo -e "${GREEN}==> Pushing $ahead commit(s) to GitHub...${NC}"
        git -C "$DOTFILES_DIR" push
        echo -e "${GREEN}==> Successfully pushed to GitHub!${NC}"
    else
        echo -e "${GREEN}==> Nothing new to push. Working tree is clean and in sync with GitHub.${NC}"
    fi
}

case "${1:-preflight}" in
    preflight)
        shift || true
        cmd_preflight "$@"
        ;;
    pull|sync)
        cmd_safe_pull
        ;;
    push)
        shift || true
        cmd_safe_push "$@"
        ;;
    resolve|clash)
        resolve_clash_interactive
        ;;
    *)
        echo "Usage: $(basename "$0") [preflight <cmd> | pull | push [msg] | resolve]"
        exit 1
        ;;
esac
