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
combat reports and the objects list. What blocks a real game today is the
**planet actions**: you can't colonise, invade, annex or change focus, so
an empire can't grow. After that come the information a player plays by
(resources in the top bar, supply ranges, planet meters) and the game's
end states (victory, defeat, server errors).

| Priority | Open items | Main ones |
|---|---|---|
| P0 | 5 | Colonise/outpost, invade, annex; change focus; scrap |
| P1 | 13 | Top-bar resources; supply on the map; planet detail; autosave; end of game and server errors; diplomacy; species and colour in setup; meter tooltips; multiplayer |
| P2 | 22 | Tech tree graph; design management; production pause and stockpile; map hotkeys and overlays; sitrep history; graphs; sound; hotkey rebinding |
| P3 | 15 | Minimap, box select, combat replay, object filters, moderator, packaging, cut-over cleanup |

## P0: blocks a normal game

| Gap | Legacy | Size | Notes |
|---|---|---|---|
| Colonise and outpost a planet | `UI/SidePanel.cpp` `ClickColonize`, `AutomaticallyChosenColonyShip` | M | Needs a `ColonizeOrder` in the bridge, choosing the best colony ship in the system and projecting the new colony's target population, plus a button with cancel on the planet row. |
| Invade a planet | `SidePanel.cpp` `ClickInvade`, `AutomaticallyChosenInvasionShips` | S | `InvadeOrder` with "just enough" troop ships; show own troops against defenders. |
| Annex natives | `SidePanel.cpp` annex button, `AnnexOrder` | S | Cost in IP, affordability, the species' annexation condition; cancel. |
| Change a planet's focus | `SidePanel.cpp` focus drop-down, `ChangeFocusOrder` | S | Available foci per planet; the panel shows the focus but can't change it. |
| Scrap ships and buildings | `FleetWnd.cpp`, `BuildingsPanel`, `ScrapOrder` | S | Including cancelling a scrap. |

## P1: a regular player misses it

### Map and panels

