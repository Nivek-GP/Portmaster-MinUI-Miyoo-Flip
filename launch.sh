#!/bin/sh
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"
[ -f "$USERDATA_PATH/PORTS-portmaster/debug" ] && set -x

rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt"
exec 2>&1

echo "$0" "$*"
cd "$PAK_DIR" || exit 1
mkdir -p "$USERDATA_PATH/PORTS-portmaster"
mkdir -p "$SHARED_USERDATA_PATH/PORTS-portmaster"

export PAK_DIR="$SDCARD_PATH/Emus/$PLATFORM/PORTS.pak"
export EMU_DIR="$SDCARD_PATH/Emus/$PLATFORM/PORTS.pak/PortMaster"
# Export controlfolder so subprocesses inside runtime squashfs files
# (e.g. weston_pkg's westonwrap.sh) find our actual PortMaster path.
export controlfolder="$EMU_DIR"
# Some port runtime scripts (weston_pkg's westonwrap.sh, Solarus, etc.) hardcode
# /roms/ports/PortMaster as the control folder path rather than reading
# $controlfolder. Create a symlink so the hardcoded path resolves to our actual
# PortMaster dir. Silently no-ops on read-only rootfs.
if mkdir -p /roms/ports 2>/dev/null; then
    ln -snf "$EMU_DIR" /roms/ports/PortMaster 2>/dev/null && \
        echo "Symlinked /roms/ports/PortMaster -> $EMU_DIR" || \
        echo "Failed to create /roms/ports/PortMaster symlink"
else
    echo "Cannot create /roms/ports (rootfs not writable)"
fi

export PATH="$EMU_DIR:$PAK_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$PAK_DIR/lib:$LD_LIBRARY_PATH"
export SSL_CERT_FILE="$PAK_DIR/files/ca-certificates.crt"
export SDL_GAMECONTROLLERCONFIG_FILE="$EMU_DIR/gamecontrollerdb.txt"
export PYSDL2_DLL_PATH="$PAK_DIR/lib:/usr/lib:/usr/lib/aarch64-linux-gnu:/lib:/lib/aarch64-linux-gnu"
export HOME="$SHARED_USERDATA_PATH/PORTS-portmaster"
export XDG_DATA_HOME="$HOME/.local/share"
mkdir -p "$XDG_DATA_HOME"

[ -z "$1" ] && exit 1
ROM_PATH="$1"
ROM_DIR="$(dirname "$ROM_PATH")"
ROM_NAME="$(basename "$ROM_PATH")"
TEMP_DATA_DIR="$SDCARD_PATH/.ports_temp"
PORTS_DIR="$ROM_DIR/.ports"

export HM_TOOLS_DIR="$PAK_DIR"
export HM_PORTS_DIR="$TEMP_DATA_DIR/ports"
export HM_SCRIPTS_DIR="$TEMP_DATA_DIR/ports"

# shellcheck disable=SC2317
cleanup() {
    rm -f /tmp/stay_awake

    # Restore keyboard mode so minui menu navigation works (minui reads
    # gpio-keys-polled which only fires in joy_type=0 mode).
    if [ -f /sys/class/miyooio_chr_dev/joy_type ]; then
        echo 0 > /sys/class/miyooio_chr_dev/joy_type
    fi
    # Mirror OG kill_apps.sh: kill miyoo_inputd on PAK exit so the next
    # launch starts a fresh inputd.
    killall miyoo_inputd 2>/dev/null || true

    if [ -f "$USERDATA_PATH/PORTS-portmaster/cpu_governor.txt" ]; then
        cat "$USERDATA_PATH/PORTS-portmaster/cpu_governor.txt" \
            >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        rm -f "$USERDATA_PATH/PORTS-portmaster/cpu_governor.txt"
    fi
    if [ -f "$USERDATA_PATH/PORTS-portmaster/cpu_min_freq.txt" ]; then
        cat "$USERDATA_PATH/PORTS-portmaster/cpu_min_freq.txt" \
            >/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
        rm -f "$USERDATA_PATH/PORTS-portmaster/cpu_min_freq.txt"
    fi
    if [ -f "$USERDATA_PATH/PORTS-portmaster/cpu_max_freq.txt" ]; then
        cat "$USERDATA_PATH/PORTS-portmaster/cpu_max_freq.txt" \
            >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
        rm -f "$USERDATA_PATH/PORTS-portmaster/cpu_max_freq.txt"
    fi

    lsof +f -- "$TEMP_DATA_DIR/ports" | awk 'NR>1 {print $2}' | xargs -r kill -9 2>/dev/null || true
    # DO NOT use rm -rf here. Busybox umount on FAT32 can return success while
    # the bind mount is still effective — rm -rf would then follow the bind
    # into $ROM_DIR/.ports and recursively wipe every installed port (we hit
    # this exactly: all 5 ports nuked between sessions). Use rmdir which only
    # removes empty directories — bulletproof against a stale bind.
    umount "$TEMP_DATA_DIR/ports" 2>/dev/null || umount -l "$TEMP_DATA_DIR/ports" 2>/dev/null || true
    rmdir "$TEMP_DATA_DIR/ports" 2>/dev/null
    rmdir "$TEMP_DATA_DIR" 2>/dev/null
}

