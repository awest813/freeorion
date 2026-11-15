# FreeOrion Graphics / UI / UX Overhaul — Audit & Plan

Status: proposal · Date: 2026-11-15 · Scope: human client (graphics, UI, UX). Server, AI, and FOCS content are out of scope except where the UI needs new data from them.

---

## 1. Executive summary

FreeOrion currently has **three** client UI stacks:

| Stack | Where | State |
|---|---|---|
| GiGi (GG) + SDL2 + OpenGL 2.0 fixed-function | `GG/` (~21k LOC), `UI/` (~61k LOC), `client/human/` | The shipping client. Feature-complete, but on an obsolete rendering model, with no high-DPI support and hand-placed pixel layout. |
| Godot 3 (GDNative) | `godot/`, `client/godot/` | Dead end. GDNative doesn't exist in Godot 4. Still built in Ubuntu, Docker, and Android CI. |
| Godot 4 (GDExtension) | `godot4/`, `client/godot4/` | Active since late Oct 2026, one main contributor. About 230 lines of GDScript and 919 lines of C++, roughly 2% of the GG feature surface. Its stated goal is to be "pixel precise" with GG. |

**Decision (§3):** do the overhaul **in the Godot 4 client, in this fork**, desktop-first, on the **GL Compatibility** renderer. In this fork, the Godot 4 client's goal changes from "pixel-precise clone of GG" to "**design-system-first rebuild that keeps GG's gameplay feature set**". GG gets maintenance only (crash fixes and a few cheap wins) until Godot 4 reaches parity, then it is retired.

A redesign of the GG stack would mean rewriting its renderer (GL 2 fixed-function, `GL_QUADS`, a 72-DPI glyph atlas without shaping or fallback), adding a layout engine to about 1,000 manual `MoveTo`/`Resize` calls, and adding DPI scaling, focus navigation, and touch. Godot 4 already provides all of that: Theme, Containers, HarfBuzz shaping, font fallback, MSDF fonts, `content_scale_factor`, focus neighbours, gamepad and touch input, shaders, MultiMesh, and Android export. The project is already moving there.

**The critical path is not visual. It's the bridge.** The Godot 4 GDExtension exposes only the turn number and the single-player flag. Universe data is mutated on a network thread with no synchronisation. Until the bridge exposes game state safely and accepts orders, no screen can be designed against real data. Phase 1 below is therefore mostly C++.

---

## 2. Audit findings

### 2.1 Legacy GG client: rendering

- **Context:** SDL2 with a GL **2.0** context and no profile (`UI/SDLGUI.cpp:254`). GLEW is used. `GLInit` enables fixed-function lighting and the matrix stack (`SDLGUI.cpp:306-334`).
- **Drawing:** client-side vertex arrays with `glDrawArrays(GL_QUADS…)`, about 145 call sites, the most in `GG/src/DrawUtil.cpp`, `UI/CUIControls.cpp`, and `UI/MapWnd.cpp`. VBOs are optional, through `GG::GLClientAndServerBuffer`. `GL_QUADS` and fixed-function are not available in a core profile, so moving to GL 3.3 core, Vulkan, or Metal is a rewrite.
- **Shaders:** a single GLSL 1.10 program, used only for scanlines (`UI/ShaderProgram.cpp`, `default/shaders/scanlines.frag`).
- **Text:** FreeType at a fixed 72 DPI (`GG/src/Font.cpp:3300`).
  - One `GL_LUMINANCE_ALPHA` atlas per font and size, capped at 1024 px wide.
  - No kerning, no shaping, no fallback fonts, no SDF.
  - Glyph sets are pre-rasterised from the stringtables' charsets.
  - Text vertex buffers are rebuilt on render (comment at `Font.cpp:2860`).
- **High-DPI:** none. There is no `SDL_WINDOW_ALLOW_HIGHDPI`, no drawable-size query, and no UI scale option. The only scaling controls are `ui.font.size` (4–40 pt) and the map icon sizes.

### 2.2 Legacy GG client: styling and layout

- **Theming:** no theme system. There are about 47 `*.color` options read through static `ClientUI::*Color()` accessors (`UI/ClientUI.cpp:78-112`). `CUIStyle` is just a control factory.
- **Hard-coded values:** about 218 literal colours, about 400 file-level numeric constants (pads, widths, sizes), and about 161 inline `X(n)`/`Y(n)` literals. Only about 89 sizes are font-relative.
- **Layout:** `GG::Layout` exists but has only about 25 uses, 10 of them in `OptionsWnd`. Everything else is manual: 33 `DoLayout()` and 45 `SizeMove()` overrides, plus about 1,044 move/resize calls. This is why large fonts clip.
- **Asset paths:** about 213 hard-coded `ArtDir() / "…"` paths across 24 UI files.

### 2.3 Legacy GG client: UX surface

