# Beyond Mod Manager 1.0.9

Source for the Windows release of Beyond Mod Manager (BMM).

BMM installs and manages Drive Beyond Horizons mod ZIPs. It can enable,
disable and remove mods, preserve settings during updates, and check for updates when
the mod author provides an update source. Beyond Apocalypse is optional.

Version 1.0.9 verifies the tested UE4SS runtime during every mod installation
and update, repairing incompatible or partial installations from its verified
bundled files. It checks for manager updates on every launch and prompts when
a newer public release is available. Uninstall removes the full managed mod
folder, including generated data and settings, with a recovery copy kept outside
the mod loader. Reinstall starts fresh; game saves and shared support stay installed.

Start with [BUILDING.txt](BUILDING.txt) to build the manager.
[REVIEW-NOTES.txt](REVIEW-NOTES.txt) lists the main code and bundled dependencies.

This branch contains BMM, its public artwork/catalogue, build tools and tests.
It does not contain the game or the Beyond Apocalypse gameplay mod.