| Gap | Legacy | Size | Notes |
|---|---|---|---|
| Resources in the top bar | `MapWnd` toolbar (`m_industry`, `m_research`, `m_influence`, `m_population`, `m_detection`, fleet counts) | S | PP, RP and IP with this turn's change, stockpile, population; each opens its screen. |
| Supply ranges on the map | `MapWnd::InitStarlaneRenderingBuffers` supply lanes, `RenderSupply` | M | Owner-tinted supply lanes or territory shader (plan, phase 3). Decides where fleets resupply and where production can be delivered. |
| Fields (ion storms, nebulae, black holes) | `UI/FieldIcon.cpp` | S | Not drawn at all; they change stealth, detection and movement. |
| Planet detail | `SidePanel` population, resource, military, buildings and specials panels | M | Meters with their targets (industry, research, influence, stability, supply, defence, shield, troops), buildings and specials. The panel shows population and focus only. |
| Meter breakdown tooltips | `UI/MeterBrowseWnd.cpp`, `ShipDesignBrowseWnd`, `IconTextBrowseWnd` | L | Why a meter has its value (each effect's contribution). FreeOrion's main teaching tool. |
| Bombard | `SidePanel.cpp` `ClickBombard` | S | Rarely used but part of the planet actions. |

### Game flow

| Gap | Legacy | Size | Notes |
|---|---|---|---|
| Autosave | `GGHumanClientApp::Autosave`, `save.auto.*` options | S | Each turn and on exit, as the options say. Nothing autosaves now. |
| End of game | `HumanClientFSM` `EndGame`, `PlayerEliminated` | S | Victory, defeat and elimination are ignored: the game just stops changing. |
| Server errors and crashes | `ERROR_MSG`, `Disconnection` in `HumanClientFSM` | S | Show the error; if the server dies, say so and return to the title. |
| Diplomacy | `PlayerListWnd`, `DIPLO_MESSAGE`, `DIPLOMATIC_STATUS` | M | AIs propose peace and alliances even in single player; the client can neither see nor answer them. Includes an empires list. |
| Species and colour in galaxy setup | `GalaxySetupWnd` species picker, colour selector | S | New games always use the stored species and colour. |
| Game rules in galaxy setup | `GalaxySetupWnd` rules tab | M | Generated from the rules' metadata, like the options screen. |
| Multiplayer | `ServerConnectWnd`, `MultiplayerLobbyWnd`, `PasswordEnterWnd`, `ChatWnd` | L | Connect, host, lobby (players, AIs, colours, ready), passwords, chat, and the lobby, auth, chat, status and timeout messages. |

## P2: parity

| Gap | Legacy | Size | Notes |
|---|---|---|---|
| Tech tree graph | `TechTreeWnd`, `TechTreeLayout`, `TechTreeArcs` | L | The fork has the list view only. |
| Queue a tech with its prerequisites | `ResearchWnd` add-with-prereqs | S | |
| Design management | `DesignWnd` saved/premade/monster lists | M | Save designs to disk, mark obsolete or hide, delete, browse premade and monster designs. |
| Compare a design with the current one | `DesignWnd` | S | |
| Production: pause, stockpile | `QueueListBox`, `ProductionWnd` | M | Pause and resume items, allow the imperial stockpile, stockpile projects and limits. |
| Production: where can I build this | `BuildDesignatorWnd` | M | Highlight valid locations on the map, build at several at once. |
| Map navigation hotkeys | `MapWnd::ConnectKeyboardAcceleratorSignals` | S | Previous/next system, own system, fleet, idle fleet; zoom keys exist. |
| Detection ranges overlay | `MapWnd` detection circles | S | |
| Fleet waypoints | `MapWnd` shift-click | S | The bridge supports appended moves; the map doesn't offer them. |
| Ship detail | `FleetWnd` ship data panel | M | Per-ship meters, parts, attack, fighters. |
| Drag ships between fleets | `FleetWnd` | M | Split and merge exist; drag-and-drop doesn't. |
| Sitrep history and filters | `SitRepPanel` prev/next turn, type filters, snooze | S | The feed shows the current turn only. |
| Graphs | `ui.map.graphs`, `GraphControl` | M | Empire statistics over time. |
| Pedia extras | `EncyclopediaDetailPanel` | M | Graphs, the planet suitability table, "show on map". |
| Turn progress | `TURN_PROGRESS` phases | S | "Processing orders", "combat", … instead of "Waiting…". |
| Revoke an ended turn | `MAP_BTN_TURN_REVOKE` | S | |
| Turn readiness check | Plan, phase 4 item 7 | M | Idle fleets, empty queues, unspent points before ending the turn. |
| Hotkey rebinding | `OptionsWnd` hotkeys page | M | Fork shortcuts are fixed in code. |
| Sound and music | `UI/Sound.cpp`, `PlaySound` calls | M | Fork screens are silent; no music. Volume options belong in Options. |
| Intro extras | `IntroScreen` | S | Multiplayer, credits, website links. |
| Restore view on load | `SaveGameUIData` | S | Camera and selection are lost on load. |
| Delete a save | `SaveFileDialog` | S | |

## P3: polish and cut-over

| Gap | Legacy / plan | Size | Notes |
|---|---|---|---|
| Minimap, scale legend and circle | `MapWnd` | M | |
| Box-select fleets | Plan, phase 3 | M | |
| Map modes (political, supply, detection, resources, threat) | Plan, phase 3 | L | |
| Combat replay and charts | `CombatReport/GraphicalSummary`, plan phase 5 | L | |
| Object list filters, grouping, column chooser, actions | `ObjectListWnd` | M | |
| Moderator tools | `ModeratorActionsWnd` | M | |
| Credits and About | `CreditsWnd`, `About` | S | |
| Onboarding hints | Plan, phase 5 | M | |
| Translations of the fork's new strings | `default/stringtables/*.txt` | S | New keys exist in English only; other languages fall back to English. |
| Screenshot tests at 150% and 200% scale and in de/ru | Plan §7.1 | M | Goldens run at 100% in English only. |
| TSan job, theme-literal lint rule | Plan §7.1, §7.3 | S | |
| Packaging | `CMakeLists.txt`, `packaging/` | M | The Godot client runs from the source tree only; installers and the desktop entry still ship the GG client. |
| Windows, macOS and Docker CI | `.github/workflows` | S | Changed but never run. |
| Remove upstream's unused Godot scenes | `godot4/*.tscn`, `UpstreamAdapters.gd` | S | Root scenes from the upstream port, unused by the Shell flow. |
| Art pipeline | Plan, phase 6 | L | Compressed imports, downscaled hull and field art, unreferenced icons, attribution files. |