- **Size:** the largest units are `MapWnd` (7.9k LOC), `DesignWnd` (5.0k), `EncyclopediaDetailPanel` (4.7k), `SidePanel` (4.1k), `FleetWnd` (3.9k), and `ObjectListWnd` (3.0k).
- **Debt:** 126 TODO/FIXME/HACK markers, concentrated in SidePanel, MapWnd, Encyclopedia, and FleetWnd. One example is fleet-window cleanup done inside `Render()` (`MapWnd.cpp:1726`).
- **Window model:** a floating-window desktop (CUIWnd) with per-window, per-video-mode position persistence. DesignWnd and ResearchWnd are opaque full-screen windows, and the map stops rendering while they are open.
- **Tooltips:** about 151 call sites across five separate BrowseWnd classes. Delay handling is re-applied by hand.
- **Galaxy map:** world-space GL transform, with stars, lanes, and fields batched into VBOs. System icons and fleet buttons are GG **widgets** repositioned by hand on every zoom (`MapWnd.cpp:4774-4886`). Fleet move lines and ETA text are rebuilt every frame. There is no culling, only zoom-threshold hiding.
- **Accessibility:**
  - No colourblind or high-contrast mode, although empire, meter, and tech status are colour-coded.
  - No keyboard focus traversal (focus follows the mouse). Hotkeys, rebindable, are the only keyboard path.
  - No RTL, BiDi, or CJK support.
- **Input:** mouse and keyboard only. No gamepad, touch, or gestures.

### 2.4 Godot 4 client

- **Engine and renderer:** Godot 4.4 baseline with the **GL Compatibility** renderer on both desktop and mobile. Base viewport is 1280×800. DPI scaling in `IntroScreen.gd:12-18` uses fixed steps of 1.0, 1.35, and 1.75.
- **Screens:**
  - IntroScreen: partial. Only QuickStart, MultiPlayer, Credits, and Exit are wired.
  - MapWnd: a turn button only, with **no galaxy rendering**.
  - ServerConnectWnd: a player-name field only.
  - CreditsWnd: an empty stub.
- **Styling:** 11 `StyleBoxFlat` resources hand-copied from GG's colours. There is **no `Theme` resource**, and colours are hard-coded rather than read from OptionsDB.
- **Bridge** (`client/godot4/FreeOrionNode.cpp`):
  - Methods: version and paths, turn number, single-player flag, start network and parsing threads, new SP game, `start_turn`, and seven `options_*` wrappers.
  - Signals: `parsing_completed`, `start_game`, `turn_update`.
  - Only six message types are handled. Everything else logs "Not implemented".
  - There is no multiplayer connect, save/load, or orders, and no universe, empire, fleet, or tech access.
- **Threading:** `HandleMessage` mutates Universe and Empires **on the network thread with no mutex**. Signals are deferred to the main thread, but any getter called from GDScript would race with turn updates. This has to be fixed before any data is exposed.
- **Platforms:** export presets exist only for Linux and Android. CI builds Windows and macOS binaries but has no export presets for them.
- **CI Godot versions:** 4.4.1 on Windows, 4.7.2 on Android, and 4.4 as the project baseline.
- **Tests:** one GUT integration test (quickstart, one turn).

### 2.5 Godot 3 client (`godot/`)

- **Had:** game setup, MP join and auth, chat, an error dialog, a 3D galaxy map (orbit camera, `AStar` lane graph, `GodotSystem`/`GodotFleet` wrappers), and a full `FOStdTheme.tres`.
- **Worth carrying over (as ideas, not code):** the wrapper-object pattern, the camera controller, and AStar picking.
- **Not worth carrying over:** its lane rendering, which uses `ImmediateGeometry` rebuilt every frame, and its practice of emitting signals from the network thread.

### 2.6 Art, fonts, strings, and audio (`default/data`)

- **Art:** 146 MB, all PNG, with no vector sources.
  - **Mixed sizes within categories:** species icons are 64 or 66 px, tech icons 128, 124, or 64, building icons 64, 128, or 256, and policies 512×480, 512×512, or 512×768. Fleet icons are 62×64, 31×32, and 20×21.
  - **Oversized folders:** `hulls_design` (31 MB of 2000×1000 images) and `fields` (28 MB of 2048² images) together take 40% of the art budget.
  - **Probably unused:** about 297 of 1,009 icons appear unreferenced (heuristic). `stars/old_stars` and `icons/tech/unused` are legacy folders.
  - **Broken reference:** `scripting/species/species_macros/focus.py:94` references `icons/focus/stealth.png`, which does not exist (verified).
- **Planets:** 3D lit spheres from 512×256 equirectangular maps with cloud, citylight, and damage layers (`UI/SidePanel.cpp:390`). Asteroids are 3×256 pre-rendered frames (768 files).
- **Splash screens:** 1280×960 (4:3), with three seasonal variants chosen by date (`UI/IntroScreen.cpp:228-262`).
- **Fonts:** Roboto (default) and DejaVu.
  - Neither has CJK or Hangul.
  - Roboto lacks common UI symbols (→ ★ ✓).
  - There is no fallback chain.
- **Strings:** 13 languages and 5,169 English keys.
  - Coverage: ru 98%, fr 93%, de 44%, es 35%, and every other language 20% or less.
  - Custom inline markup (`<rgba>`, `<img>`, `<u>`, `<i>`, `<encyclopedia>`, `<url>`) and `[[KEY]]` macros will need converting to Godot rich text.
- **Audio:** 21 UI sounds, 20 combat sounds, and **one** music track.
- **Licence:** creative content is CC-BY-SA 3.0, and attribution exists only in aggregate (`credits.xml`). Any replacement art must be CC-BY-SA-compatible, and replacement fonts must be OFL or Apache.

---

## 3. Strategic decisions (resolved 2026-11-15)

