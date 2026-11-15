# FreeOrion Godot 4 client

Godot 4.4 and up based rewrite of the GiGi client, tries to be pixel precise as much as possible.

See `client/godot4/` for C++ GDExtension code.


## Fork direction

This fork redesigns the Godot 4 client instead of reproducing GiGi pixel for pixel.
The plan is in [`doc/UI_OVERHAUL_PLAN.md`](../doc/UI_OVERHAUL_PLAN.md). In short:

- **Desktop-first.** Windows, macOS and Linux, 1280×720 minimum, mouse and keyboard first.
- **GL Compatibility renderer only.** Every shader must work under it.
- **Godot version** is pinned in [`.godot-version`](.godot-version) and read by CI.
- **Keep upstream merges cheap:**
  - New work lives in `shell/`, `ui/`, `map/`, `screens/` and `panels/`.
  - Upstream's root-level scenes (`IntroScreen`, `MapWnd`, `CUI*`, ...) are not edited.
  - The app starts from `shell/Shell.tscn` (`run/main_scene`). The shell has its own title, galaxy setup and options screens, and plays the game in `shell/GameShell.gd`. Upstream's IntroScreen and MapWnd are no longer used by this flow; `UpstreamAdapters` only matters if they are opened directly.
  - Changes to `client/godot4/` stay minimal and generic.