show_message() (
    message="$1"
    seconds="$2"

    if [ -z "$seconds" ]; then
        seconds="forever"
    fi

    killall minui-presenter >/dev/null 2>&1 || true
    echo "$message" 1>&2
    if [ "$seconds" = "forever" ]; then
        minui-presenter --disable-auto-sleep --message "$message" --timeout -1 &
    else
        minui-presenter --disable-auto-sleep --message "$message" --timeout "$seconds"
    fi
)

# Swap the active gamecontrollerdb.txt between Xbox and Nintendo layouts.
# Both ship in files/ and already contain the MIYOO Player1 GUID with the
# appropriate A/B X/Y mapping for each layout. Modeled on ben16w upstream.
set_controller_layout() {
    layout="$1"
    case "$layout" in
        nintendo|xbox) ;;
        *)
            echo "set_controller_layout: invalid '$layout' (use 'nintendo' or 'xbox')"
            return 1
            ;;
    esac
    src="$PAK_DIR/files/gamecontrollerdb_$layout.txt"
    if [ ! -f "$src" ]; then
        echo "set_controller_layout: $(basename "$src") not found"
        return 1
    fi
    echo "Applying $layout controller layout"
    cp -f "$src" "$EMU_DIR/gamecontrollerdb.txt"
}

create_busybox_wrappers() {
    bin_dir="$PAK_DIR/bin"
    echo "Creating busybox wrappers in $bin_dir"
    if [ ! -x "$bin_dir/busybox" ]; then
        echo "Error: $bin_dir/busybox not found or not executable"
        return 1
    fi

    for cmd in $("$bin_dir/busybox" --list); do
        if [ "$cmd" = "sh" ]; then
            continue
        fi

        if [ ! -e "$bin_dir/$cmd" ] || grep -q 'exec .*/busybox .*\$@' "$bin_dir/$cmd"; then
            cat > "$bin_dir/$cmd" <<EOF
#!/bin/sh
exec $PAK_DIR/bin/busybox $cmd "\$@"
EOF
            chmod +x "$bin_dir/$cmd"
        fi
    done
}

