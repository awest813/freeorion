# Godot 4 client: gap list

What the fork's Godot 4 client still lacks compared with the GG client, and
what the plan (`UI_OVERHAUL_PLAN.md`) still owes. Audited on 2026-11-15 by
reading both clients; update it as gaps close.

**Priority**
- **P0:** blocks a normal single-player game.
- **P1:** a regular player would miss it within the first hours.
- **P2:** expected for parity, but play goes on without it.
- **P3:** polish, rare use, or infrastructure for the cut-over.

**Size:** S ≤ 1 day, M ≤ 1 week, L > 1 week.

## Summary

The fork covers the menus, galaxy setup, save/load, the map with fleet moves,
production, research, government, the ship designer, the Pedia, options,
combat reports and the objects list. Nothing blocks a normal
single-player game any more. The planet actions (colonise, invade, annex,
focus, scrap) were the last P0 gap. The resources, autosave and the game's end states (victory,
defeat, server errors) are in as well. So are supply ranges and fields on
the map. Planet detail is in; so are diplomacy and game rules;
so are meter breakdowns. Multiplayer is the last P1 item. All P2
(parity) items are closed: sounds, turn readiness, ship detail, build
locations, drag-and-drop between fleets, statistics charts, rebindable
shortcuts, Pedia extras and the tech tree.

| Priority | Open items | Main ones |
|---|---|---|
| P0 | 0 | (planet actions closed on 2026-11-15) |
| P1 | 1 | Multiplayer |
| P2 | 0 | (all closed on 2026-11-15) |
| P3 | 10 | Map modes, combat replay, moderator tools, onboarding, translations, scaled and localised goldens, TSan, packaging, CI, cut-over cleanup |

## P0: blocks a normal game

None open. Closed on 2026-11-15:
- Colonise and outpost.
- Invade.
- Annex.
- Change focus.
- Scrap ships.

Each is an action button, or a focus picker, on the planet rows of the system panel; Scrap is in the fleet panel. They are ported from `SidePanel`'s choices: the colony ship giving the largest projected colony, and "just enough" troop ships. Colonising and changing focus were checked in a real game. Invading and annexing are covered by unit tests only so far.

## P1: a regular player misses it

Closed on 2026-11-15:
- **Resources in the top bar:** PP and RP with unspent points flagged, IP with next turn's change, PP stockpile, population, ships and detection. Each opens its screen.
- **Autosave:** at the start and end of turns, on the first turn and on exit, following the `save.auto.*` options. Autosaves are listed (and marked) in the load screen.
- **Server errors:** shown in a dialog. Fatal ones and the server ending the game return to the title, saying why.
- **Lost server:** if the server dies, the client returns to the title.
- **Victory and defeat:** announced in a dialog, once each.
- **Supply on the map:** each empire's supplied area as one even tint, and its supplied lanes as bands, in the empire's colour.
- **Planet detail:** click a planet's name for its meters (now, next turn's change, target), buildings (own ones can be scrapped) and specials, all linked to the Pedia. The side column scrolls when the panels don't fit.
- **Species and colour in galaxy setup:** a species picker with icons (and Random) and a row of colour swatches, saved to the existing setup options.
- **Bombard:** in the planet actions, with ships chosen by their bombard tags as in `SidePanel`. Covered by unit tests only so far; no bombard-capable ships early in a game.
- **Diplomacy:** an Empires screen (F9) lists every empire with your standing (war, peace, allied) and proposals waiting either way. It offers the GG player list's actions: propose, accept or reject peace or alliance, withdraw, declare war, end an alliance. The top bar counts proposals made to you. Options moved to the in-game menu (F10 still opens it).
- **Game rules in galaxy setup:** a second tab lists all 78 rules by category, generated from their metadata (type, range, choices), with a reset per changed rule. Changes are validated and reach the game.
- **Meter breakdowns:** hovering a meter in the planet panel lists every effect behind its value (techs, buildings, species, policies, ...) as the GG meter tooltips do. This needed the client to compute effect accounting and meter estimates each turn, as `MapWnd::InitTurn` does; that also re-applies orders loaded with a saved game. Ship meters have them too (see Ship detail under P2).
- **Fields (ion storms, nebulae, ...):** drawn with their art at their real radius. Their names and effects on hover are still missing (P2).

### Map and panels

| Gap | Legacy | Size | Notes |
|---|---|---|---|

### Game flow

| Gap | Legacy | Size | Notes |
|---|---|---|---|
| Multiplayer | `ServerConnectWnd`, `MultiplayerLobbyWnd`, `PasswordEnterWnd`, `ChatWnd` | L | Connect, host, lobby (players, AIs, colours, ready), passwords, chat, and the lobby, auth, chat, status and timeout messages. |