1. **Where the overhaul lives: Godot 4.** GG is frozen to maintenance only.
2. **Fork, not upstream.** This fork redesigns the client rather than following upstream's "pixel-precise GG clone" goal.
   - **Merge discipline:** keep tracking upstream `master`. The `client/godot4/` bridge stays generic and close to upstream so their bridge work keeps merging cleanly. Bridge additions are written so they could be offered upstream later.
   - **Isolation:** all redesign work lives in *new* directories (`godot4/ui/`, `godot4/shell/`, `godot4/map/`, `godot4/screens/`, `godot4/panels/`). Upstream's root-level scenes (`IntroScreen.tscn`, `MapWnd.tscn`, `CUI*`) are replaced by pointing `run/main_scene` at our shell, not by editing them. This keeps merge conflicts confined to `project.godot`.
   - **No "Classic" theme.** Upstream's GG-matching StyleBoxes remain in the tree for their scenes, but we don't maintain a GG look-alike.
   - **Rebase cadence:** merge upstream at least every two weeks, and run the screenshot and GUT suites on each merge.
3. **Desktop-first.** Windows, macOS, and Linux are the design targets.
   - Minimum supported window size is 1280×720. Mouse and keyboard are primary, and gamepad is a stretch goal.
   - **Touch and Android are out of scope** for design. Upstream's Android CI keeps building because it arrives with merges, but layouts, budgets, and interaction design don't target it.
4. **Renderer: GL Compatibility only** (OpenGL 3.3 desktop / GLES3). There is no Forward+ tier.
   - Every effect (bloom, glow, territory fields, planet impostors) is done with `canvas_item` and `spatial` shaders that are valid under Compatibility.
   - This keeps integrated-GPU laptops and older Macs fully supported.
5. **Galaxy map dimension: 2D top-down.** Universe positions are 2D, and 2D is the cheapest path under the Compatibility renderer. 3D is used only inside sub-viewports (planet spheres, hull previews).
   - The Godot 3 3D map added camera complexity without adding gameplay information.

---

## 4. Design principles

1. **Tokens, not literals.** Every colour, spacing, radius, font size, and icon size comes from a design-token resource feeding one `Theme`. Zero pixel literals in scenes, enforced by lint (§7.3).
2. **Layout by containers.** Every screen is built from Godot Containers and must reflow from 1280×720 up to 4K at UI scales from 75% to 200%.
3. **Information first.** A 4X UI succeeds when the player can answer "what needs my attention this turn?" without opening five windows. Prefer persistent docked panels, inline actions, and drill-down over floating-window sprawl.
4. **Every colour-coded meaning has a second channel:** an icon, shape, pattern, or label. Colourblind palettes are themes, not afterthoughts.
5. **Keyboard and gamepad reachable.** Every interactive control participates in focus navigation, and hotkeys remain rebindable.
6. **The bridge is a product.** The GDExtension API is typed, documented, thread-safe, and tested, because every screen depends on it.
7. **Performance budgets are tests.** For example, the map holds 60 fps with 500 systems and 2,000 fleets on a mid-range desktop, and 30 fps on a reference integrated-GPU laptop.

---

## 5. Phased plan

The phases are ordered by dependency. Phases 3–5 overlap heavily once Phase 1 lands. The rough sizes assume 1–2 dedicated contributors; at upstream's current single-contributor pace, multiply them.

### Phase 0: Foundations and housekeeping (≈2–3 weeks)

- **Decisions:** record the §3 decisions (fork, desktop-first, GL Compatibility) in `godot4/README.md`, under a "Fork direction" section so upstream merges don't clobber it.
- **Fork scaffolding:**
  - Create the new directory skeleton (`ui/`, `shell/`, `map/`, `screens/`, `panels/`) and an empty `shell/Shell.tscn`.
  - Switch `run/main_scene` to the shell, leaving upstream's scenes untouched.
  - Document the upstream-merge procedure in `doc/`.
- **Godot version:** pin **one** Godot version for desktop CI, the project, and the API (today it is 4.4.1, 4.7.2, and 4.4). Use the newest stable release that runs the GUT suite on all three desktop OSes. Leave upstream's Android workflow alone.
- **Retire Godot 3:** remove the Godot 3 builds from the Ubuntu, Docker, and Android CI (`_build-ubuntu.yml`, `_build-docker.yml`, `_build-android.yml`). Delete `godot/` and `client/godot/`, or move them to an archive tag. Expect a small merge conflict if upstream later touches these files.
- **Export presets:** add Windows and macOS export presets next to the existing Linux one, so all three desktop platforms produce playable exports in CI.
- **Renderer setting:** set `rendering_method="gl_compatibility"` explicitly for the desktop override (it already is), and add a CI assertion that no shader uses Forward+-only features. The simplest assertion is that the headless Compatibility run loads every scene without shader errors.
- **Screenshot tests:** add a CI job that boots Godot headless (or under xvfb with `--rendering-driver opengl3`) and captures golden screenshots of each scene. This becomes the visual-regression net.
- **GG quick wins**, each a small change that helps today's players:
  - Add `SDL_WINDOW_ALLOW_HIGHDPI` and drawable-size handling, or at least a documented `ui.font.size` recommendation.
  - Fix the missing `icons/focus/stealth.png`.
  - Freeze GG feature work otherwise.

### Phase 1: Bridge v1, the critical path (≈6–8 weeks, mostly C++ in `client/godot4/`)