copy_artwork() {
    if [ -f "$USERDATA_PATH/PORTS-portmaster/no-artwork" ]; then
        echo "Artwork disabled."
        find "$ROM_DIR/.media" -name '*.png' -type f -delete
        return
    fi

    for dir in "$PORTS_DIR"/*/; do
        [ -d "$dir" ] || continue
        port_json="$dir/port.json"
        [ -f "$port_json" ] || continue
        artwork_file="$dir/cover.png"
        if [ ! -f "$artwork_file" ]; then
            screenshot_candidate=$(find "$dir" -maxdepth 1 -type f -name 'screenshot*' | head -n1)
            if [ -n "$screenshot_candidate" ]; then
                artwork_file="$screenshot_candidate"
            else
                continue
            fi
        fi

        echo "Processing folder $dir for artwork"
        shell_script=$(jq -r '.items[] | select(test("\\.sh$"))' "$port_json" | head -n1)
        if [ -z "$shell_script" ] || [ "$shell_script" = "null" ]; then
            echo "No shell script found in $port_json"
            continue
        fi

        mkdir -p "$ROM_DIR/.media"
        dest_file="$ROM_DIR/.media/${shell_script%.*}.png"
        if [ ! -f "$dest_file" ]; then
            echo "Copying $dir/cover.png to $ROM_DIR/.media/$shell_script.png"
            cp "$artwork_file" "$dest_file"
        fi
    done
}

unpack_tar() {
    tar_file="$1"
    dest_dir="$2"
    echo "Unpacking $1 to $2"
    if [ ! -f "$tar_file" ]; then
        echo "$tar_file not found"
        return
    fi
    if gunzip -c "$tar_file" | tar -xf - -C "$dest_dir"; then
        rm -f "$tar_file"
    else
        echo "Failed to unpack $tar_file"
        return 1
    fi
}

unzip_pylibs() {
    pylibs_file="$1"
    echo "Unzipping $1"
    if [ ! -f "$pylibs_file" ]; then
        echo "$pylibs_file not found"
        return
    fi
    if unzip -oq "$pylibs_file" -d "$(dirname "$pylibs_file")"; then
        rm -f "$pylibs_file"
    else
        echo "Failed to unpack $pylibs_file"
        return 1
    fi
}

update_file_shebang() {
    file="$1"
    echo "Updating shebang for $file"
    if [ ! -f "$file" ]; then
        echo "$file not found"
        return 1
    fi
    first_line=$(head -n 1 "$file")
    if [ "$first_line" = "#!/bin/bash" ]; then
        tail -n +2 "$file" > "$file.tmp"
        echo "#!/usr/bin/env bash" > "$file.new"
        cat "$file.tmp" >> "$file.new"
        mv "$file.new" "$file"
        chmod +x "$file"
        rm -f "$file.tmp"
    else
        echo "No need to update shebang for $file"
    fi
}

update_shebangs_from_list() {
    while IFS= read -r file || [ -n "$file" ]; do
        [ -z "$file" ] && continue
        update_file_shebang "$file"
    done
}

replace_strings_in_files() {
    old_string="$1"
    new_string="$2"
    while IFS= read -r file || [ -n "$file" ]; do
        [ -z "$file" ] && continue
        echo "Replacing '$old_string' with '$new_string' in $file"
        python3 "$PAK_DIR/src/replace_string_in_file.py" "$file" "$old_string" "$new_string"
    done
}

find_shell_scripts() {
    search_path="$1"
    find "$search_path" -type f -executable \
        \( -name "*.sh" -o -name "*.src" -o -name "*.txt" -o ! -name "*.*" \) \
        | while read -r file; do
        if head -n 1 "$file" | grep -qE '^#!.*(sh|bash)'; then
            echo "$file"
        fi
    done
}

modify_squashfs_scripts() {
    squashfs_file="$1"
    tmpdir=$(mktemp -d) || return 1

    echo "Modifying scripts in $squashfs_file"
    if ! unsquashfs -no-progress -d "$tmpdir" "$squashfs_file"; then
        echo "Failed to extract squashfs"
        rm -rf "$tmpdir"
        return 1
    fi

    shell_scripts=$(find_shell_scripts "$tmpdir")
    if ! echo "$shell_scripts" | grep -q .; then
        echo "No shell scripts found in $squashfs_file"
        rm -rf "$tmpdir"
        return 0
    fi
    echo "$shell_scripts" | update_shebangs_from_list
    echo "$shell_scripts" | replace_strings_in_files "/roms/ports/PortMaster" "$EMU_DIR"

    echo "Rebuilding squashfs file $squashfs_file"
    rm -f "$squashfs_file"
    if ! mksquashfs "$tmpdir" "$squashfs_file" -noappend -comp xz -no-progress; then
        echo "Failed to rebuild squashfs"
        rm -rf "$tmpdir"
        return 1
    fi

    rm -rf "$tmpdir"
}

process_squashfs_files() {
    search_dir="$1"

    echo "Processing SquashFS files in $search_dir"
    find "$search_dir" -type f -name "*.squashfs" | while IFS= read -r squashfs_file; do
        processed_marker="${squashfs_file}.processed"

        if [ -f "$processed_marker" ]; then
            if [ "$squashfs_file" -ot "$processed_marker" ]; then
                echo "Skipping $squashfs_file; already processed"
                continue
            fi
        fi

        # Skip large runtime squashfs files. They are third-party runtimes
        # (Mono ~262 MB, Weston ~55 MB) that don't need our shebang/path
        # patching and extracting them fills /tmp on the device. Port-bundled
        # squashfs files are typically <10 MB; runtimes are 50+ MB.
        size_bytes=$(stat -c %s "$squashfs_file" 2>/dev/null || echo 0)
        if [ "$size_bytes" -gt 52428800 ]; then
            echo "Skipping large runtime squashfs $squashfs_file ($((size_bytes / 1024 / 1024)) MB)"
            touch "$processed_marker"
            continue
        fi

        echo "Processing $squashfs_file"
        if modify_squashfs_scripts "$squashfs_file"; then
            sleep 2
            touch "$processed_marker"
        else
            echo "Failed to process $squashfs_file"
        fi
    done
}

replace_progressor_binaries() {
    search_path="$1"
    progressor_src="$PAK_DIR/files/progressor"
    presenter_src="$PAK_DIR/files/minui-presenter"

    if [ ! -f "$progressor_src" ]; then
        echo "Source progressor binary not found at $progressor_src"
        return 1
    fi

    if [ ! -f "$presenter_src" ]; then
        echo "Source minui-presenter binary not found at $presenter_src"
        return 1
    fi

    find "$search_path" -type f -name "progressor" | while read -r target; do
        echo "Replacing $target with $progressor_src"
        cp -f "$progressor_src" "$target"
        chmod +x "$target"
        presenter_target="$(dirname "$target")/minui-presenter"
        if [ ! -f "$presenter_target" ]; then
            echo "Copying $presenter_src to $presenter_target"
            cp -f "$presenter_src" "$presenter_target"
            chmod +x "$presenter_target"
        fi
    done
}

main() {
    echo "1" >/tmp/stay_awake
    trap "cleanup" EXIT INT TERM HUP QUIT

    show_message "Starting, please wait..." forever

    # Move Weston GPU package to PortMaster libs on first run
    if [ -f "$PAK_DIR/files/weston_pkg_0.2.squashfs" ]; then
        echo "Moving weston_pkg_0.2.squashfs to $EMU_DIR/libs"
        mkdir -p "$EMU_DIR/libs"
        mv -f "$PAK_DIR/files/weston_pkg_0.2.squashfs" "$EMU_DIR/libs/"
        touch "$EMU_DIR/libs/weston_pkg_0.2.squashfs"
    fi

    if [ -f "$PAK_DIR/files/bin.tar.gz" ] || [ -f "$PAK_DIR/files/lib.tar.gz" ]; then
        show_message "Unpacking files, please wait..." forever
        unpack_tar "$PAK_DIR/files/bin.tar.gz" "$PAK_DIR/bin"
        unpack_tar "$PAK_DIR/files/lib.tar.gz" "$PAK_DIR/lib"
    fi

    if [ ! -f "$PAK_DIR/bin/busybox_wrappers.processed" ]; then
        if create_busybox_wrappers; then
            touch "$PAK_DIR/bin/busybox_wrappers.processed"
        fi
    fi

    if [ ! -f "$EMU_DIR/config/config.json" ]; then
        echo "Copying config.json to $EMU_DIR/config"
        mkdir -p "$EMU_DIR/config"
        cp -f "$PAK_DIR/files/config.json" "$EMU_DIR/config/config.json"
    fi

    mkdir -p "$ROM_DIR/.ports"
    if ! mount | grep -q "on $TEMP_DATA_DIR/ports type"; then
        echo "Mounting $ROM_DIR/.ports to $TEMP_DATA_DIR/ports"
        mkdir -p "$TEMP_DATA_DIR/ports"
        if ! mount -o bind "$ROM_DIR/.ports" "$TEMP_DATA_DIR/ports"; then
            echo "Failed to mount $ROM_DIR/.ports to $TEMP_DATA_DIR/ports"
            exit 1
        fi
    else
        echo "Mount point $TEMP_DATA_DIR/ports already exists, skipping mount."
    fi

    unzip_pylibs "$EMU_DIR/pylibs.zip"
    # Fix PySDL2 _finds_libs_at_path to handle colon-separated PYSDL2_DLL_PATH
    python3 "$PAK_DIR/src/fix_dll_py.py" "$EMU_DIR/exlibs/sdl2/dll.py"
    # Patch PortMaster's hardcoded Roms/PORTS path to our actual ROM_DIR
    python3 "$PAK_DIR/src/replace_string_in_file.py" \
        "$EMU_DIR/pylibs/harbourmaster/platform.py" "/mnt/SDCARD/Roms/PORTS" "$ROM_DIR"
    # Guard os.path.samefile() against missing target_file on first install
    python3 "$PAK_DIR/src/replace_string_in_file.py" \
        "$EMU_DIR/pylibs/harbourmaster/platform.py" \
        "if not os.path.samefile(port_script, target_file):" \
        "if not target_file.exists() or not os.path.samefile(port_script, target_file):"
    # Stub out portmaster_install() so our control.txt isn't clobbered
    python3 "$PAK_DIR/src/disable_python_function.py" \
        "$EMU_DIR/pylibs/harbourmaster/platform.py" portmaster_install
    # Remap 'miyoo' platform to PlatformBase: avoids WANT_XBOX_FIX and Miyoo Mini paths
    python3 "$PAK_DIR/src/replace_string_in_file.py" \
        "$EMU_DIR/pylibs/harbourmaster/platform.py" \
        "'miyoo':     PlatformMiyoo," \
        "'miyoo':     PlatformBase,"

    cp -f "$PAK_DIR/files/control.txt" "$EMU_DIR/control.txt"
    python3 "$PAK_DIR/src/replace_string_in_file.py" "$EMU_DIR/control.txt" \
        "\$EMU_DIR" "$EMU_DIR"
    python3 "$PAK_DIR/src/replace_string_in_file.py" "$EMU_DIR/control.txt" \
        "\$TEMP_DATA_DIR" "$TEMP_DATA_DIR"

    # Use the Miyoo-compatible gptokeyb2 (newer versions break Miyoo Flip input)
    cp -f "$PAK_DIR/files/gptokeyb2.miyoo" "$EMU_DIR/gptokeyb2"
    chmod +x "$EMU_DIR/gptokeyb2"

    # gamecontrollerdb.txt is now applied via set_controller_layout() at launch time
    # so the user can switch between Xbox and Nintendo layouts via a marker file.
    # Both files/gamecontrollerdb_{xbox,nintendo}.txt already contain the MIYOO Player1
    # GUID (030000005e0400008e02000014010000) with the appropriate A/B X/Y swap.

    # Dump all input devices for diagnostics (vendor/product/name/events)
    echo "=== INPUT DEVICES ==="
    cat /proc/bus/input/devices 2>/dev/null
    echo "=== END INPUT DEVICES ==="

    # OG stock OS runs runmiyoo.sh at boot which sets joy_type=-1 (joypad mode)
    # and starts miyoo_inputd. minui does not, so we replicate it here. Without
    # joy_type=-1, face buttons (A/B/X/Y/L/R/L2/R2) arrive on a keyboard evdev
    # node and never reach SDL2 via the MIYOO Player1 virtual joystick.
    if [ -f /sys/class/miyooio_chr_dev/joy_type ]; then
        echo "Setting joy_type=-1 (joypad mode) — mirrors runmiyoo.sh line 75"
        echo -1 > /sys/class/miyooio_chr_dev/joy_type
        # Kill any miyoo_inputd started in keyboard mode so it reinitializes
        # against the joypad-mode kernel driver.
        if pgrep -x miyoo_inputd > /dev/null 2>&1; then
            killall miyoo_inputd 2>/dev/null || true
            sleep 0.3
        fi
        # Default all turbo flags off (matches a fresh stock-OS settings with
        # turbo*=0). miyoo_inputd reads these on startup.
        mkdir -p /tmp/miyoo_inputd
        for _b in a b x y l r l2 r2; do
            rm -f "/tmp/miyoo_inputd/turbo_$_b"
        done
        unset _b
    fi

    # Start miyoo_inputd if not running — creates virtual Xbox 360 joystick from button events
    if ! pgrep -x miyoo_inputd > /dev/null 2>&1; then
        echo "miyoo_inputd NOT running, searching..."
        for _miy in /customer/app/miyoo_inputd /customer/bin/miyoo_inputd \
                    /usr/miyoo/app/miyoo_inputd /usr/miyoo/bin/miyoo_inputd \
                    /usr/miyoo/miyoo_inputd /usr/bin/miyoo_inputd; do
            if [ -x "$_miy" ]; then
                echo "Starting miyoo_inputd from $_miy"
                "$_miy" &
                sleep 1
                break
            fi
        done
        echo "miyoo_inputd search results:"
        find /customer /usr/miyoo /usr/bin /usr/local -name 'miyoo_inputd' 2>/dev/null | while read -r _f; do
            echo "  found: $_f (executable=$([ -x "$_f" ] && echo Y || echo N))"
        done
    else
        echo "miyoo_inputd already running (pid=$(pgrep -x miyoo_inputd))"
    fi

    # Controller layout selection applies uniformly to PortMaster GUI and to
    # game ports. Drop a file named 'nintendo*' (case-insensitive) into
    # $USERDATA_PATH/PORTS-portmaster/ to switch A/B X/Y to Nintendo positions
    # (matches the labels printed on the Miyoo Flip's physical buttons and the
    # pugwash GUI's on-screen prompts like "A to select / B to back"). Absent
    # marker = Xbox layout.
    nintendo_file=$(find "$USERDATA_PATH/PORTS-portmaster" -maxdepth 1 -iname 'nintendo*' -type f 2>/dev/null | head -n1)
    if [ -n "$nintendo_file" ]; then
        set_controller_layout nintendo
    else
        set_controller_layout xbox
    fi

    if echo "$ROM_NAME" | grep -qi "portmaster"; then
        echo "Starting PortMaster GUI"
        # Auto-register manually-installed wrappers so pugwash's load_ports()
        # marks them "Installed" not "Broken". Pugwash scans ports_dir (.ports/
        # via bind mount) and walks each port.json's items[]; if a wrapper
        # listed in items isn't present in ports_dir, the port is flagged
        # broken and hidden from "Manage Installed Ports". On minui our
        # wrappers live in $ROM_DIR (for menu visibility), so we sync copies
        # into $TEMP_DATA_DIR/ports/ for pugwash's discovery pass.
        for _wrap_src in "$ROM_DIR"/*.sh; do
            [ -f "$_wrap_src" ] || continue
            _wrap_name=$(basename "$_wrap_src")
            case "$_wrap_name" in
                "0) Portmaster.sh") continue ;;
            esac
            _wrap_dst="$TEMP_DATA_DIR/ports/$_wrap_name"
            if [ ! -e "$_wrap_dst" ] || ! cmp -s "$_wrap_src" "$_wrap_dst" 2>/dev/null; then
                if cp -f "$_wrap_src" "$_wrap_dst" 2>/dev/null; then
                    echo "Synced wrapper for pugwash discovery: $_wrap_name"
                fi
            fi
        done
        unset _wrap_src _wrap_name _wrap_dst
        show_message "Starting PortMaster..." 10 &
        rm -f "$EMU_DIR/.pugwash-reboot"

        while true; do
            pugwash --debug

            if [ ! -f "$EMU_DIR/.pugwash-reboot" ]; then
                break
            fi

            rm -f "$EMU_DIR/.pugwash-reboot"
        done

        show_message "Applying changes, please wait..." &
        find_shell_scripts "$ROM_DIR" | update_shebangs_from_list
        find_shell_scripts "$ROM_DIR" | replace_strings_in_files "/roms/ports/PortMaster" "$EMU_DIR"
        replace_progressor_binaries "$PORTS_DIR"
        copy_artwork
        process_squashfs_files "$EMU_DIR/libs"
    else
        echo "Starting port: $ROM_PATH"
        update_file_shebang "$ROM_PATH"
        python3 "$PAK_DIR/src/replace_string_in_file.py" "$ROM_PATH" "/roms/ports/PortMaster" "$EMU_DIR"
        # Neutralize the malformed sed in upstream Balatro.sh line 55 (single
        # quotes nested inside single-quoted sed → 'sed: bad option in
        # substitution expression' log noise on every Balatro launch).
        python3 "$PAK_DIR/src/replace_string_in_file.py" "$ROM_PATH" \
            "sed -i 's/s/shadows = 'On'/shadows = 'Off'/g' globals.lua" \
            ": # noop: neutralized upstream's broken sed quoting"
        # Foreground 5s timer: minui-presenter must exit BEFORE the port runs.
        # It polls SDL events even when backgrounded, so an alive presenter
        # intercepts D-pad input during gameplay and briefly redraws over the
        # game. Match ben16w upstream's exit-before-launch pattern.
        show_message "Starting ${ROM_NAME%.*}..." 5
        killall minui-presenter >/dev/null 2>&1 || true
        "$PAK_DIR/bin/busybox" bash "$ROM_PATH"
    fi
}

main "$@"
