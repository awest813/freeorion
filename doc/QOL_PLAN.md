# Godot 4 client: parity check and quality-of-life plan

Written 2026-11-15, after `UI_PARITY_AUDIT.md` was completed.

## 1. Parity re-check

`UI_PARITY_AUDIT.md` was a checklist written by the same person who built the
features, so it was checked again independently:

- **Order types.** Every order type the game defines (`util/Order.h`) can be
  issued from the Godot client. That includes colonise, invade, annex,
  bombard, scrap, give, forget, focus, policies, queues and designs.
- **Window by window.** Three separate audits compared the GG client's windows
  (`UI/`) and its game-flow code (`client/human/`) with the Godot client:
  - the map and side panels;
  - production, research, government and the designer;
  - everything else (Pedia, objects, combat, sitreps, chat, lobby, options,
    saves, and the client's handling of server messages).

  Each gap they reported was checked in the code before acting on it.
- **Message handling.** The bridge handles every server message GG handles,
  except the server echoing back an "unready". That is harmless, as the Godot
  client already unlocks the turn itself.

### Fixed in the same pass (commits `54c872c`, `5305890`)

| Gap | Was |
|---|---|
| Colonise and invade use the ships selected in the fleet panel | always auto-picked, ignoring the selection |
| Production queue moves around items removed this turn | ▲/▼ could swap with a hidden item; "to bottom" stopped short |
| A queued item whose location became invalid says so | looked normal while stalling |
| Batches show turns to the next item, not only to the last | |
| Stockpile drawn and wasted PP; wasted RP | not shown |
| Saving sends this turn's orders first; the exit save has them too | saves lost the turn's orders |
| Save offered only when GG allows it (host; AIs done) | non-host saves were refused by the server and stuck |
| Server won't start or dies before the game: back to the title with the reason | title stuck on "Starting…" |
| A server error turns auto end turn off | kept ending turns after the error |
| Player status changes refresh the empires' ready marks | marks went stale in multiplayer |
| Duplicate stringtable keys (`COMBAT_INITIAL_FORCES`, `COMBAT_SUMMARY`) | GG client showed "%1%" raw |

Each fix was unit-tested. The first two and the server-start fix were also
checked in a real game.

### Remaining parity gaps

All are minor. None blocks playing.

| # | Gap (GG source) | Importance | Size |
|---|---|---|---|
| R1 ✅ | Annex button tooltip: species' opinions, stability, costs, why it's restricted (`SidePanel.cpp:2050`) | medium | S |
| R2 | Movement lines: turn numbers at each ETA marker, red ring at a blockade stop, yellow at blocked supply (`MapWnd.cpp:2436`) | medium | M |
| R3 | Detection ranges of every known empire in its colour, not only the player's (`MapWnd.cpp:4118`) | medium | S |
| R4 ✅ | A dedicated server going hostless sends players back to the lobby; Godot clients stay in a dead game (`HumanClientFSM.cpp:898`) | medium (MP) | S |
| R5 | Tech tooltips with queued state, progress, RP this turn, ETA; queue rows get a tooltip; clicking a queued tech centres the tree on it (`TechTreeWnd.cpp:172`, `ResearchWnd.cpp:690`) | medium | S |
| R6 | Research queue item menu (top, bottom, Pedia); right-click on tree cards (`ResearchWnd.cpp:316`, `TechTreeWnd.cpp:921`) | low | S |
| R7 | Reorder designs, which sets the production catalogue's order (`DesignWnd.cpp:3047`) | low | S |
| R8 | "Add premade designs at game start" toggle (`resource.shipdesign.default.enabled`) | low | S |
| R9 | Quantity and batch size for the stockpile project; force-add unavailable items; ship catalogue tooltip with parts | low | S |
| R10 | Dismiss sensor ghosts of single ships and buildings, and all in a map fleet marker | low | S |
| R11 | Split off ships of one design; detailed fleet status (refuelling, ETA to next system, out of range) | low | S |
| R12 | Obstructed supply half-lanes; systems split-coloured by several owners; scanlines over out-of-sight fields | low | M |
| R13 | Chat: Up/Down history, Tab completion, `/zoom`, timestamps option; third-party diplomacy in the log | low | S |
| R14 | Mid-turn partial updates shown; lobby shows the server's progress while it generates | low | S |
| R15 | `--auto-quit` flag; monster designs in the Pedia index; pausing music when the window loses focus | low | S |

## 2. Quality-of-life plan

The items below come from the three audits and from watching the client in
real games while checking each batch. They are ordered by how often a player
runs into them, and each has a test of done.

### Phase 1: feedback when something doesn't happen (about 2 days) ✅ done

The most common frustration is an action that silently does nothing.

1. **Say why an order was refused.**
   - The planet actions (colonise, invade, annex, bombard) share one
     "refused" notice (`GameShell._on_planet_action`).
   - The fleet actions (scrap, stance, merge) say nothing at all on failure
     (`PanelOrders.gd`).
   - Fix: return a reason key from the bridge (e.g. "no troop ships here", "the
     planet is shielded", "not enough IP") and show it.
   - Done when every action button either works or shows a reason.
2. **Disable what can't work, with a tooltip saying why.**
   - The fleet scrap button is enabled while the fleet is in transit, though
     scrapping needs a system.
   - Every own planet's "⋯" menu shows a disabled "no gift" entry.
   - Right-clicking a system with a foreign fleet shown does nothing.
3. **Order refresh after changes.**
   - Production: the supply group's PP and the catalogue go stale after
     queue changes. An item that can be queued only once still shows Add.
   - Government: when a policy dropped onto a slot can't be adopted, the
     policy it replaced looks adopted, though it was revoked.
4. **Multiplayer lobby clarity.**
   - The server resets ready marks when it corrects a player's settings.
     Show "your ready was reset: settings changed".
   - A game with no human player can't start. Say "waiting for a human
     player" instead of nothing.
   - Lock Ready once everyone is ready: a ready sent as the game starts gets
     the player disconnected.

### Phase 2: fewer clicks for common work (about 3 days)

1. **Double-click to add** on production catalogue rows and research list
   rows, as on the tree.
2. **Keep the quantity and batch spinners** while they're being clicked.
   - Each step sends an order and rebuilds every row, freeing the spinner
     mid-click, so holding the button down fails.
   - Fix: apply the value on release or after a short pause, and update the
     row in place.
3. **One meaning for Shift in research.**
   - Shift+click queues at the end, but Shift with Add or double-click queues
     at the top, and Shift+double-click sends both orders.
   - Fix: Shift always means "at the top"; plain clicks select.
4. **Groups of fleets act together.**
   - Box-selected fleets get no route preview and no group stance or explore
     (`_active_fleet()` only knows one fleet).
   - Fix: give the group a route preview, and offer stance and explore for
     the whole selection.
5. **The route preview follows Shift.**
   - Today it changes only when the hovered system changes.
   - Fix: redraw when Shift is pressed or released.
6. **Location picker.**
   - The production "Build at" list holds every owned planet, outposts too,
     ungrouped.
   - Fix: group by system, add a search, and show planets that can build
     something first.
7. **Stockpile project under its filter.** It appears only under "All".

### Phase 3: less in the way (about 2 days)

1. **Hints.**
   - The tip box sits over the top-right of the screen it is shown on,
     covering filter rows and pickers until it is dismissed (seen on
     several screens during testing).
   - Fix: anchor each hint beside the control it explains, and never over a
     control.
2. **Unknown isn't zero.**
   - The empires list shows 0 ships, planets and output for empires the
     player knows nothing about.
   - Fix: show "?" and say "not known" in the tooltip.
3. **Observer and moderator top bar.**
   - The resource row stays as empty space.
   - Fix: hide it, or show the selected empire's numbers.
4. **The moderator tools cover the middle of the map.**
   - Fix: make the panel collapsible and dock it at the side.
5. **Tech tree "fit".**
   - At the smallest zoom the whole tree is unreadable.
   - Fix: fit shows the current category or status filter, and the zoom
     floor keeps names legible. Show a minimap when the tree doesn't fit.
6. **Truncated design names** in the narrow designs column.
   - Fix: wrap to two lines, or move "can't be built" to an icon.
7. **Saving in multiplayer.**
   - The save screen lists local single-player saves while the save goes to
     the server's directory.
   - Fix: list the server's saves (as the lobby now does).

### Phase 4: speed and polish (about 2 days)

1. **System panel refresh cost.**
   - Every refresh re-runs the colony projection for every ship and planet,
     with two meter-estimate updates each.
   - Fix: cache it per turn and per ship/planet pair, as GG does.
   - Done when there are no rebuilds while a drop-down is open, and a refresh
     on a 30-ship system takes under 10 ms.
2. **LAN search blocks for about 2 seconds**, so "Searching…" never shows.
   - Fix: run it on a thread or in steps.
3. **Closing the window in a game leaves at once.**
   - Fix: ask as the in-game menu does (save? not ready?).
4. **Server errors stack modal dialogs.**
   - Fix: show non-fatal errors in the message log with a toast. Keep dialogs
     for fatal ones.
5. **Auto-advance from the command line** doesn't show the top bar as
   waiting.
6. **Research tooltip and turn markers** (R5, R2 above) also serve as QoL
   wins, and fit here if not done earlier.

### How each phase is checked

Each phase follows the parity work's routine:

- unit tests with fake sources;
- a real game under Xvfb (two clients for multiplayer items);
- updated goldens;
- one commit per phase.

Phase 1 also gets a test that every enabled action button either issues an
order or shows a reason.

### Suggested order

1. Phase 1, plus R4 (players stuck in a dead game) and R1 (annex tooltip).
2. Phase 2, plus R5.
3. Phase 3, plus R2 and R3.
4. Phase 4, then the low-importance R items as time allows.
