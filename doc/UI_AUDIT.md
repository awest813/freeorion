# UI and menu audit

Every screen, menu and dialog was captured in a real game at 1280×800:
- title, options and keyboard shortcuts, About, load, Connect, Pedia, the three setup steps;
- the map, system, planet and fleet panels, the map menu, messages;
- Production, Research (list and tree), Government, Design, Objects, Combat, Empires, Pedia;
- options, save, load and the game menu in game.

The visual goldens then checked the changes at 100%, 150% and 200%, and in German and Russian.

## Fixed

| Where | Problem | Fix |
|-------|---------|-----|
| Pedia from the title | The start page showed 2 of 13 kinds: its tiles were built before the game's content was read. | Tiles are rebuilt whenever the start page is shown (test added). |
| Title | An error at every start: the splash's drift read the viewport size before the title was in the tree. | The pivot follows the splash's own size. |
| Title | The "Continue" detail line sat left of the menu items. | Indented to line up with the items' text. |
| Front-end screens | Options, setup, saves, About, Connect and the Pedia stood on a flat dark texture. | They open over the title's splash, which shows through their glass. |
| Production queue | The "use the stockpile" toggle was a wide box with its icon off to the left. | A square toggle with the icon centred. |
| Government | Slots were plain grey boxes; section names in large title type. | Slots tinted in their category's colour; empty slots explain how to fill them; section captions in the caps style. |
| Options | Section names in large title type. | The caps style, as the rest of the UI. |
| Keyboard shortcuts | Symbol keys showed as "Equal" and "Minus" (also in tooltips and hints). | Shown as "=" and "−"; the saved bindings are unchanged. |
| Objects | "1 objects". | "1 object". |
| Combat | With no combats, one grey line in the top-left corner. | A centred empty state with the combat picture (new `ScreenKit.empty_state`). |
| Map menu | GG's option descriptions ("Galaxy map gas rendering", "Show or hide the minimap"). | Short labels: "Nebulae", "Minimap"... The options keep their descriptions. |
| Map | Fields out of sight have GG's scanlines, which read as a rendering fault. | The scanlines are lighter. |
| Load and save | Cards showed only a colour strip. | Each card shows the empire's flag. |
| Setup | The flag floated apart from the empire name. | The flag sits beside the name, with the species under them. |
| Setup | Rule tabs read "Balance:Misc". | "Balance: Misc". |
| Connect | The LAN list had no style. | Lists (`ItemList`) are styled like the tables. |

## Looked at and left

- The turn-1 event reads `**Greetings**` with the asterisks: that is the article's real title in the game data, and the event tells players to click that word.
- The bot's double-click on "Outpost Ship" fails only on turn 1, when it clicks as the screen first opens. Later turns queue fine, and a unit test covers the double-click.

# UX audit

The second pass looked at how the interface behaves rather than how it looks. A bot opened every screen, panel and menu in a real game at 1280×720, 1280×800 and 1920×1080. On each it checked every visible control for:
- icon-only buttons without a tooltip;
- disabled buttons that don't say why;
- text cut off with no tooltip giving all of it;
- controls off screen;
- targets too small to click;
- screens that Esc doesn't close.

It also hovered cards and the top bar to see real tooltips.

## Fixed

| Where | Problem | Fix |
|-------|---------|-----|
| Everywhere | With a tooltip showing, Esc only closed the tooltip: Godot's viewport keeps the key. Pointing at something and pressing Esc to close a screen needed two presses. | FOUi sees the Esc first and sends it on once the tooltip has gone (tests for plain and custom tooltips). |
| Everywhere | Long tooltips (policies, production items, techs) ran on one line up to 900 px wide. | Tooltips longer than about 420 px wrap (`FOUi.wrap_tooltip`). |
| Research, Production, Government lists | Cards didn't react to the pointer. | A card lifts when pointed at: a lighter fill and a stronger edge (`ScreenKit.card`). |
| Saves | Load and Delete were disabled with no reason. | Their tooltips say to pick a save first (or to type a name, to save). |
| Government | Revert was disabled with no reason. | Its tooltip says there's nothing to undo, or what it undoes. |
| Research and Production queues | When empty, a grey line at the top of a blank column. | The empty state with the screen's picture. |

