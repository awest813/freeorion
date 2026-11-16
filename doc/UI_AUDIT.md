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