1. **Threading model.** Make the network thread only *receive and queue* messages. `FreeOrionNode::_process` drains the queue and calls `HandleMessage` on the main thread, so Universe and Empires are only ever touched on the main thread. This is simpler and safer than locking.
2. **Typed read-only views.** Add `RefCounted` wrappers registered with `ClassDB`: `FOSystem`, `FOPlanet`, `FOFleet`, `FOShip`, `FOBuilding`, `FOField`, `FOEmpire`, `FOSpecies`, `FOTech`, `FOPolicy`, `FOShipDesign`, `FOProductionQueue`, `FOResearchQueue`, `FOSitRep`, and `FOCombatLog`. They hold object IDs, not pointers, and resolve on access.
3. **Bulk map data.** For the renderer, add calls that return **packed arrays** rather than objects, for example `get_map_snapshot()` returning `PackedVector2Array` positions, `PackedColorArray` owner colours, lane index pairs, supply ranges, and fleet positions and headings. The map must not make 10k GDScript↔C++ calls per frame.
4. **Orders API.** Add `issue_fleet_move`, `issue_colonize`, `issue_invade`, `issue_scrap`, `issue_production_enqueue`/`reorder`/`remove`, `issue_research_enqueue`, `issue_focus_change`, `issue_policy_adopt`, `issue_design_create`, `issue_rename`, and `rescind_order`. Each returns a success flag and a reason string, so the UI can explain *why* an action is unavailable.
5. **Session and messaging.** Implement the missing message handlers: MP connect, join, and auth, lobby, chat, errors, diplomacy, save/load, end-game, and player status. Map each one to a signal.
6. **Options.** Replace the one-method-per-type option wrappers with a generic `get_option(name) -> Variant` and `set_option(name, value)`, plus a `option_changed` signal, and fill in the empty `GodotOptionsDB` singleton.
7. **Rich text.** Add a C++ converter from FreeOrion string markup (`<rgba>`, `<i>`, `<u>`, `<img>`, `<encyclopedia>`, `<url>`) to Godot BBCode, with `[url=fo://pedia/KEY]` links handled by `meta_clicked`.
8. **Tests.** Add GUT tests for each view and order (quickstart, issue a move, end turn, assert the position changed), plus an API reference doc generated from `_bind_methods`.

**Exit criteria:** a GDScript test can start a game, enumerate systems, planets, and fleets, move a fleet, queue production and research, end five turns, and save and load the game, all without data races (run under TSan in one CI job).

### Phase 2: Design system (≈3–4 weeks, can overlap Phase 1)

- **Tokens:** `godot4/ui/tokens.tres` defines the colour palette (surface, raised, overlay, accent, text-primary, text-secondary, positive, negative, warning, info), a spacing scale (4/8/12/16/24/32), radii, elevation, a type scale, icon sizes, and motion durations.
- **Theme:** `godot4/ui/theme/fo_default.tres`, generated from the tokens by a small editor script so themes stay consistent. Ship two themes:
  - **Default**, the new look.
  - **High-contrast.**

  There is no GG-matching "Classic" theme (fork decision, §3).
- **Colourblind support:** empire colour palettes for deuteranopia, protanopia, and tritanopia, with per-empire shape or glyph markers on the map.
- **Typography:**
  - Use MSDF fonts so text stays crisp at any scale.
  - Set up a fallback chain of Roboto → Noto Sans Symbols 2 → Noto Sans CJK (optional download) → DejaVu. All are OFL or Apache.
  - Godot's HarfBuzz text server gives shaping, kerning, and BiDi for free.
- **Component library**, each control a scene with GUT and screenshot tests:
  - Basic controls: Button (primary, secondary, ghost, danger), IconButton, Toggle, Slider, SpinBox, Dropdown, TabBar.
  - Windows and lists: a Window frame that is dockable, closable, and pinnable, a SearchField, and a VirtualList (recycled rows, for 1,000-row object lists).
  - Data display: MeterBar (current, target, projected), a ResourceChip (icon, value, delta), and a Tooltip host. The Tooltip host is one rich-tooltip system replacing all five BrowseWnds, and it supports pinning a tooltip.
  - Feedback and visuals: Toast/Notification, a ContextMenu, a DragSource/DropTarget mixin, and a GraphControl (line and area charts).
- **UI scale:** a continuous `ui.scale` option from 75% to 200% using `content_scale_factor` and `canvas_items` stretch, auto-detected from `DisplayServer.screen_get_scale()` and DPI. This replaces the fixed 1.0/1.35/1.75 steps.
- **Iconography:**
  - Commission or produce an **SVG** set for UI chrome and meter, resource, and action icons. Godot rasterises SVG at import scale, so these stay crisp at every DPI.
  - Normalise the raster content icons (techs, buildings, parts, species) to canonical sizes (64 and 128, plus 256 where used large) using a batch script, keeping the originals.

### Phase 3: Galaxy map renderer (≈6–8 weeks; this is the heart of the game)

Build it as a `Node2D` with `Camera2D` and smooth zoom (continuous, with easing, cursor-anchored), driven by the Phase 1 bulk snapshot. Layers, back to front:

