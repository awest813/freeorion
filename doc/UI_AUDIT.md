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