## Checked and fine

- Every screen, the game menu and the menu screens close with Esc.
- Deleting a save or a design asks first; scrapping ships can be cancelled until the turn ends; quitting asks first.
- Saving says when the save is written.
- At 1280×720 the panels scroll rather than clip, and the designer fits.
- At 1920×1080 the research grid shows three columns.
- No icon-only button lacks a tooltip, and no clipped text lacks a way to read it.

# Late-game audit

The first two passes ran at turn 3, when lists are short and screens are mostly empty. This pass loaded a turn-40 save (150 systems, 7 empires, six colonies, adopted policies, a research queue) and went through:
- the map, zoomed in and out, and the home system's planet;
- the largest fleet and one of its ships;
- every screen, the tech tree, the Empires statistics, and each Objects tab;
- Pedia articles for a tech, a species and a planet;
- messages, the game menu and a delete confirmation.

The same per-control checks ran on each.

## Fixed

| Where | Problem | Fix |
|-------|---------|-----|
| Research, tree view | The one-line hint under the tree (760 px) widened the screen past a 1280 px window by 14 px. | The hint wraps (test added). |
| Confirmations | Delete dialogs started with the focus on the red button, so Enter deleted. | When the first choice destroys something, the focus starts on Cancel, as Esc does (test added). |
| Objects | "structure / max" was cut ("128 / 1…"), as were sorted number headers: number columns were capped at 84 px. | Number columns are as wide as their values and title, up to the text cap. |
| Empires statistics | Count charts (armed ships, planets) had ticks at 0.5 and 1.5. | Charts of whole numbers tick on whole numbers; the turn axis always does (test added). |
| Fleet panel | "Scrap Ship" was disabled without a reason. | Its tooltip says to tick the ships to scrap. |
| Pedia | Captions of long link lists ("Likes", "Dislikes") sat halfway down the list. | They sit at its top. |

## Looked at and left

- The research timeline's turns need not rise down the queue: a later tech can finish first when it gets more points (45, 44, 48). The marks show the real turns.
- Combat reports aren't kept in saves, so the combat screen wasn't seen with late-game data. Its golden covers a report with both sides.

# Menus

| Where | Before | Now |
|-------|--------|-----|
| Options | The right side was every engine option in one list: thread counts, log levels, ports and paths next to autosaves and scouts. | Three pages. **Gameplay** (first) has what players change, in plain words and groups: the end-of-turn check, scouts exploring, new fleets' stance (as a list, not a text field), designs in new games, autosaves. **Keyboard shortcuts** as before. **Advanced** has everything else, with a note that most players never need it. Glass panels and empire colours moved to the Interface switches on the left. |
| Options | Changing the new fleets' stance in Options took effect only in the next game. | Splitting fleets reads the setting each time. |
| Game menu | Quitting warned that progress since the last save is lost, without saying when that was. | The confirmation says when the game was last saved ("Last autosaved on turn 40, 2026-11-16 12:25") or that it never was. |
| Title | Entries had no explanation ("Quick start" does what?). | The entry pointed at or focused is explained under the menu. |
| Load | With no saves, a grey line at the top of an empty list. | The empty state, centred. |
| Galaxy setup | The numbers alone: what do 150 systems and 6 AIs make? | Under the preview: "150 systems · 7 empires · about 21 systems each", and whether that is crowded (early wars), balanced or spacious, as the counts change. Alone in the galaxy, it says so. |
| Connect | "Lan game at:" over an empty box. | "Games on your network" as a section caption; the empty list says how to look, that it is looking, or that nothing answered. |

# Menus, dialogs and overlays

Every popup menu was opened in a real game and captured, along with each dialog and overlay:
- **Menus:** the map, a fleet's "…", End turn's, the turn log's filters, a tech, the "+" categories, the Objects columns, rows and visibility, a hull, a part, part classes, and the build location.
- **Dialogs and overlays:** a hint, a toast, a battle card, the end-of-turn check, victory and defeat.