1. **Background:** a parallax starfield (one `MultiMeshInstance2D`) and nebula and galaxy-gas sprites with additive blending.
2. **Overlays:** territory and supply as a **shader**. Use an SDF or Voronoi field over owner-tinted supply ranges with soft borders, replacing the hard supply circles and lines. Detection-range rings get a toggle.
3. **Fields:** ion storms and the like, as an animated shader on a quad with UV rotation, replacing the per-turn texture rotation. The "unexplored" scanline effect is ported as a shader.
4. **Starlanes:** one static `ArrayMesh` or `MultiMesh` of lane quads, with a shader for width, owner gradient, supply-flow animation, and lane-level-of-detail fading. The mesh is rebuilt only when lanes change.
5. **Stars:** a `MultiMeshInstance2D` per star class, with instance colour and a shader halo (bloom faked in the Compatibility renderer).
6. **Fleets:** a `MultiMesh` of fleet glyphs with owner colour and shape markers (for colourblind players) and aggressive/passive styling. Movement paths are a shader-animated dashed `Line2D` or mesh, and ETA labels are cached until the route changes.
7. **Labels:** system names and counts via a label pool with collision avoidance, faded by zoom level.
8. **Picking:** a spatial hash or `AStar2D` over systems and fleets, instead of per-widget hit testing.

**Interactions:**
- Hover previews, click to select, and right-click for a context menu (move here, colonise, invade, set rally point).
- Box-select fleets, drag a route with a preview path and ETA, and shift-click to add waypoints.
- Minimap.
- Keyboard pan and zoom, middle-drag pan, edge-scroll (an option), and gamepad cursor (stretch goal).
- Touch is out of scope (desktop-first, §3).

**Map modes**, a one-key toggle replacing scattered toggles: political, supply, detection, resource (industry/research heat), and threat.

**Performance tests:** generated 250-, 500-, and 1000-system galaxies in CI, asserting frame time.

**Exit criteria:** the full game loop can be played from the map: explore, move, colonise, fight, and end the turn, with visual parity or better against GG's MapWnd features (`MapWnd.cpp` toolbar list, 39 hotkeys).

### Phase 4: Core gameplay screens (≈12–16 weeks)

This phase also restructures the **window model**. The floating-window desktop becomes a **docked shell**:

- **Top bar:** empire resources with deltas, turn number and End Turn, and a readiness indicator.
- **Left rail:** screen switcher (Map, Production, Research, Design, Government, Pedia, Objects, Empires).
- **Right context panel:** whatever is selected (system, planet, fleet), replacing SidePanel and FleetWnd.
- **Bottom notifications:** the sitrep feed, where each item has a "Go to" action.
- **Floating windows:** kept as an *option*, as pinned or detached panels.

Order of work, following the gameplay loop:

1. **System and planet panel** (replaces SidePanel, 4.1k LOC, the highest TODO count):
   - Planet sphere via shader impostor: a quad with an equirectangular sampler, lighting, atmosphere, clouds, and citylights. It works in the Compatibility renderer and replaces the GL-lit spheres. Asteroids also become a shader instead of 768 frames.
   - Focus selector with projected-meter preview.
   - Buildings, specials, and defence summary.
2. **Fleet panel** (replaces FleetWnd and FleetButton): split, merge, and drag ships between fleets; aggression stance; per-ship detail; full combat-stat display, including the fighters-shot data that `FleetWnd.cpp:2964` notes is missing.
3. **Production** (replaces ProductionWnd, BuildDesignatorWnd, and QueueListBox): a filterable build catalogue, drag-reorder queue, per-item ETA and PP allocation bars, "where can I build this?" highlighting on the map, and quantity and blocksize controls.
4. **Research** (replaces TechTreeWnd and ResearchWnd): a zoomable tech graph using the same 2D camera tech as the map, with dependency highlighting on hover, a queue sidebar, and search. Keep the list view alternative.
5. **Ship designer** (replaces DesignWnd, 5k LOC): the hull view uses the 2000×1000 hull art, downscaled. Slot drag-and-drop, a live stat summary (attack, structure, speed, cost) with comparison to the currently selected design, validity reasons inline, and premade and saved designs.
6. **Government** (replaces GovernmentWnd): policy cards (the 512-px policy art is well suited to cards), slot categories, adoption cost and IP projection, and drag to adopt.
7. **End-turn readiness:** a check before ending the turn, listing idle fleets, empty queues, unspent PP or RP, and new planets without a focus. Each item is clickable, and the check can be dismissed.

### Phase 5: Secondary screens and flows (≈8–10 weeks)

- **Menus and setup:** IntroScreen redesign (widescreen splash; all three seasonal variants re-cut to 16:9 and 21:9), Galaxy setup with a live galaxy preview, the multiplayer lobby, server connect, and password/auth.
- **Save/load:** with thumbnails and turn/empire metadata.
- **Options:** search, categories, live preview, and per-option reset. Generated from OptionsDB metadata wherever possible, so new options appear automatically.
- **Pedia** (replaces EncyclopediaDetailPanel, 4.7k LOC): `RichTextLabel` and the BBCode converter, history, global search across all content, and "show on map" links.
- **Objects list:** a virtualised table with sortable columns, saved filters, and multi-select actions.
- **Other windows:** empire and player list, diplomacy, chat, and moderator tools.
- **Combat report:** a timeline and replay animation on the map renderer, plus a damage summary graphs tab.
- **In-game menu, plus onboarding:** contextual first-time hints that can be dismissed and are stored in options, and an optional guided first 10 turns.

### Phase 6: Polish, art, and cut-over (≈6–8 weeks, plus ongoing art)