## P2: parity

Closed:
- **Turn progress:** while you wait, the top bar shows what the server is doing ("Resolving Combat", ...). So does the title while a game is generated or loaded.
- **Revise an ended turn:** the End turn button becomes "Revise N" until the server starts processing.
- **Map navigation keys:** as the GG map's:
  - Ctrl+H for the home system.
  - Ctrl+, / Ctrl+. for the previous and next system; with Shift, systems with your planets.
  - Ctrl+F / Ctrl+G for your fleets; Alt+F / Alt+G for your idle fleets.
- **Detection ranges:** Ctrl+D shows your detection ranges as one faint tint. The choice is remembered (option `ui.map.detection.shown`).
- **Fields on hover:** a field's name shows under the cursor; clicking it opens its Pedia article.
- **Fleet waypoints:** Shift + right-click adds a move after the fleet's current route.
- **Sitrep history:** ‹ and › in the turn-event feed step through earlier turns. Filtering by type is still open (P3).
- **Queue a tech with its prerequisites:** this already worked; the button now says so ("Add with prerequisites").
- **Delete a save:** from the save and load screens, after a confirmation.
- **Credits and website:** on the title screen. Multiplayer belongs to the multiplayer item.
- **Restore the view on load:** the map's centre and zoom go with each turn's orders and come back when a save loads. Saves from the GG client keep only their zoom, since it stores the map position differently.
- **Production pause and stockpile:** queue items can be paused or resumed and allowed to draw on the imperial stockpile. The stockpile transfer project can be built. The screen shows the stockpile, how much a turn may draw from it, and next turn's amount. Stockpile limits per item (the GG blocksize split) are still open.
- **Design management:** the designer lists your designs, those put aside, premade and monster designs.
  - Yours can be put aside (production stops offering them; kept with the save, as in the GG client), brought back, or deleted.
  - Premade designs can be added to your empire.
  - Stats show the change from the design you started from, green when better.
  - Saving designs between games and renaming came later (P3).
- **Sound and music:** the game's music plays in a loop; buttons click and sound on hover; new turns, ending a turn and dialogs have their sounds. Options has a Sound section to turn music and effects on or off and set their volumes (the GG client's `audio.*` options).
- **Turn readiness check:** End turn first lists what may have been forgotten: unspent PP or RP (saying so when a queue is empty), fleets with colony ships but no orders, and new fleets without orders. Each entry goes to its screen or fleet; "End turn anyway" ends it. The check can be turned off in the dialog or in Options (`ui.turn.readiness.check`).
- **Ship detail:** a ship's name in the fleet panel opens its details below: design, hull and species (linked to the Pedia), damage, fighters shot down, fighters, troops and colonists as the GG ship rows show them, its meters with next turn's change, maximum and effect breakdown, and its parts with their capacities. Ship links in turn events select the fleet and open the ship.
- **Where can I build this:** ⌖ on each item in the production list lists every planet that can build it now, ticked where you are; one Add queues it at all the ticked ones. Highlighting those planets on the map is still open (P3).
- **Drag ships between fleets:** drag a ship from the fleet panel onto another of your fleets in the system panel to move it there, or onto Split for a new fleet. Dragging a ticked ship takes all the ticked ships along.
- **Graphs:** the Empires screen (F9) has a Statistics tab charting every empire statistic the server records (output, stockpiles, ships, planets, military strength, ...) turn by turn: one line per empire in its colour, yours thicker. Hovering shows every empire's value at that turn; the legend hides lines.
- **Hotkey rebinding:** every shortcut of the fork (screens, save, options, end turn, home, detection, map navigation) is an input action bound from an option (`ui.hotkey.godot.*`). Options has a Keyboard shortcuts tab: click a shortcut and press the new key with its modifiers, Esc to cancel; reset and clear per shortcut. A key already in use moves to the new shortcut, and Options says which one lost it. Tooltips show the current keys.
- **Pedia extras:** species articles list likes and dislikes (linked to their articles), the environment on each planet type, and known homeworlds, which open on the map. The planet panel's "Who could live here?" lists your species and the ones the content always reports, with their environment and the population each would reach, as the GG suitability report does by trying each species on the planet. Graphs are in the Empires screen.
- **Tech tree graph:** the research screen shows the techs as a list or as a tree. In the tree, each tech's column follows its longest prerequisite chain, and rows are ordered to keep arcs short. Cards are coloured by status, with queue position and progress. Drag to pan, scroll to zoom. Clicking a tech shows its details and lights up the chain it needs and leads to; double-clicking or Add queues it, prerequisites included. The category picker narrows the tree; search selects and centres the match.

