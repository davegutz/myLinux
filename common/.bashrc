# ~/.bashrc - Unified interactive bash configuration
# Managed by myLinux across CachyOS, Lubuntu, Pop!_OS, and Ubuntu

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# --- History Configuration ---
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s checkwinsize

# --- Environment & PATH ---
# Add user binary directories to PATH if not already present
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
case ":$PATH:" in
    *":$HOME/bin:"*) ;;
    *) export PATH="$HOME/bin:$PATH" ;;
esac

# Identify chroot if present (Ubuntu/Debian)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# Set terminal title
case "$TERM" in
    xterm*|rxvt*|alacritty*)
        PROMPT_TITLE='\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]'
        ;;
    *)
        PROMPT_TITLE=''
        ;;
esac

# --- Unified Git-Aware Colored Prompt ---
__prompt_command() {
    local EXIT_STATUS="$?"
    local PS_SYMBOL="\\$"
    local PS_COLOR="\\[\\033[01;32m\\]" # Green if last cmd succeeded
    if [ $EXIT_STATUS -ne 0 ]; then
        PS_COLOR="\\[\\033[01;31m\\]" # Red if last cmd failed
    fi

    local GIT_INFO=""
    local branch
    branch=$(git branch --show-current 2>/dev/null)
    if [ -n "$branch" ]; then
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            GIT_INFO=" \\[\\033[01;33m\\]($branch*)\\[\\033[00m\\]"
        else
            GIT_INFO=" \\[\\033[01;32m\\]($branch)\\[\\033[00m\\]"
        fi
    fi

    PS1="${PROMPT_TITLE}${debian_chroot:+($debian_chroot)}\\[\\033[01;36m\\]\\u\\[\\033[00m\\]@\\[\\033[01;34m\\]\\h\\[\\033[00m\\]:\\[\\033[01;33m\\]\\w\\[\\033[00m\\]${GIT_INFO} ${PS_COLOR}${PS_SYMBOL}\\[\\033[00m\\] "
}
PROMPT_COMMAND=__prompt_command

# --- Color Support & Dircolors ---
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

# --- Bash Completion ---
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# --- Load Shared Aliases ---
if [ -f "$HOME/.bash_aliases" ]; then
    . "$HOME/.bash_aliases"
fi

# --- Load Machine-Specific Overrides (if present) ---
if [ -f "$HOME/.bashrc.local" ]; then
    . "$HOME/.bashrc.local"
fi

# --- Modern CLI Integrations ---
# Zoxide directory jumper
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
fi

# Display fastfetch on initial interactive terminal launch if available
if command -v fastfetch >/dev/null 2>&1 && [ "$SHLVL" -eq 1 ]; then
    fastfetch
fi
