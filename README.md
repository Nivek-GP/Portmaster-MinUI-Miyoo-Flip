<div align="center">
  <h1>PortMaster for MinUI — Miyoo Flip</h1>
  <p>PortMaster Emu Pak for <a href="https://github.com/shauninman/MinUI">MinUI</a> on the <strong>Miyoo Flip</strong> — browse, install, and launch ports directly from the MinUI interface.</p>
  <img src="https://img.shields.io/badge/device-Miyoo%20Flip-blue" alt="Device">
  <img src="https://img.shields.io/badge/based%20on-minui--portmaster%20by%20ben16w-grey" alt="Based on">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</div>

> Based on [minui-portmaster](https://github.com/ben16w/minui-portmaster) v2.12.0 by ben16w, heavily adapted for the `my355` platform. Bundles [PortMaster](https://portmaster.games/) 2025.03.03-0141.

## Features

| Feature | Description |
| --- | --- |
| **PortMaster GUI** | Full access to the PortMaster browser — browse, install, update, and manage ports on-device |
| **MinUI integration** | Installed ports appear as entries in the MinUI Ports menu and launch directly |
| **Manual installs** | Ports copied by hand onto the SD card appear in both the MinUI menu and PortMaster's Manage Installed Ports |
| **Controller layout swap** | A marker file toggles between Xbox and Nintendo A/B/X/Y layout for SDL GameController games and the GUI itself |

## Download

Go to the [Releases page](https://github.com/Nivek-GP/Portmaster-MinUI-Miyoo-Flip/releases) and download the latest `PORTS.pak.zip`.

## Installation

1. Mount your SD card to your computer.
2. Download `PORTS.pak.zip` from the [Releases page](https://github.com/Nivek-GP/Portmaster-MinUI-Miyoo-Flip/releases).
3. Copy it to `/Emus/my355/` on the SD card and extract in place, then delete the zip.
4. Confirm that `/Emus/my355/PORTS.pak/launch.sh` exists.
5. Create a folder at `/Roms/Ports (PORTS)/`.
6. Create an empty file named `0) Portmaster.sh` inside that folder.
7. Eject the SD card and reinsert it into the device.

> **First launch** unpacks ~80 MB of files — expect 5–10 minutes. Subsequent launches are fast.

## Usage

From MinUI, go to **Ports** and select **0) Portmaster** to open the PortMaster GUI. Browse and install available ports. Installed ports appear as entries under Ports.

> Some ports require additional files from a purchased game copy. See each port's page on [portmaster.games](https://portmaster.games/games.html) for details.

### Controller layout

The Miyoo Flip's physical buttons are labeled Nintendo-style (A on the right, B on the bottom). To map A/B/X/Y to those labels in games and the GUI:

1. Create an empty file named `nintendo` (any extension, case-insensitive) inside `/.userdata/my355/PORTS-portmaster/` on your SD card.

| Marker present | Physical A | Physical B |
| --- | --- | --- |
| Yes (Nintendo) | SDL A — confirm | SDL B — back |
| No (Xbox, default) | SDL B — back | SDL A — confirm |

Applies to SDL GameController games (Celeste, Stardew Valley) and the PortMaster GUI. LOVE2D ports that link the Miyoo system SDL2 (e.g. Balatro) are unaffected — they always use Xbox-style layout due to a system-SDL2 quirk.

### Manually-installed ports

Ports copied directly to the SD card appear in the MinUI Ports menu and launch correctly. They are also listed in **PortMaster → Manage Installed Ports** because `launch.sh` syncs wrappers into the directory pugwash scans before the GUI starts.

## Tested games

| Game | Status | Notes |
| --- | --- | --- |
| Balatro | ✅ Works | LOVE2D. Always uses Xbox A/B layout (see above). First launch ~30s while assets repack |
| Celeste | ✅ Works | First launch 5–15 min while assets ASTC-compress. Honors layout marker |
| Half-Life | ✅ Works | xash3d engine. Requires Steam `valve/` files copied in |
| Stardew Valley | ✅ Works | Steam **compatibility branch** required (Mono, not .NET 6). First launch ~30s |
| Undertale | ✅ Works | First launch ~30s while assets repack. Steam Windows files accepted |
| Papers Please | ❌ Blocked | Requires Weston runtime, which hardcodes `/roms/ports/PortMaster` — unwritable on MinUI's read-only rootfs |
| TBOI: Rebirth | ❌ Blocked | Same Weston runtime blocker |

Any port whose `port.json` lists `"runtime": ["weston_pkg_*.squashfs"]` is currently unsupported. Most other ports should work.

## Troubleshooting

- **Log file**: `/.userdata/my355/logs/PORTS.txt` — includes pugwash output, shell script trace, and the port's stderr.
- **Per-port logs**: many ports write `log.txt` inside their `.ports/<portname>/` directory.
- If a port stops working after an update: **PortMaster → Manage Ports → select the port → Reinstall**.
- For general PortMaster support, visit the [NextUI Discord](https://discord.gg/HKd7wqZk3h) — **Standalone PortMaster** channel.

## Building from source

```sh
git clone https://github.com/Nivek-GP/Portmaster-MinUI-Miyoo-Flip.git
cd Portmaster-MinUI-Miyoo-Flip
make release-pak
```

Requires: `make`, `curl`, `zip`, `tar`, `jq` (standard Linux/macOS tools).
Output: `dist/PORTS.pak.zip`

## Credits

- [ben16w](https://github.com/ben16w) — original [minui-portmaster](https://github.com/ben16w/minui-portmaster)
- [justjoseorg](https://github.com/justjoseorg) — initial my355 adaptation
- [PortMaster team](https://portmaster.games/) — the port manager itself
- [josegonzalez](https://github.com/josegonzalez) — minui-presenter binary for my355

## Related

- [MinUI — Miyoo Flip Enhanced](https://github.com/Nivek-GP/MinUI-Miyoo-Flip-Enhanced) — unofficial MinUI fork with input lag reduction, cheat support, and QoL improvements
- [CHTSync](https://github.com/Nivek-GP/CHTSync) — desktop app to auto-download `.cht` cheat files for your ROM collection
- [ArtSync](https://github.com/Nivek-GP/ArtSync) — desktop app to auto-download boxart for your ROM collection
- [minui-portmaster](https://github.com/ben16w/minui-portmaster) — upstream project this is based on
- [PortMaster](https://portmaster.games/) — the port manager itself
