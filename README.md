# Beyond Apocalypse

Beyond Apocalypse 1.0.8 for Drive Beyond Horizons Steam build 26106988.

[Downloads and release notes](https://github.com/lionlord513/beyond-apocolypse-private/releases/tag/v1.0.8).
The public ZIP supports Beyond Mod Manager; the Nexus ZIP uses the game-folder layout.
Mod Manager is optional. Launch the game through Steam.

Gameplay source and original assets are in `mod/BasicM4`. Packages map that
source to `Mods/BeyondApocalypse`, with an inert legacy migration stub.
Installation, controls, credits and validation limits are in `release/`.
Personal companion tools and local state are excluded from this repository.

Lua regressions are in `tests/` (Lua 5.4). `build_release.py` assembles and checks
the distributable archives from the source, pinned runtime and original Hornet source.
Recovered native helper DLLs are retained unchanged; their original C++ source
was not available in the recovered source tree.
