#!/bin/bash
# encodeLinux.sh
#
# Transcode DVD discs into format m4v for Plex media server
#
# Workflow:
#   1. Encode locally in fast SSD staging folder (saves wear and speeds up transcode)
#   2. Automatically fetch .en.srt subtitles using movie_Scraper
#   3. If duplicate exists in library, keep the new rip work saved locally
#   4. If no duplicate exists, move .m4v and .srt files to library to free local disk space
#   5. Eject disc and wait for next disc
#
# Dependencies:
#   HandBrakeCLI            (e.g., sudo apt install handbrake-cli)
#   eject                   (standard Linux eject utility)
#   blkid / isoinfo / lsblk (for reading DVD volume label)
#   Fast 480p30.json        (HandBrake preset file in common/bin)
#   jobStat.sh              (progress indicator in common/bin)
#   fetch_subtitles.py      (automated subtitle download in common/bin)
#
# Usage:
#   encodeLinux.sh [source_device] [staging_folder] [library_folder]
#
# Defaults:
#   source:         /dev/sr0
#   staging folder: $HOME/Videos/encodeLinux
#   library folder: /media/daveg/Lib/Movies (set to 'none' to keep all in staging)

# Resolve canonical script directory through symlinks
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source device, local staging folder, and final library destination
SRC="${1:-/dev/sr0}"
if [[ "$SRC" != /* ]]; then
    SRC="/dev/$SRC"
fi
STAGE_DIR="${2:-$HOME/Videos/encodeLinux}"
LIB_DIR="${3:-/media/daveg/Lib/Movies}"

die() {
    echo -en "$0: $1" >&2
    exit ${2:-1}
}

msg() {
    echo -en "$0: $1" >&2
}

eject_drive() {
    command eject "$1" 2>/dev/null
}

play_single_beep() {
    # Ensure system audio is unmuted
    pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null

    local sound_file=""
    if [ -f "/usr/share/sounds/freedesktop/stereo/bell.oga" ]; then
        sound_file="/usr/share/sounds/freedesktop/stereo/bell.oga"
    elif [ -f "/usr/share/sounds/freedesktop/stereo/message.oga" ]; then
        sound_file="/usr/share/sounds/freedesktop/stereo/message.oga"
    elif [ -f "/usr/share/sounds/freedesktop/stereo/complete.oga" ]; then
        sound_file="/usr/share/sounds/freedesktop/stereo/complete.oga"
    fi

    if [ -n "$sound_file" ]; then
        if command -v paplay >/dev/null 2>&1; then
            timeout 2 paplay --volume=65536 "$sound_file" 2>/dev/null &
        elif command -v pw-play >/dev/null 2>&1; then
            timeout 2 pw-play --volume=1.0 "$sound_file" 2>/dev/null &
        elif command -v aplay >/dev/null 2>&1; then
            timeout 2 aplay "$sound_file" 2>/dev/null &
        fi
    fi

    # Single terminal bell
    printf '\7'
}

play_alert_sound() {
    # Ensure system audio is unmuted (Success alert: 3 beeps / chime)
    pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null

    local sound_file=""
    if [ -f "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga" ]; then
        sound_file="/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
    elif [ -f "/usr/share/sounds/freedesktop/stereo/complete.oga" ]; then
        sound_file="/usr/share/sounds/freedesktop/stereo/complete.oga"
    elif [ -f "/usr/share/sounds/freedesktop/stereo/bell.oga" ]; then
        sound_file="/usr/share/sounds/freedesktop/stereo/bell.oga"
    fi

    if [ -n "$sound_file" ]; then
        if command -v paplay >/dev/null 2>&1; then
            timeout 3 paplay --volume=65536 "$sound_file" 2>/dev/null &
        elif command -v pw-play >/dev/null 2>&1; then
            timeout 3 pw-play --volume=1.0 "$sound_file" 2>/dev/null &
        elif command -v aplay >/dev/null 2>&1; then
            timeout 3 aplay "$sound_file" 2>/dev/null &
        fi
    fi

    # 3 terminal bells for success
    printf '\7\7\7'
}

play_failure_sound() {
    # Ensure system audio is unmuted (Failure sequence: fail -> success -> fail -> success -> fail)
    pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null

    local fail_file=""
    if [ -f "/usr/share/sounds/freedesktop/stereo/dialog-error.oga" ]; then
        fail_file="/usr/share/sounds/freedesktop/stereo/dialog-error.oga"
    elif [ -f "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga" ]; then
        fail_file="/usr/share/sounds/freedesktop/stereo/dialog-warning.oga"
    elif [ -f "/usr/share/sounds/freedesktop/stereo/suspend-error.oga" ]; then
        fail_file="/usr/share/sounds/freedesktop/stereo/suspend-error.oga"
    fi

    local success_file=""
    if [ -f "/usr/share/sounds/freedesktop/stereo/complete.oga" ]; then
        success_file="/usr/share/sounds/freedesktop/stereo/complete.oga"
    elif [ -f "/usr/share/sounds/freedesktop/stereo/bell.oga" ]; then
        success_file="/usr/share/sounds/freedesktop/stereo/bell.oga"
    fi

    # Play sequence in background: fail -> success -> fail -> success -> fail
    (
        play_clip() {
            local f="$1"
            if [ -n "$f" ] && [ -f "$f" ]; then
                if command -v paplay >/dev/null 2>&1; then
                    paplay --volume=65536 "$f" 2>/dev/null
                elif command -v pw-play >/dev/null 2>&1; then
                    pw-play --volume=1.0 "$f" 2>/dev/null
                elif command -v aplay >/dev/null 2>&1; then
                    aplay "$f" 2>/dev/null
                fi
            fi
        }

        play_clip "$fail_file"
        play_clip "$success_file"
        play_clip "$fail_file"
        play_clip "$success_file"
        play_clip "$fail_file"
    ) &

    # Terminal bell sequence (5 pulses)
    for _ in 1 2 3 4 5; do
        printf '\7'
        sleep 0.2
    done
}

# Locate HandBrakeCLI
if command -v HandBrakeCLI >/dev/null 2>&1; then
    HANDBRAKE_CLI="HandBrakeCLI"
elif [ -x "${SCRIPT_DIR}/HandBrakeCLI" ]; then
    HANDBRAKE_CLI="${SCRIPT_DIR}/HandBrakeCLI"
elif [ -x "${BIN_DIR}/HandBrakeCLI" ]; then
    HANDBRAKE_CLI="${BIN_DIR}/HandBrakeCLI"
elif [ -x "$HOME/bin/HandBrakeCLI" ]; then
    HANDBRAKE_CLI="$HOME/bin/HandBrakeCLI"
else
    HANDBRAKE_CLI="HandBrakeCLI"
fi

# Locate preset file with full path resolution
PRESET_NAME="Fast 480p30.json"
PRESET=""
if [ -f "$PRESET_NAME" ]; then
    PRESET="$(cd "$(dirname "$PRESET_NAME")" && pwd)/$(basename "$PRESET_NAME")"
elif [ -f "${SCRIPT_DIR}/${PRESET_NAME}" ]; then
    PRESET="${SCRIPT_DIR}/${PRESET_NAME}"
elif [ -f "${BIN_DIR}/${PRESET_NAME}" ]; then
    PRESET="${BIN_DIR}/${PRESET_NAME}"
elif [ -f "$HOME/bin/${PRESET_NAME}" ]; then
    PRESET="$HOME/bin/${PRESET_NAME}"
elif [ -f "$HOME/Documents/GitHub/myLinux/common/bin/${PRESET_NAME}" ]; then
    PRESET="$HOME/Documents/GitHub/myLinux/common/bin/${PRESET_NAME}"
elif [ -f "$HOME/Documents/GitHub/movie_Scraper/${PRESET_NAME}" ]; then
    PRESET="$HOME/Documents/GitHub/movie_Scraper/${PRESET_NAME}"
elif [ -f "$HOME/Documents/GitHub/myComputer/${PRESET_NAME}" ]; then
    PRESET="$HOME/Documents/GitHub/myComputer/${PRESET_NAME}"
elif [ -f "/media/daveg/Lib/${PRESET_NAME}" ]; then
    PRESET="/media/daveg/Lib/${PRESET_NAME}"
fi
[ -z "$PRESET" ] && die "Preset file $PRESET_NAME not found.\n"

# Minimum file size test for success
SIZE_TEST=512000c

# Locate fetch_subtitles script
FETCH_SUBS_SCRIPT=""
if [ -f "${SCRIPT_DIR}/fetch_subtitles.py" ]; then
    FETCH_SUBS_SCRIPT="${SCRIPT_DIR}/fetch_subtitles.py"
elif [ -f "${BIN_DIR}/fetch_subtitles.py" ]; then
    FETCH_SUBS_SCRIPT="${BIN_DIR}/fetch_subtitles.py"
elif [ -f "$HOME/bin/fetch_subtitles.py" ]; then
    FETCH_SUBS_SCRIPT="$HOME/bin/fetch_subtitles.py"
elif command -v fetch_subtitles.py >/dev/null 2>&1; then
    FETCH_SUBS_SCRIPT="$(command -v fetch_subtitles.py)"
elif [ -f "$HOME/Documents/GitHub/movie_Scraper/fetch_subtitles.py" ]; then
    FETCH_SUBS_SCRIPT="$HOME/Documents/GitHub/movie_Scraper/fetch_subtitles.py"
fi

# Locate jobStat script
JOBSTAT_SCRIPT=""
if [ -x "${SCRIPT_DIR}/jobStat.sh" ]; then
    JOBSTAT_SCRIPT="${SCRIPT_DIR}/jobStat.sh"
elif [ -x "${BIN_DIR}/jobStat.sh" ]; then
    JOBSTAT_SCRIPT="${BIN_DIR}/jobStat.sh"
elif [ -x "$HOME/bin/jobStat.sh" ]; then
    JOBSTAT_SCRIPT="$HOME/bin/jobStat.sh"
elif command -v jobStat.sh >/dev/null 2>&1; then
    JOBSTAT_SCRIPT="$(command -v jobStat.sh)"
fi

# Time to wait between attempts (seconds)
SLEEP_TIME=5

# Function to check if physical media is present in drive
is_media_present() {
    local dev="$1"
    if /usr/lib/udev/cdrom_id "$dev" 2>/dev/null | grep -q "^ID_CDROM_MEDIA=1"; then
        return 0
    fi
    if udevadm info -q property -n "$dev" 2>/dev/null | grep -q "^ID_CDROM_MEDIA=1"; then
        return 0
    fi
    return 1
}

# Function to get volume label from disc
get_volume_name() {
    local dev="$1"
    local name=""

    # 1. Try blkid
    name=$(blkid -c /dev/null -o value -s LABEL "$dev" 2>/dev/null | tr -d '\r\n')

    # 2. Try isoinfo
    if [ -z "$name" ] && command -v isoinfo >/dev/null 2>&1; then
        name=$(isoinfo -d -i "$dev" 2>/dev/null | grep -i "^Volume id:" | cut -d: -f2- | tr -d '\r\n')
    fi

    # 3. Try lsblk
    if [ -z "$name" ] && command -v lsblk >/dev/null 2>&1; then
        name=$(lsblk -no LABEL "$dev" 2>/dev/null | tr -d '\r\n')
    fi

    # 4. Try udevadm
    if [ -z "$name" ] && command -v udevadm >/dev/null 2>&1; then
        name=$(udevadm info -q property -n "$dev" 2>/dev/null | grep '^ID_FS_LABEL=' | cut -d= -f2- | tr -d '\r\n')
    fi

    # Clean leading and trailing whitespace
    name=$(echo "$name" | sed -e 's/^[[:blank:]]*//' -e 's/[[:blank:]]*$//')
    echo "$name"
}

# Ensure staging directory exists
mkdir -p "$STAGE_DIR" 2>/dev/null || die "Staging folder $STAGE_DIR could not be created.\n"

# Clear screen so easy to review in progress
clear

echo "=== encodeLinux.sh ==="
echo "Source:          $SRC"
echo "Output (local):  $STAGE_DIR"
echo "Library (final): $LIB_DIR"
echo "Preset:          $PRESET"
echo "HandBrake:       $HANDBRAKE_CLI"
[ -n "$FETCH_SUBS_SCRIPT" ] && echo "Subtitle fetch:  $FETCH_SUBS_SCRIPT"
echo "Waiting for disc in $SRC..."
echo "======================"

# Main loop
last_completed_disc=''
while [ true ]; do
    if ! is_media_present "$SRC"; then
        # Disc removed or drive tray open; reset tracker so newly inserted disc will process
        last_completed_disc=''
        sleep "$SLEEP_TIME"
        continue
    fi

    # Physical media is present in the drive
    RAW_VOL=$(get_volume_name "$SRC")

    # If the disc has no volume label or blkid returned empty
    if [ -z "$RAW_VOL" ]; then
        if /usr/lib/udev/cdrom_id "$SRC" 2>/dev/null | grep -q "^ID_CDROM_MEDIA_STATE=blank"; then
            RAW_VOL="BLANK_OR_UNREADABLE_DISC"
        else
            RAW_VOL="UNLABELLED_DISC"
        fi
    fi

    # If the same disc that just finished is still in the drive, wait without re-ripping
    if [ "$RAW_VOL" = "$last_completed_disc" ]; then
        echo -en "."
        sleep "$SLEEP_TIME"
        continue
    fi

    echo "Found disc: preliminary scan returned '$RAW_VOL'"
    NAM="$RAW_VOL"

    # Check if preliminary title contains a 4-digit date in parentheses, e.g. "Title (2020)"
    while ! [[ "$NAM" =~ \([0-9]{4}\) ]]; do
        echo ""
        echo "=========================================================================="
        echo "Preliminary scan of disc returned title: '$NAM'"
        echo "Title does not contain a 4-digit year in parentheses, e.g. 'Gladiator (2000)'"
        echo "=========================================================================="
        play_single_beep
        read -r -p "Enter movie title with year (or 'e' to eject, 'q' to quit): " user_title
        if [ "$user_title" = "e" ] || [ "$user_title" = "E" ]; then
            eject_drive "$SRC"
            last_completed_disc="$RAW_VOL"
            NAM=""
            break
        elif [ "$user_title" = "q" ] || [ "$user_title" = "Q" ]; then
            echo "Exiting."
            exit 0
        fi

        user_title="$(echo "$user_title" | sed -e 's/^[[:blank:]]*//' -e 's/[[:blank:]]*$//')"
        if [[ "$user_title" =~ \([0-9]{4}\) ]]; then
            NAM="$user_title"
            break
        else
            echo "Invalid title: '$user_title' must have a 4-digit year in parentheses like 'Title (YYYY)'. Please try again."
        fi
    done

    if [ -z "$NAM" ]; then
        sleep "$SLEEP_TIME"
        continue
    fi

    echo "Using title: NAM=$NAM"
    DEST_LIB=""
    if [ -n "$LIB_DIR" ] && [ "$LIB_DIR" != "none" ] && [ "$LIB_DIR" != "local" ]; then
        DEST_LIB="${LIB_DIR}/${NAM}.m4v"
    fi

    # Check local staging target: avoid overwriting existing local files
    if [ -f "${STAGE_DIR}/${NAM}.m4v" ]; then
        DEST_LOCAL="${STAGE_DIR}/${NAM}_$(date +%Y%m%d_%H%M%S).m4v"
        echo "Existing local file found. Using unique local destination: $DEST_LOCAL"
    else
        DEST_LOCAL="${STAGE_DIR}/${NAM}.m4v"
    fi

    if [ -n "$DEST_LIB" ] && [ -f "$DEST_LIB" ]; then
        msg "NOTICE($SRC): '$NAM.m4v' already exists in library ($LIB_DIR). New rip will be saved locally in $STAGE_DIR.\n"
    fi

    clear
    # Run HandBrake
    if [ -n "$JOBSTAT_SCRIPT" ] && [ -x "$JOBSTAT_SCRIPT" ]; then
        "$JOBSTAT_SCRIPT" "  $SRC: $NAM\n" &
        stat_id=$!
        echo "spawned $stat_id"
        trap 'kill $stat_id 2>/dev/null' EXIT INT TERM
    else
        stat_id=''
    fi

    sleep 2  # To allow stdout of HandBrakeCLI to start
    echo "running $HANDBRAKE_CLI --main-feature --preset-import-file \"$PRESET\" --subtitle none -i $SRC -o $DEST_LOCAL"
    "$HANDBRAKE_CLI" --main-feature --preset-import-file "$PRESET" --subtitle none -i "$SRC" -o "$DEST_LOCAL"
    handbrake_failure=$?

    find "$DEST_LOCAL" -type f -size +"$SIZE_TEST" 2>/dev/null
    size_test_failure=$?

    if [ -n "$stat_id" ]; then
        kill "$stat_id" 2>/dev/null
        trap - EXIT INT TERM
    fi

    if [ $handbrake_failure -eq 0 ] && [ $size_test_failure -eq 0 ]; then
        eject_drive "$SRC"
        play_alert_sound
        msg "\n\nMSG($SRC): Movie $NAM successfully encoded to $DEST_LOCAL\n"

        # Automatically fetch external .srt subtitles using movie_Scraper
        if [ -n "$FETCH_SUBS_SCRIPT" ] && [ -f "$FETCH_SUBS_SCRIPT" ]; then
            echo "Attempting to fetch subtitles using ($FETCH_SUBS_SCRIPT)..."
            python3 "$FETCH_SUBS_SCRIPT" "$DEST_LOCAL"
        fi

        # Handle destination: if duplicate exists in library, keep new rip work locally
        local_base="${DEST_LOCAL%.*}"
        if [ "$LIB_DIR" = "none" ] || [ "$LIB_DIR" = "local" ] || [ -z "$LIB_DIR" ]; then
            msg "\nOutput preserved in $STAGE_DIR (library move disabled).\n"
            echo "Video file: $DEST_LOCAL"
            for srt in "${local_base}"*.srt; do
                [ -f "$srt" ] && echo "Subtitle file: $srt"
            done
        elif [ -n "$DEST_LIB" ] && [ -f "$DEST_LIB" ]; then
            msg "\n[!] DUPLICATE IN LIBRARY: '$DEST_LIB' already exists.\n"
            msg "[!] Preserving new rip work locally in $STAGE_DIR without overwriting library.\n"
            echo "Video kept locally: $DEST_LOCAL"
            for srt in "${local_base}"*.srt; do
                [ -f "$srt" ] && echo "Subtitle kept locally: $srt"
            done
        elif [ -n "$LIB_DIR" ] && [ -d "$LIB_DIR" ]; then
            echo "Moving files to library: $LIB_DIR"
            mv -v "$DEST_LOCAL" "$LIB_DIR/"
            for srt in "${local_base}"*.srt; do
                if [ -f "$srt" ]; then
                    mv -v "$srt" "$LIB_DIR/"
                fi
            done
            echo "Local disk space freed in $STAGE_DIR."
        else
            msg "\nWARN: Library directory $LIB_DIR is not accessible. Retaining file in $STAGE_DIR.\n"
        fi

        last_completed_disc="$RAW_VOL"
    else
        play_failure_sound
        msg "\nWARN($SRC): HandBrake failed (exit=$handbrake_failure) or output too small (size test exit=$size_test_failure). Look at $NAM to investigate. Leaving disk in drive.\n\nPress any key when ready to continue with checking..."
        while [ true ]; do
            read -t 3 -n 1
            if [ $? -eq 0 ]; then
                echo ""
                break
            else
                echo -en "."
            fi
        done
        last_completed_disc="$RAW_VOL"
    fi
    msg "\n\nMSG($SRC): Movie $NAM finished.\nInsert a new disk...\n"

    # Skips to here if drive not available or while waiting
    sleep "$SLEEP_TIME"
done