- **Motion:** a 120–200 ms motion language (panel slide, hover lift, notification enter and exit) with a "reduce motion" option.
- **Audio:** re-map the 21 UI sounds through an `AudioBus` with UI, music, and combat sliders. Commission or source CC-BY-SA music, since only one track exists today.
- **Art pipeline:**
  - VRAM-compressed imports (S3TC/BPTC for desktop; under Compatibility, check that BPTC falls back cleanly on GPUs without it).
  - Downscale `hulls_design` and `fields`. Together they are 59 MB of 2K PNGs, which matters for VRAM on integrated GPUs (see the budget in §7.2).
  - Delete or archive the ~297 unreferenced icons after verification.
  - Add an `ATTRIBUTION.yaml` per asset folder to meet CC-BY-SA requirements beyond `credits.xml`.
- **Remaster passes:** priority is stars and halos, planet textures (1K/2K plus normal maps), and fleet glyphs (vector).
- **Localisation:**
  - A string-length overflow test that renders every screen in de and ru (the longest strings) and flags clipped labels.
  - Pseudo-localisation mode.
  - Optional CJK font pack.
- **Cut-over:** Godot 4 becomes the default client once the parity checklist (§6) is green. GG stays buildable behind `BUILD_CLIENT_GG=ON` for one release, then `GG/` and `UI/` are removed (about 82k LOC).

---

## 6. Parity checklist (gates the cut-over)

Track this as a GitHub project. Each GG window maps to one Godot 4 owner scene.

| GG unit | Godot 4 target | Phase |
|---|---|---|
| IntroScreen, About/Credits | `screens/Intro`, `screens/Credits` | 5 |
| GalaxySetupWnd | `screens/GalaxySetup` | 5 |
| ServerConnectWnd, MultiplayerLobbyWnd, PasswordEnterWnd | `screens/Connect`, `screens/Lobby` | 1 (data), 5 (UI) |
| MapWnd (+ SystemIcon, FleetButton, FieldIcon) | `map/GalaxyMap` | 3 |
| SidePanel (+ Population/Resource/Military/Buildings/Specials panels) | `panels/SystemPanel`, `panels/PlanetPanel` | 4 |
| FleetWnd | `panels/FleetPanel` | 4 |
| ProductionWnd, BuildDesignatorWnd, QueueListBox | `screens/Production` | 4 |
| ResearchWnd, TechTreeWnd(+Layout/Arcs) | `screens/Research` | 4 |
| DesignWnd | `screens/Designer` | 4 |
| GovernmentWnd | `screens/Government` | 4 |
| SitRepPanel | `shell/Notifications` | 4 |
| EncyclopediaDetailPanel | `screens/Pedia` | 5 |
| ObjectListWnd | `screens/Objects` | 5 |
| PlayerListWnd, ChatWnd, ModeratorActionsWnd | `panels/Empires`, `panels/Chat`, `panels/Moderator` | 5 |
| CombatReport | `screens/CombatReport` | 5 |
| OptionsWnd (+ HotkeysPage) | `screens/Options` | 5 |
| SaveFileDialog, InGameMenu | `screens/SaveLoad`, `shell/GameMenu` | 5 |
| *BrowseWnd tooltips, GraphControl, MultiMeterStatusBar | `ui/components/*` | 2 |
| Hotkeys | `InputMap` + rebinding UI | 2 / 5 |

---

## 7. Cross-cutting workstreams

### 7.1 Testing and quality

- **GUT unit tests** for components and bridge views, and **integration tests** for game flows (quickstart, MP loopback, save/load).
- **Golden screenshots** at 100%, 150%, and 200% scale and in two languages, with a pixel-diff threshold. These run on every PR that touches `godot4/`.
- **Perf CI:** headless frame-time capture on generated galaxies, failing the build on budget regression.
- **TSan job** for `client/godot4/`.

### 7.2 Performance budgets (initial)

All figures are measured with the GL Compatibility renderer.

| Scenario | Desktop (mid discrete GPU) | Low-end desktop (integrated GPU, e.g. Intel UHD 620) |
|---|---|---|
| Map, 500 systems / 2k fleets, panning | 60 fps (≤16.6 ms) | 30 fps (≤33 ms) |
| Map, 1000 systems, panning | 60 fps | 30 fps |
| Turn-update → map refreshed | ≤150 ms | ≤300 ms |
| Open any screen | ≤100 ms | ≤200 ms |
| VRAM, full game loaded | ≤1 GB | ≤512 MB |

### 7.3 Conventions and lint

- **Lint:** extend `godot4-check.yml` with a check that rejects `theme_override_*` colour and size literals in `.tscn` outside `ui/theme/`, and inline numeric sizes in GDScript UI code.
- **Scene layout:**
  - `godot4/ui/` for tokens, theme, and components.
  - `godot4/shell/` for the app frame.
  - `godot4/map/` for the galaxy map.
  - `godot4/screens/` for full screens.
  - `godot4/panels/` for context panels.
- **Bridge API changes** require a doc entry and a GUT test.

### 7.4 Accessibility checklist (per screen)

- Every interactive control is reachable by focus navigation.
- No information is carried by colour alone.
- The screen reflows at 200% scale and with the de and ru string lengths.
- Every tooltip is reachable via keyboard (focus plus a hotkey).
- The screen respects "reduce motion".
- Contrast is at least 4.5:1 for body text in all shipped themes.