| Where | Before | Now |
|-------|--------|-----|
| Every menu and tooltip | A plain rounded box; the pointed item filled solid accent; the submenu arrow touching its text. | Cut corners and a shadow like the other floating chrome; the pointed item gets the menu items' tint and accent bar; separators as hairlines; more room between items. |
| Menus with check items | Godot's dark grey check squares, invisible when unchecked. | The check boxes' own outline and accent fill, and round radio marks for one-of-many lists (the build location). |
| End turn's menu | "Send 4 Orders and Start Turn 2" (during turn 2), "Revoke 4 Orders and Restart Turn 2". | "End turn 2" and "Undo this turn's orders (4)", with a tooltip saying what undo takes back. |
| Victory and defeat | A small dialog with one line. | The empire's flag, VICTORY in green or DEFEAT in red in the display face, the empire's name, the line, and what it came to (turn, planets, ships, population). |
| Dialogs | The focus started on the first button, even with a primary one ("Keep playing"). | It starts on the primary choice; on Cancel when the main choice destroys something. |

# Map widgets, screen details and the lobby

The bot captured each of these in a real game:
- **Map:** every map mode, the zoom slider, scale circle and detection ranges, a hovered system, and the map panned away from everything.
- **Screens:** the Objects conditions, a Pedia search, the designer's description, proposing peace, the production planet finder, and a ship's panel.
- **Lobby:** a hosted multiplayer lobby with an AI player added.

| Where | Before | Now |
|-------|--------|-----|
| Map modes | What a mode's colours mean was only in the picker's tooltip. | A small glass caption above the picker explains the mode while it is on (not in the standard map), as wide as the picker. |
| Pedia search | Names shared by two kinds of article showed twice, alike ("Armor Plating", "Armor Plating"). | Such names say their kind ("Armor Plating · Ship part", "Armor Plating · Technology"). |
| Lobby | "Players" and "Chat" in large title type; nothing said what the galaxy size meant. | Section captions as elsewhere; under the preview, the same room line as single-player setup, counting the players and AIs. |
| Hints | "Tip" in plain grey. | A section caption, like the other cards. |

Also captured and found fine: the About tabs (credits, vision, licence, Godot), hints anchored to their control, the turn log, a scout sent across the galaxy.

## The three captures that first failed

Loading the turn-40 save, the bot opened each of them properly. Two of the three hid real bugs.

| Where | Found | Fix |
|-------|-------|-----|
| System panel's list of systems (⌄) | It opened 1 pixel wide: its maximum size was set as (0, 480), and a 0 width caps rather than lifts. Players could never use it. | A real maximum (512 × 480 UI units); a test checks it opens wide enough to read. |
| Production: adding where it can't be built | Add did nothing and said nothing (Scout at a planet without a shipyard). | A note under the stockpile line says the item can't be built there now, and to pick another place or look under Unavailable; any refused change says so. It clears once an order goes through (test added). |
| Production queue item menu | Fine: move, duplicate, rally, show where, Pedia. | — |
| Off-screen pointers | Labels of two targets near the same edge overlapped. | A label that would cover another moves inward from the edge (test added). |

# Themes, small windows and the keyboard

The bot played the same screen tour in the high-contrast theme and in a 1024×640 window. It then walked every menu, dialog and screen with Tab, logging where focus went.

| Where | Found | Fix |
|-------|-------|-----|
| High contrast | Nothing broken. | — |
| Galaxy setup, Game rules step, at 1024 px | The rule-category tabs would not shrink, so the screen grew to 1263 px and Start game went off screen. | The categories scroll with arrows when they don't fit. |
| Title, at 640 px high | The menu column ran 55 px past the bottom and over the website link. | Below 760 px the logo and the gaps shrink; the column stops above the link. |
| Screens | Opening a screen left the focus behind (or nowhere), so Tab did nothing or walked the hidden map. | A screen takes the focus as it opens. Tab goes through its controls in order, then the top bar, never the map behind it. |
| Game menu and dialogs | Tab left them for the top-bar buttons hidden under the dimmed layer. | They keep the focus: Tab and Shift+Tab wrap inside. |
| Nothing focused | Tab did nothing. | Tab starts at the dialog on top, else the first control. |
| Sliders and links | Godot's faint default focus ring. | The theme's focus ring, as on every other control. |

