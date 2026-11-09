# Beyond Mod Manager 1.0.11

Install, update, enable and remove Drive Beyond Horizons mods.

Open BMM, choose your game folder if needed, then select a mod or use **Add ZIP**. Close the game before installing or updating. BMM checks for manager and supported mod updates when it opens.

Use **Settings > repair Mod** to repair the shared UE4SS support files. Uninstall removes the selected mod, its settings and generated data, and keeps a recovery copy in Backups. Game saves and shared UE4SS files remain installed.

## Changes

### 1.0.11
- Shortened descriptions, help and update messages.
- Renamed Repair mod support to repair Mod.

### 1.0.10
- Downloads retry after temporary server errors, including HTTP 504.
- Fixed stalled updates and update failures in some PowerShell environments.
- Added Retry update when a manager download fails.

### 1.0.9
- Added automatic UE4SS repair during mod installs and updates.
- Added startup prompts for manager updates.
- Uninstall now removes the full managed mod folder and keeps a recovery copy.

See BUILDING.txt to build the manager and REVIEW-NOTES.txt for source details.