---

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Fork drift: upstream merges conflict with the redesign | High | Med | Keep the redesign in new directories and leave upstream's scenes unedited. Keep the bridge (`client/godot4/`) generic. Merge upstream at least every two weeks, gated by CI. Offer bridge additions upstream to shrink the diff. |
| Upstream changes the bridge in ways that clash with our API | Med | Med | Wrap our views and orders in separate source files (`client/godot4/views/`, `orders/`) and touch `FreeOrionNode.cpp` minimally. |
| Bridge threading bugs (crashes, corrupt state) | Med | High | Main-thread message handling (Phase 1.1), a TSan CI job, and ID-based views instead of raw pointers. |
| Parity takes far longer than estimated (61k LOC of UI) | High | Med | Gate on the parity checklist, not dates. Keep GG shippable until then. Port by gameplay loop so a playable vertical slice exists early (end of Phase 3 plus the first two Phase 4 items). |
| GL Compatibility limits visual ambition (no built-in glow, SSAO, or compute) | Med | Low | Fake bloom with additive halo sprites and a single-pass blur on a `BackBufferCopy`. Put the visual budget into 2D shaders (territory, lanes, impostors), which Compatibility handles well. |
| Art replacement blocked by licence or sourcing | Med | Med | Everything must be CC-BY-SA-compatible. Prioritise procedural and shader visuals (territory, lanes, stars, planet impostors), which need little new art. Add per-folder attribution files. |
| Godot version churn (4.4 → 4.7 in CI already) | Med | Med | Pin one version (Phase 0), and upgrade deliberately with the screenshot suite as the safety net. |
| Players attached to the GG UI | Med | Med | A floating-window mode option, and public preview builds with a feedback channel before the cut-over. GG stays buildable for one release afterwards. |

---

## 9. Suggested first ten tickets

1. Document the fork direction (§3) in `godot4/README.md`, create the `ui/`/`shell/`/`map/`/`screens/`/`panels/` skeleton, and point `run/main_scene` at `shell/Shell.tscn`.
2. Pin the Godot version across desktop CI and the project; remove the Godot 3 CI jobs; add Windows and macOS export presets.
3. Bridge: move `HandleMessage` to the main thread (`client/godot4/FreeOrionNode.cpp` network thread → queue → `_process`).
4. Bridge: `FOSystem`, `FOFleet`, and `FOPlanet` read-only views, plus `get_map_snapshot()` packed arrays, with GUT tests.
5. Bridge: `issue_fleet_move` and `rescind_order`, with a GUT test (move a fleet, end the turn, assert its position).
6. Design tokens resource, a theme generator script, and the Default and High-contrast themes.
7. Continuous `ui.scale` with OS DPI detection; replace the fixed steps in `IntroScreen.gd`.
8. Galaxy map MVP: starfield, stars via MultiMesh, lanes via ArrayMesh, camera with smooth zoom, and system picking.
9. Golden-screenshot CI job (IntroScreen and map MVP).
10. Fix the missing `icons/focus/stealth.png` and add a CI check that every `graphic=` path in FOCS exists.

---

## 10. Progress log

### 2026-11-15: starter tickets 1–10 done

All ten tickets in §9 are implemented on `claude/happy-allen-oas1fr`. They were verified locally on Linux:
- The C++ build is Godot 4 client only, with server and AI.
- The headless GUT suite has 13 passing tests and 3 visual tests pending (they need a renderer).
- The visual suite passes under Xvfb with opengl3.

| # | Result | Where |
|---|---|---|
| 1 | Shell entry scene, fork directories, README "Fork direction" | `godot4/shell/`, `godot4/README.md` |
| 2 | Godot pinned at **4.4.1** in `godot4/.godot-version` (read by the Windows and Ubuntu jobs). Ubuntu now builds and tests Godot 4. Godot 3 is gone from CI. Windows and macOS export presets added. | `.github/workflows/`, `godot4/export_presets.cfg` |
| 3 | Server messages are dispatched on the main thread from `_process` (8 ms budget, order kept). The network thread is removed. | `client/godot4/FreeOrionNode.cpp` |
| 4 | `FOSystem`, `FOFleet`, `FOPlanet` views; `FOUniverse` with `get_map_snapshot()` | `client/godot4/views/` |
| 5 | `FOOrders.issue_fleet_move`, `rescind_order`, `get_order_count`. Integration test: move, stop, re-issue, fleet moves over a turn. | `client/godot4/orders/`, `godot4/test/integration/` |
| 6 | `FOTokens` (default and high contrast) and `FOThemeBuilder`. Unit tests enforce WCAG AA text contrast. | `godot4/ui/` |
| 7 | `ui.scale` ("auto" or 0.75–2.0). Auto mode is capped so the logical window stays at least 1280×720. Applied by the `FOUi` autoload. | `godot4/ui/FOUi.gd`, `godot4/ui/FOUiScale.gd` |
| 8 | Galaxy map MVP, shown in-game behind upstream `MapWnd` via a runtime adapter | `godot4/map/`, `godot4/shell/UpstreamAdapters.gd` |
| 9 | Golden screenshots (gallery in both themes, synthetic 300-system galaxy), plus an Ubuntu 24.04 CI step with failure artifacts | `godot4/test/visual/` |
| 10 | `FOCUS_STEALTH` now uses `icons/meter/stealth.png`. `check/checkArtPaths.py` runs in the Lint PY FOCS workflow. | `check/`, `default/scripting/` |