## P3: polish and cut-over

Closed:
- **Build locations on the map:** "Show on map" in the production item's location list returns to the map with every system that can build it ringed; each click on a ringed system queues the item there, until Done or Esc.
- **Sitrep filters and snoozing:** ☰ in the turn-event feed shows or hides each kind of report, kept in the GG client's `ui.map.sitrep.hidden.stringlist` option. Right-clicking a report ignores it for 5 or 10 turns or for the session, hides its whole kind, or copies its text. The header counts what is hidden.
- **About:** the title screen's About shows the version and tabs for the credits, the project's vision, its licence (COPYING) and the Godot Engine's licence and third-party notices, as Godot asks projects to include.
- **Box-select fleets:** dragging from empty map space (fields included) draws a box; your fleets inside are selected together and ringed. Right-click a system sends them all (Shift appends), "Merge into one" joins them when they share a system, Esc or Clear ends the selection. Fields now open their Pedia article on release, so a drag can start over one.
- **Minimap, scale legend and circle:** at the bottom of the map, a scale bar of a round distance follows the zoom and a minimap shows the galaxy with the visible part framed (click or drag to move there). Alt+C draws a circle of the scale's length around the selected system. Ctrl+L, Alt+C and Ctrl+M toggle them (rebindable), remembered in the GG client's `ui.map.scale.*.shown` options and `ui.map.minimap.shown`. Placing production, box selection and these aids now live in `MapModes`, out of GameShell.
- **Objects list:** filter presets per kind (populated or outpost planets, moving or idle fleets, damaged ships); grouping by location, owner, species, fleet, design or building type with totals per group; a column chooser on right-clicking a title, with optional columns (planet type, size, shield; colony ships), remembered in `ui.objects.columns`; and a row menu to show the object on the map, open its species or building in the Pedia, or build at an own planet.
- **Designs kept between games, renaming:** your designs' ⋯ menu can keep a design for later games (written to `<user data>/shipdesigns` in the GG client's format, so both clients share them), rename it (designs your empire made) or put it aside. The Saved list adds a kept design to the empire or deletes it, and new games start with the kept designs, following `resource.shipdesign.saved.enabled`. New designs now get a UUID, as in the GG designer. The design lists use a picker instead of tabs and the part filter no longer widens its column, so the designer fits at 1280 px.
- **Theme-literal lint rule:** `godot4/tools/check_theme_literals.py`, run by the GDScript lint workflow, rejects theme overrides in scenes outside `ui/theme/` (upstream's root scenes exempt), numeric size and colour-literal overrides in UI scripts, and hex colours outside the style files; `# lint-ok: theme-literal` waives a line. The one offender (a 2 px gap in combat reports) now uses a token.
- **Scaled and localised screenshot tests:** the options, production and designer screens and the game shell also have goldens at 150% (1920×1080 window, 1280×720 layout) and 200% (2560×1600), rendered in the window as players see them, and in German and Russian. CI runs each variant (`VISUAL_VARIANT`); `FOOptions.set_language()` switches the stringtable. The visual tests share `visual_base.gd`. Note: the Russian shots show the fork's new strings in English (the translations item).

| Gap | Legacy / plan | Size | Notes |
|---|---|---|---|
| Map modes (political, supply, detection, resources, threat) | Plan, phase 3 | L | |
| Combat replay and charts | `CombatReport/GraphicalSummary`, plan phase 5 | L | |
| Moderator tools | `ModeratorActionsWnd` | M | |
| Onboarding hints | Plan, phase 5 | M | |
| Translations of the fork's new strings | `default/stringtables/*.txt` | S | New keys exist in English only; other languages fall back to English. |
| TSan job | Plan §7.1 | S | Build the bridge with `-fsanitize=thread` and run the integration test with libtsan preloaded into Godot. |
| Packaging | `CMakeLists.txt`, `packaging/` | M | The Godot client runs from the source tree only; installers and the desktop entry still ship the GG client. |
| Windows, macOS and Docker CI | `.github/workflows` | S | Changed but never run. |
| Remove upstream's unused Godot scenes | `godot4/*.tscn`, `UpstreamAdapters.gd` | S | Root scenes from the upstream port, unused by the Shell flow. Waits for the cut-over: until then the fork keeps them unedited (`godot4/README.md`) so upstream changes to them merge cleanly, and `UpstreamAdapters` keeps them working if opened directly. |
| Art pipeline | Plan, phase 6 | L | Compressed imports, downscaled hull and field art, unreferenced icons, attribution files. |
