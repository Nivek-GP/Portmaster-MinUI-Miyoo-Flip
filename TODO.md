# TODO

## ✅ DONE

Tagged milestones (in order):

- `working-baseline` — apps run, screen on, no face buttons yet
- `buttons-working` — joy_type=-1 + miyoo_inputd restart makes face buttons reach SDL2
- `awake-fix` — `--disable-auto-sleep` on minui-presenter + bundled libpixman; no more standby during gameplay
- `layout-swap-working` — `nintendo*` marker file flips Xbox/Nintendo A/B X/Y for SDL_GameController games
- `five-games-working` — Balatro, Celeste, Half-Life, Stardew Valley, Undertale all confirmed. Includes the critical cleanup safety fix (rmdir not rm -rf) that ended the port-wipe regressions
- `gui-safe` — PortMaster GUI confirmed safe to open + exit; quick wins (Balatro sed noise silenced, large runtime squashfs skipped in `process_squashfs_files`)
- `gui-integration` — Pugwash "Manage Installed Ports" now lists manually-installed ports (wrapper sync into ports_dir before pugwash launches); controller layout selection unified so PortMaster GUI itself respects the `nintendo` marker too

---

## 🚧 Remaining backlog

### F. Pre-launch UX overlay during first-run cold extract

**Effort**: 1-2 hours. **Value**: medium — only matters on the *first* launch of each port, but really matters then.

On first launch of certain ports, the screen goes black for an extended period while the port script silently processes game files:
- **Balatro**: ~30s while 7z extracts globals.lua, sed-patches it, repackages
- **Celeste**: 5-15 min while `celeste-repacker` ASTC-compresses every PNG
- **Stardew**: ~30s while Mono cold-starts and MMLoader patches

Currently launch.sh's `show_message "Starting <port>..." 5` fires before the port script runs. After the 5s timer the screen stays black until the game produces its first frame.

Fix: keep a `minui-presenter --message "Extracting game data, this may take several minutes..." --timeout -1 &` alive past the show_message timeout. Two implementation options:
1. **Per-port wrapper around `bash $ROM_PATH`** that starts the presenter, execs the port, then `killall minui-presenter` when the port's binary actually starts (detected via `pgrep` for known binary names or via a marker file the port creates).
2. **Universal**: always keep the presenter alive until some condition (port log file appears? a process appears in pgrep?). Less precise but simpler.

Option 2 is probably fine for a first pass — kill the presenter when any non-launch.sh child process of the port script appears, or after a generous timeout (e.g. 5 min).

### G. Brightness restore on game exit

**Effort**: 20 min. **Value**: low if no actual dimming observed.

Logs sometimes show `SetRawBrightness(0)` during the gptokeyb2 libinterpose exit handler. If this reaches the kernel sysfs, minui's menu inherits the dimmed brightness when control returns. Steps:
1. **First**: confirm with user whether the minui menu actually appears dimmer after exiting a game. Without that confirmation, this is a non-issue.
2. If yes: identify the brightness sysfs path on Miyoo Flip (`/sys/class/backlight/backlight/brightness` or similar — minui's main launch.sh sets it at boot, check there).
3. Capture default value before launch.sh runs (save to `$USERDATA_PATH/PORTS-portmaster/brightness.txt` like we do for CPU governor), restore in `cleanup()`.

### Z. Weston runtime squashfs patching (Papers Please, TBOI: Rebirth)

**Effort**: 4+ hours. **Value**: medium — unlocks ~2-3 ports.

The Weston runtime (`weston_pkg_0.2.squashfs`) bundles a `westonwrap.sh` that hardcodes `controlfolder=/roms/ports/PortMaster` and sources `control.txt` from there. On minui:
- We can't symlink `/roms/ports/PortMaster` (rootfs is read-only)
- Our `export controlfolder` is clobbered by westonwrap.sh's local assignment

The only viable fix is to patch westonwrap.sh inside the squashfs:
1. Mount the runtime squashfs (read-only)
2. Copy contents to a writable temp dir
3. sed-patch westonwrap.sh's hardcoded path → `$controlfolder` or `$EMU_DIR`
4. mksquashfs the patched dir back into the runtime
5. Replace the original

Has to be done on the device (squashfs tools are aarch64 only in our PAK). Adds significant boot time on first run. Likely OK to skip unless someone really wants Papers Please.

---

## 🔒 Out of scope

- **Try ports blindly** — wait for a specific port someone wants. Otherwise it's chasing unknowns.
- **Stardew/Celeste cold-boot slowness** — Mono JIT on 4-core ARM. Can't fix without rebuilding the runtime.
- **LOVE2D layout swap** — Balatro's love.aarch64 links the Miyoo system libSDL2 which doesn't honor `SDL_GAMECONTROLLERCONFIG_FILE` for the Xbox 360 GUID family. Would require bundling our own libSDL2.

---

## Tags ladder

```
working-baseline    → apps run, screen on, no face buttons
buttons-working     → + face buttons (joy_type=-1)
awake-fix           → + no standby + libpixman bundled
layout-swap-working → + Xbox/Nintendo layout marker file
five-games-working  → + cleanup safety, 5 ports confirmed
gui-safe            → + GUI safe, sed noise gone, large squashfs skipped
gui-integration     → + Manage Installed Ports populated; GUI respects marker
```

Return to any point: `git checkout <tag>` (detached HEAD) or `git reset --hard <tag>` (move master).