**Bugs found along the way:**
- The Godot client never built the client system graph after GAME_START or TURN_UPDATE, so every move order produced an empty route. It now calls `InitializeSystemGraph` the same way the GG client does.
- The slider track had no thickness. The gallery golden caught this.

**Deviations from the plan text:**
- **Godot version:** pinned to 4.4.1 (upstream's desktop test version and the project baseline) rather than the newest release, so upstream merges stay clean. Upgrading is a separate, deliberate step.
- **Theme:** built at runtime from tokens instead of by an editor script, so no generated `.tres` needs committing.
- **Lanes:** drawn as a single batched `draw_multiline` rather than an `ArrayMesh`, because that keeps them at a constant pixel width for free. Revisit if the 1000-system perf test (§7.2) shows lanes as a cost.
- **UI scale ownership:** upstream `IntroScreen` still sets its own scale steps. `FOUi` re-applies `ui.scale` after every scene change, so upstream scenes stay unedited.

**Not verified locally:**
- The Windows and macOS CI jobs, and the export presets (no export templates here).
- The Docker matrix change.
- Whether the CI Mesa version matches the goldens closely enough. The tolerance is meant to absorb small differences.

**Next up** (Phase 1 remainder, then Phase 2):
1. A perf-test galaxy scene with a frame-time budget.
2. Typed option getters and setters plus an `option_changed` signal.
3. Multiplayer connect, join, and auth messages.
4. The rich-text converter.
5. Then the system/planet context panel on top of the map selection.

### 2026-11-15 (later): first playable shell

Done since the starter tickets:

**Performance**
- Galaxy map perf test: 1000 systems and 2000 fleets load in about 15 ms, and zooming costs about 7 ms per frame (CPU, headless).
- Map rendering: culling, screen-space labels, and a backdrop baked into one texture.

**Bridge**
- `FOOptions`, a typed options API with change signals.
- `FOPlanet.get_meter`, `FOUniverse.get_empire_name`, `FOFleet.get_eta`, and `FOUniverse.get_sitreps`.

**UI**
- `FORichText`: FreeOrion markup to BBCode, with `fo://` object links.
- `GameShell`, which replaces upstream `MapWnd`'s toolbar and contains:
  - Top bar: empire, turn, and End Turn (Ctrl+Enter) with a waiting state.
  - System panel: planets with type, focus and population icons, plus fleets. Own fleets can be selected.
  - Fleet orders: right-click a system to send the selected fleet. The route is drawn with an ETA chip.
  - Notification feed: this turn's sitreps. Links to planets, systems and fleets select and centre on them.
- Map hover chip; the galaxy is framed below the top bar; `ui.reduce-motion` option.

**Core bugs fixed along the way**
- **Option validators:** range, step and discrete validators were skipped for every `string_view` path, including `config.xml` and the command line. Now covered by a C++ test.
- **UTF-8 decoding:** the Godot bridge decoded stringtables and paths as Latin-1.
- **Auto-translation:** upstream `MapWnd`'s `ALWAYS` setting turned every name in child UI into "ERROR: <name>".

**Next**
1. Production screen (the Phase 4 order).
2. Fleet panel details: ships, split and merge, aggression.
3. Pedia links from the feed.
4. Ctrl+click to append waypoints.

### 2026-11-15 (later still): production, research, Pedia

**Screens**
- **Production:** queue, catalogue, location, filters and search.
- **Research:** queue and tech list. Adding a tech also queues its missing prerequisites.
- **Pedia:** articles for every content kind, search, browsing by kind, and back/forward history.
- **Navigation:** Production, Research and Pedia sit in the top bar on F2, F3 and F1. One screen shows at a time, and Esc returns to the map.
- **Pedia links:** content links in the event feed, articles and the "?" buttons open the Pedia. Map-object links return to the map.

**Bridge**
- `FOProduction`, `FOResearch` and `FOPedia`.
- `FreeOrionNode::InitTurnState`: the system graph and resource pools are recomputed every turn.
- Calls into content evaluation catch exceptions, because a C++ exception reaching Godot aborts the process.

**Next**
1. Fleet details: ships, split and merge, aggression.
2. Government (policies).
3. Ship designer.
4. Options screen.
5. Galaxy setup and save/load.

### 2026-11-15 (end of day): the fork's app stands on its own

The app now runs entirely on fork screens:
- Title screen with the seasonal splash, then galaxy setup, then the game shell.
- Game shell screens:
  - Map with the system, fleet and turn-event panels.
  - Production, Research and Government.
  - Pedia and Options.
- `--quickstart` still starts a game straight away.

Bridge additions since the last entry:
- `FOGovernment`.
- Ship views, plus fleet stance, split, merge and rename orders.
- `FOOptions` can set enum-typed options (galaxy shape, age, frequencies, AI aggression) by name. It goes through a validated `SetFromXML`, because `OptionsDB` only parses strings privately.

UI fixes:
- Check boxes and switches now use generated glyphs; Godot's defaults are invisible on dark surfaces.
- Fleet stance is a text segmented control; the GG stance icons are dark art made for light buttons.

**Next**
1. Ship designer.
2. Save/load.
3. Multiplayer lobby.
4. Combat reports.
5. Objects list.