Tests cover the screen focus, the menu and dialog wrapping both ways, and Tab staying off the map.

# Debugging

Five bots played 30 turns each (newcomer, warlord, economist, explorer and auto end turn; about 150 turns in all), and the test suite's log was combed for anything printed, not just failures.

**Fixed**
- The new deferred focus calls captured screens that tests could free first ("Lambda capture … was freed", four times a run). They now look the screen up when they run.
- A screen could try to grab focus after leaving the tree. The off-screen pointers measured a negative area in a tiny window ("Rect2 size is negative"). Both are guarded.
- An integration check crashed on an empty panel instead of failing cleanly.

The suite now runs with no errors in its log, beyond the engine's usual leak report at exit.

**Investigated, not bugs**
- In the long games: no script errors, engine errors or crashes. The only warnings are the container's missing audio device and vsync.
- "Right-click didn't send the colony ship": the bot right-clicked systems that sat under the side panels. With the target in clear map, the order goes through, as a dedicated check showed.
- "Double-clicking a research row didn't queue it" (turn 1 only): the bot clicks while the screen is still opening. A real double-click on a tech card queues it.
- The 18 anchor warnings in the tests come from tests sizing the game before adding it to the tree.

# Resolutions, settings, audio and the start menu

## Resolutions and UI scale

| Found | Fix |
|-------|-----|
| "Automatic" UI scale came only from the display's DPI. Linux and many monitors report 96, so a 4K screen got a tiny 100% interface. | Automatic also follows the window's resolution: 100% at 1920×1080, 135% at 2560×1440, 200% at 4K. It still never leaves less than 1280×720 of room. |
| A manual scale too large for the window (200% at 1280×800) left a 640×400 layout. | A manual scale is capped to what fits; the Options list greys out steps too large for the window and says why. |
| The window could be dragged smaller than the layouts support. | It can't go below 1024×640. |
| A window that fits a scale exactly (2560×1600 at 200%) got 195%: 2.0 / 0.05 is 39.999… in floating point. | The cap allows for the rounding (test added). |
| There was no way to pick a window size, frame-rate limit or vsync, and nothing slowed the game in the background. The original client has several of these options. | A Display page (below), using the original client's option names where they exist. |

## Settings

| Found | Fix |
|-------|-----|
| Changes applied at once but reached the config file only on Save, so leaving Options without Save lost them at the next start. | Every change is saved as it is made; the Save button is gone, and the header says "Saved.". |
| Interface and Sound sat in a fixed left column beside three tabs. On short or wide windows the column was cramped or stretched. | One column of six pages: **Display**, **Interface**, **Sound**, **Gameplay**, **Keyboard shortcuts**, **Advanced**. Each setting has its name, a line saying what it does, and its control. Content is capped at 960 px and centred on wide windows. |
| The **Display** page didn't exist. | Fullscreen; window size (the sizes that fit the screen, greyed out in fullscreen); screen (with more than one); UI scale (showing the automatic value, e.g. "Automatic (135%)"); vertical sync; a frame-rate limit (30, 60, 120, 144 or none); slowing down in the background; an FPS counter. |
| "Reduce motion" was described as "Turn off UI animations in the Godot client." | "Show changes at once, without sliding, fading or counting." |

## Audio

| Found | Fix |
|-------|-----|
| Volumes changed only when the slider was let go, and showed no value. | Volumes change as the slider moves and show a percentage; they are saved when it is let go. |
| The Sounds slider gave no idea of how loud the sounds would be. | Letting go plays a click at the new volume. |
| There was no overall volume. | A master volume (`audio.master.volume`), on the Master bus. |
| Music started at full volume and stopped dead. | It fades in and out over a second and a half. |

## Start menu

| Found | Fix |
|-------|-----|
| The mouse and the keyboard could light two entries at once. | Pointing at an entry focuses it, so one entry is lit and its description shows. |
| Load Game opened an empty list when there were no saves. | It is greyed out, with "No saved games yet" as its tooltip, until there is a save. |

