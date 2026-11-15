# Godot 4 client: feature parity with the GG client

A feature-by-feature audit of the GG client's windows (`UI/`, `client/human/`)
against the Godot 4 client, made on 2026-11-15 after every item of
`UI_GAP_LIST.md` P0-P2 was closed. Each line is something a player of the GG
client can see or do that the Godot client couldn't then. Ticked items are
done; sizes as in the gap list (S ≤ 1 day, M ≤ 1 week, L > 1 week).

## Multiplayer

- [x] Connect dialog: player name, role (player, observer, moderator), host or join, server address (`ServerConnectWnd`) — M
- [x] Password prompt (`PasswordEnterWnd`) — S
- [x] Lobby: new or loaded game, galaxy settings by the host, player rows (add AI, drop, observer, moderator), empire name, colour and species, saved empires for loaded games, ready and host marks, start conditions, chat (`MultiplayerLobbyWnd`) — L
- [x] In-game chat, whispers (`ChatWnd`) — M
- [x] Player list with ready status, turn timeout (`PlayerListWnd`, `MapWnd`) — S
- [x] Concede, and "leave while not ready?" (`InGameMenu`) — S
- [ ] Multiplayer autosave; server-side save list — S
- [ ] Observer mode; moderator tools (`ModeratorActionsWnd`) — M

## Map and system panel (`MapWnd`, `SidePanel`, `SystemIcon`, `FleetButton`, resource panels)

- [x] Turn button menu: send orders and start, revoke all orders — S
- [x] Auto end-turn toggle — S
- [x] Auto-explore for fleets — M
- [x] Double-click a system or planet: production there — S
- [x] Route and ETA preview when hovering a system with a fleet selected — S
- [x] Movement lines for all visible fleets, with ETA markers per turn — M
- [x] Click fleet icons on the map (in transit too; repeated clicks cycle) (fleets sharing a place are stacked apart, so each is clicked directly) — M
- [x] Inspect foreign and monster fleets — M
- [x] Dismiss sensor ghosts (forget objects no longer seen) — S
- [x] Ships tooltip in the top bar (armed, colony, troop, carrier counts) — S
- [x] Wasted PP: centre on a system wasting PP — S
- [x] Map options menu (system circles, empire-coloured lanes, fleet supply lines, ...) — S
- [x] Zoom slider; rebindable zoom and pan keys; sitrep panel key — S
- [x] System names and circles in their owners' colours — S
- [x] Fleet icons by role and size, selection mark — M
- [x] Blockade marker and tooltip — S
- [x] System picker drop-down with ◀ ▶ — S
- [x] Rename own system or planet — S
- [x] Give a planet or fleet to an empire at peace — S
- [x] Planet status (supply cut, attacked, recently conquered, unhappy) — S
- [x] Planet visibility (last seen, stealth against detection strength) — S
- [x] System resource summary (PP, RP, IP, stockpile, defence, troops, supply) with breakdowns — M
- [x] Per-planet meter summaries in the system panel — M
- [x] Rebel troops meter; meter and species names linked to the Pedia (species now; meters with the meter articles below) — S
- [x] Buildings being produced on a planet, with progress — S
- [x] Building tooltips; specials' turn added — S
- [x] Population census tooltip (per species and tag); fuller resource tooltips — S

## Fleets and ships (`FleetWnd`, `MeterBrowseWnd`)

- [x] Explore order (with auto-explore above) — M
- [x] Merge all own fleets at the system — S
- [x] Split damaged, unfueled, or without full fighters — S
- [x] Split one fleet per ship, or by design — S
- [x] Scrap or keep the whole fleet in one action — S
- [x] Rename a ship — S
- [x] Fleet totals: damage, fighters, troops, colonists, structure, shield, lowest fuel, slowest speed — M
- [x] Per-ship stat icons in the fleet's ship rows — S
- [x] New fleets' stance, including Auto (`ui.fleet.aggression`) — S
- [x] Drag a whole fleet onto another to merge — S
- [x] Ship damage breakdown per weapon; fighter breakdown — M

## Objects list (`ObjectListWnd`)

- [x] Condition filter builder (homeworld, capital, armed, can colonise, species, focus, planet type, meter values, ...) — L
- [x] Visibility filter: visible now, seen before, destroyed — M
- [x] Fields as a kind — S
- [x] More columns (every meter, environment per species, distance to selection, last battle, specials, hull, parts, costs) — M
- [x] Nested rows (system › planet › building, fleet › ship), expand and collapse all — M
- [x] Select several rows; set focus on them; queue an item at them — S

## Combat reports and turn events (`CombatReport`, `SitRepPanel`)

- [x] Graphical summary: a bar per unit, with GG's four display toggles — M
- [x] Initial forces and losses per empire in collapsible sections — S
- [x] Turn events sorted by importance — S
- [x] "Latest" button; ‹ › skip turns with nothing shown — S
- [x] Double-click to dismiss a report — S
- [x] Filter menu with every report type seen, and "hide all" — S

## Production, research, government, designer

- [x] Batch build (blocksize) — S
- [x] Queue item menu: duplicate, split off the incomplete part, rally to the selected system, move to top or bottom, Pedia — S
- [x] Removed items can be restored until the turn ends — S
- [x] Drag to reorder queues; drag a catalogue item into the queue — M
- [x] Click a queue item to show its location on the map (from the item menu) — S
- [x] Delete key removes the selected queue item — S
- [x] Richer queue and catalogue tooltips (costs per turn, time here and minimum, why not buildable) — S
- [x] PP of the selected location's supply group — S
- [x] Add to the top of the queue (production and research) — S
- [x] "Unavailable" catalogue filter — S
- [ ] Ship design articles in the Pedia (and design links) — M
- [x] Pause research of a tech — S
- [x] Tech tree: status filters, several categories at once, unlock icons on cards, rich tooltips, zoom buttons, Shift+click to queue — M
- [x] Tech list: sortable columns — S
- [x] Government: availability filters (adopted, adoptable, unaffordable, restricted, locked), full policy tooltips, revert this turn's changes — S
- [x] Government: drag policies to slots, double-click to adopt or remove — M
- [x] Designer: update an existing design or saved design — M
- [x] Designer: specific reasons a design is invalid; name check; description — S
- [x] Designer: clear all parts; fill every slot of a type; drag parts — M
- [x] Designer: part and hull availability and obsolete filters; mark parts and hulls obsolete; hide redundant parts; part class toggles — M
- [ ] Designer: Pedia and tooltips for parts, hulls, designs; mark designs that can't be built; "add all saved now" — S

## Title, options, saves, messages, Pedia, empires

- [x] Continue the newest save from the title screen; Pedia from the title screen — S
- [ ] Command line: `--continue`, `--load`, `--auto-connect`, `-f` — S
- [x] Video: fullscreen (Alt+Enter), window size and position remembered — M
- [x] Language picker in Options — S
- [ ] Hide options this client doesn't use (colours, fonts, ...) — M
- [x] Randomise-seed button in galaxy setup — S
- [ ] Save list: galaxy details, sortable columns — S
- [ ] Message log: turn begun, game saved, diplomatic changes, chat, `/pedia` — M
- [x] Content checksum mismatch warning — S
- [ ] Pedia: empire articles; species opinions and who likes or dislikes what — M
- [ ] Pedia: unlocked by, prerequisites and exclusions, location requirements — M
- [ ] Pedia: meter types, galaxy setup and game rules, objects; full-text search — S
- [ ] Empires: summary numbers per empire, player type and ready marks — S
- [ ] Remaining interface sounds (list select, drop, panel open and close, fleet and system hover) — S
