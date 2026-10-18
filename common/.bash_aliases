# ~/.bash_aliases - Shared aliases and environment for all Linux builds (myLinux)
# Compatible with CachyOS, Lubuntu, Pop!_OS, and Ubuntu

# --- Navigation & Listing ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# --- Safety & Diagnostics ---
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias df='df -h'
alias free='free -h'
alias c='clear'

# --- Shell Management ---
alias reload='source ~/.bashrc'
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# --- User Workflows ---
# suspend_until script in ~/bin
alias suspend='suspend_until 14:30'
alias movmov='mv /Public/* /media/daveg/Lib/Movies 2>/dev/null || true'
alias gnucash-joint='gnucash-refresh'
alias gnucash-refresh='gnucash-refresh'

# --- Git Shortcuts ---
alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -m'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'
alias glog='git log --oneline --graph --decorate -n 20'

# Launch custom git_gui (from myComputer) if available, otherwise launch gg or git status
alias gg='gitgui 2>/dev/null || python3 ~/Documents/GitHub/myComputer/git_gui.py 2>/dev/null || git status'

# --- Directory Quick Jumps ---
alias cdmylinux='cd ~/Documents/GitHub/myLinux'
alias cdcomp='cd ~/Documents/GitHub/myComputer'
alias cdpyscreen='cd ~/Documents/GitHub/myPyScreencast'
alias cdsoc='cd ~/Documents/GitHub/mySOC'

# --- System Synchronization & Updates ---
alias mylinux-sync='~/Documents/GitHub/myLinux/scripts/sync.sh'
alias mylinux-update='~/Documents/GitHub/myLinux/scripts/sync.sh --update'