The bot played its tour at 1366×768, 2560×1440, 3840×2160 and 2560×1080 (ultrawide): no errors and no controls off screen. At 4K automatic scale picks 200%, giving the same layout as 1080p; the ultrawide's research grid takes five columns. Along the way:
- The bot sent its clicks in logical coordinates where Godot expects window pixels, so it missed at any scale but 100%.
- The visual tests now hide GUT's own panel while capturing, since it can show at the edges after a scale change.

## Battles, the Pedia's kinds, designing, government, objects and the feed

The bot played until its first battle (turn 16, a scout lost at Thrax). It then went through:
- the combat report: the whole battle, bout 1, and scrolled to the log;
- one Pedia article of each of the 13 kinds;
- designing a ship from a hull and a weapon, then creating it;
- adopting a policy by drag and drop;
- the objects list under each of its four groupings;
- the feed's filter menu and an entry's menu.

It then loaded a turn-40 save to check the fixes.

| Found | Fix |
|-------|-----|
| After Create design, the designer was 1388 px wide in a 1280 px window: the header's status ("Created Deep Lancer. It can be built from the production screen.") would not wrap, so the parts column was pushed off screen. The same header is on 13 screens; Government's was 20 px too wide in its golden image. | A header's info line takes the spare width and wraps, right-aligned. |
| A combat in the list cut a long system name short, and the full name was not available. | The card's tooltip gives the system, the turn and the losses. |
| "Whole combat" was greyed out with no reason when the whole combat was already shown. | Its tooltip says so. |
| Government listed policies by name, so a greyed "no free slot" policy could come before ones you could adopt. | Policies you can adopt now come first, then the others, each group by name. |
| An empire's Pedia article had two rows called "Planets": a count, then the list. Slot counts read "1.00". All 50 species were listed with their opinion, most of them 0. | The planet list's caption counts it ("Planets (6)"), as any list of more than three links does. Whole numbers show without decimals. Only species with an opinion are listed, fondest first. |

Checked and left alone:
- Opening the Pedia puts keyboard focus on its first kind ("Technology"), as every screen focuses its first control. Starting in the search field instead would make Esc leave the field rather than close the screen.
- The bot's own policy drop asked for a slot that didn't exist: it chose "adoptable" without checking for a free slot. The screen showed "no free slot" and kept Adopt greyed out.

## Debug round: a long game, frame times, screen times and leaks

The bot can now report each turn's frame count, average and worst frame time, memory, object and node counts, stray (orphan) nodes, and any frame over 250 ms with the screen it was on (`PERF=1`). It played 100 turns as the economist. An AI took its capital at turn 100: the Defeat screen came up with the right summary ("Turn 100 · 0 planets · 0 ships · population 0.0") and Keep watching worked.

Over the 100 turns (software rendering under Xvfb, so absolute times are slow; the trend is what counts):
- Memory went from 107 MB at turn 2 to 117 MB, nodes from 1,666 to 2,371 and objects from 5,887 to 7,767, in step with what the empire knew of the galaxy.
- The average frame time held flat at 90–118 ms.
- The only frame spikes were turn arrival (250–480 ms) and opening production (260–390 ms).
- No stray nodes.
- No script errors or warnings, apart from the headless machine's lack of audio and vsync.

The bot then timed each screen's open and refresh three times on a turn-40 save:

| Screen | Before | After | Cause |
|--------|--------|-------|-------|
| Design | 170 ms every time | 60 ms | Symbols on buttons that neither UI font has ("⋯", "✕", "▲", "↺", "✓") made Godot search the system's fonts every time a button with one was shaped: about 2 ms a button, 40 rows × 2 buttons. DejaVu Sans (already shipped) is now the fonts' last fallback, so these never reach the system search. |
| Production | 57 ms | 25 ms | Each queue row's locate button ("⌖", which no shipped font has) did the same before it became an icon. `ScreenKit.small_button` now swaps a glyph for its icon before the button enters the tree. |
| Research | 55 ms | 35 ms | The same symbols. |
| Government | 22 ms | 17 ms | The same symbols. |
| Objects, Combat, Empires, Pedia | 1–15 ms | unchanged | |

Design rows' "⋯" menus are also filled only when opened, like production's.

Leaks:
- **Fixed:** selecting a system left one or two stray nodes per planet behind on every refresh: each planet row built a box for its output chips and one for its actions, and dropped them unfreed when they had nothing in them. Nine strays per refresh of the capital's panel, all game long. A new test refreshes a system with such planets and checks that nothing is left behind.
- **Not a leak:** the test suite's remaining orphans (three, in the audio and tooltip tests) are the tests' own nodes. FleetPanel and the map view, built and freed alone, leave nothing.

Not bugs:
- The bot's "Evacuate Planet didn't queue" was the confirmation the game asks for before a destructive item.
- "A research row didn't queue" was a double-click while the screen was still opening, as before.

## Menus and saving / loading

The bot loaded a turn-40 game and then:
- opened the game menu and saved under a new name;
- saved again under the same name typed in, picked an existing save to save over, and saved under the names "../weird:name/.sav" and "with extension.sav";
- opened Load, sorted it, picked a save and asked to delete it, then moved through the list with the arrow keys;
- asked to quit to the title, then loaded its own save from inside the game;
- went back to the title, with its Continue line and its Load screen.

A separate script loaded a save from inside a game twice (turn 40 to 25, and turn 25 to 40, from a save this client made) to check that loading during a game lands in the chosen game. It does: the bot's earlier turn-1 result was its own click on a scrolled-away card.

| Found | Fix |
|-------|-----|
| The loading screen's tip showed markup: "<encyclopedia OUTPOSTS_TITLE>Outpost</encyclopedia> … <metertype METER_SUPPLY>…". A tip's links were replaced by the names they stand for, and those names hold markup of their own. | Tips are plain text. A test reads every tip. |
| Typing the name of an existing save and pressing Save replaced it without a word. Only picking its card said "Saving will replace this save". | Typing an existing name picks its card and says so. Saving over a save, typed or picked, asks first ("Replace the save Audit save? This can't be undone.", with Cancel focused). |
| A name typed with its extension was saved as "name.sav.sav"; "../weird:name/.sav" became ".._weird_name_.sav.sav". | A typed ".sav" (or ".mps") is dropped before saving. The screen works out the file name the same way the save code does, so the name it checks for is the name that gets written. |
| Loading another game from inside a game ended the running one at once, though Quit to title asks first. | It asks the same question and says when the game was last saved. |
| Cancelling a dialog (Delete's, say) left nothing focused: the arrow keys did nothing until a click. | Dialogs give the focus back to what had it. |
| Times read "2026-11-17 01:47" even for a save made a minute ago. | "today 01:47" and "yesterday 23:41", then the date. The same in the quit confirmation ("Last saved on turn 40, today 02:02.") and on the title's Continue line, which now says when as well ("Terran Imperium · Turn 40 · today 02:02"). |
| Autosave cards showed their generated file name ("Autosave · FreeOrion_Human_Player_Terran_0002_20261117_014259.sav · …"). With an autosave a turn, they pushed named saves down the list. | "Autosave · today 02:01", with the file name in the tooltip (every card's tooltip starts with its file). An **Autosaves** toggle in the Load screen's header hides them; it only shows when there are autosaves. |
| A save could only be loaded by picking it and then pressing Load. | A double click loads it (or, when saving, saves over it, after asking). |

Checked and fine:
- Saving closes the screen with "Saved Audit save.sav.".
- The game menu's buttons, sort orders, the delete confirmation, the empty Load state and the multiplayer server listing were already in order.

## Galaxy setup and the multiplayer lobby

The bot went through galaxy setup:
- each step;
- three of the rule categories;
- the largest and smallest galaxies (5,000 systems with 40 AIs; 10 systems alone);
- blank names and a 70-character empire name;
- Tab from the player name.

Then it hosted a multiplayer game and in the lobby:
- added AI players, once and then three times quickly;
- chatted and changed the galaxy size;
- switched to a loaded game and picked a save;
- switched back, and shrank the window to 1024×640, the smallest it can be.

| Found | Fix |
|-------|-----|
| With both names blank, Start game was ready to go, and the identity card showed a flag with no name. | Start is greyed out with "Type a player name and an empire name first (Empire step)"; the card says "Unnamed empire", faintly. |
| The Empire and Galaxy steps' fields started at different x (each grid sized its own labels), so the form jumped sideways between steps. | Both steps' labels take the width of the widest. |
| A 10-system galaxy's preview drew 240 stars, as many as a 60-system one. | Four stars a system, at least 40. |
| Three quick clicks on "+ Add AI" added one AI (named AI_4: the server had numbered the lost ones). Each edit started from the lobby the server last sent, so an edit made before it answered dropped the one before. | Edits build on the last one sent until the server sends the lobby back. |
| "Unique names and colors required" stood under the players even when every name and colour was unique, in the same grey as everything else. | "All set: the game starts once every player is ready." When something is wrong it says what, in the warning colour: "Two empires are called Peace: each needs its own name.", "Unity and Region have the same colour: each needs its own.", "Bob's empire needs a name." |
| In a loaded game the condition read "Not enough human players" (the server's words) when the player had simply not picked their empire. | "Pick the saved empire you will play, next to your name." A greyed-out Start says the same in its tooltip, and greyed-out empire pickers say why. |
| Picking a save in the lobby widened it to 1376 px in a 1280 px window: the picker sized itself to the save's path ("auto/FreeOrion_Human_Player_Aristocracy_0002_20261115_234335.mps"). | The picker and the label above it cut the name short; the tooltip has it. |
| At 1024×640 the lobby needed 1114 px: player rows had fixed widths (name 140, species 170). | Narrower minimums. The spare width on bigger windows goes to names and species as well as empire names, so at 1280 every name shows in full, and at 1024 the longest are cut short with a tooltip. A test checks the lobby fits the smallest window, with a long save name too. |

## In-game screens at 1280 × 800 and at 1024 × 640

The bot loaded a turn-40 game and went through every in-game screen, panel and window at 1280 × 800 and at 1024 × 640, the smallest the window can be.

| Found | Fix |
|-------|-----|
| At 1024 × 640 the game drew at 100% on a 1024-px-wide screen, though its layouts need at least 1280 (the top bar alone 1200). Everything ran off the right edge: End turn and Menu were out of reach, and the minimap was cut in half. The bot's turn never ended. The automatic scale had a floor of 100%, so it never shrank below it. | A window smaller than the layouts draws them smaller, down to 75%: 80% at 1024 × 640, a logical 1280 × 800. The same cap applies to a chosen scale. Every screen then lays out as at 1280; the tour found nothing off screen. |
| A planet's Pedia article listed every meter, "Population: 0.00" through "Troops: 0.00": eight lines of zeros for an unowned planet. It had no picture, though every other kind of article has one. | Meters at 0 are left out, numbers have no needless decimals, and the article shows the planet as the map's panels draw it: its surface, atmosphere and star light. |
| A fleet between systems with no next stop had a blank Location in the objects list. | "Deep space". |

Checked and fine at both sizes: production, research (list and tree), government, design, objects (each tab), combat, empires (both tabs), the Pedia's tech, species, planet and empire articles, the map with the system, planet, fleet and ship panels, the Messages window, the game menu and dialogs.

### Debugging after the in-game pass

- **An 80-turn warlord game at 1024 × 640** (now drawn at 80%, with fleets fighting from turn 20 on): memory went from 125 to 128 MB and objects stayed around 9,500, nodes around 3,000, with no stray nodes. There were no script errors or warnings beyond the headless machine's audio and vsync. The only "bug" the bot reported was its own turn-1 double click while the research screen was still opening, as before.
- **Leaks at exit:** the bot's logs end with "ObjectDB instances leaked at exit". A verbose run that loads a game and leaves with the game menu's Exit, as a player does, leaks nothing; the warning comes from the bot stopping the engine mid-game, which no player can do.
- **Frame time at turn arrival:** the frame a turn arrives on took 300–640 ms, growing as the galaxy fills. Timing each turn listener on a turn-40 save, all of them together take under 15 ms. The frame after them is about 65 ms longer than a quiet one, and a map refresh adds nothing measurable. The rest is the client unpacking the server's turn update (C++), which grows with what the empire knows. No UI change helps there.
