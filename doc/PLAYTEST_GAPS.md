# Persona playtests: gap list

Twenty single-player games of the Godot 4 client, played by a scripted bot
through the real UI: mouse clicks and keys sent to the window, the same buttons,
menus and hotkeys a person uses. Five personas, four games each, at 1280×800.

## How the games were played

| Run | Galaxy | AI empires | AI aggression | Turns |
|-----|--------|-----------|---------------|-------|
| 1 | 150 systems, 2-arm spiral | 6 | Maniacal | 30 |
| 2 | 40 systems, 4-arm spiral | 2 | Beginner | 30 |
| 3 | 250 systems, elliptical | 10 | Typical | 25 |
| 4 | 80 systems, box | 4 (none for the power user) | Maniacal | 30 |

| Persona | Plays like | Uses |
|---------|-----------|------|
| **Newcomer** | Has never played; does only what the game points at | Turn readiness links, first-time tips, Pedia "?" buttons, the first catalogue item |
| **Warlord** | Wants a fleet and a war | Ship designer every 8 turns, warship production, attack by map right-click, Empires screen and diplomacy |
| **Economist** | Builds the economy | Planet focus, Buildings tab, policies, research queue reordering from the tech menu |
| **Explorer** | Expands | Explore from the fleet menu, colony and outpost ships sent by right-click, the system panel's Colonize and Outpost buttons |
| **Power user** | Keyboard only | F-key hotkeys for every screen, F5 quick save, F10 options, auto end turn |

All 20 games ran from setup to their last turn with **no script errors**.
Average turn processing was 0.4–1.2 s; power-user run 1 averaged 25 s over
100 turns against 6 Maniacal AIs.

| Persona | Planets at end (runs 1–4) | Ships at end | Notes |
|---------|---------------------------|--------------|-------|
| Newcomer | 1 / 1 / 1 / 1 | 4 / 4 / 4 / 4 | Never expanded; 95–140 IP unspent |
| Warlord | 1 / 1 / 1 / 1 | 11 / 12 / 9 / 12 | 3 designs each game; never found an enemy |
| Economist | 1 / 1 / 1 / 1 | 4 each | Capital evacuated by accident; PP and RP 0 by turn 20 |
| Explorer | 1 / 1 / 3 / 3 | 10 / 13 / 6 / 4 | Colonised only in the large galaxies |
| Power user | 0 / 1 / 1 / 0 | 0 / 4 / 3 / 0 | Auto end turn ran to turns 103, 374, 99 and 333; eliminated twice |

## Severity

- **S1**: loses the game or wrecks the empire with no warning.
- **S2**: blocks a goal, or a player can't tell what to do next.
- **S3**: friction or a misleading label.

**Fixed** means fixed in this branch, with a unit test, in commit `c44827f`.

## Gaps

### S1

1. **Evacuate Planet could be queued on the capital without a warning.** **Fixed.**
   - Evidence: economist, all 4 games. "Evacuate Planet" sorts first in the Buildings list. A double-click queued it on the capital, and by turn 20 PP and RP were 0 for the rest of the game. "Abandon Outpost" was queued the same way.
   - Fix: adding a building that empties or destroys planets now asks first, naming the building and the planet. This covers Evacuation, Abandon Outpost, Concentration Camp, Gateway to the Void and Nova Bomb Activator.
2. **Auto end turn keeps going through a war.**
   - Evidence: power user, runs 1 and 4.
     - Run 1: eliminated on turn 102 against Maniacal AIs.
     - Run 4: with no AIs at all, eliminated on turn 333, presumably by monsters.
     - Both times auto end turn kept ending turns while planets were attacked and lost.
   - GG behaves the same way.
   - Suggested: stop auto end turn when there is combat at an own system, an own planet is lost or depopulated, or an enemy armed fleet is seen in supply range. Show a toast saying why it stopped.

### S2

3. **The starting scouts never explore unless told to.** **Fixed.**
   - Evidence: newcomer, all 4 games. The two scouts sat at the home system for 30 turns. The readiness check only named colony ships and fleets built this turn, so the newcomer was never pointed at them. All four newcomer games ended with 1 planet.
   - Fix: the readiness check now names unarmed fleets that are idle and not exploring, with a link to the fleet. Its text says "set it to explore (fleet menu)".
   - Still open: GG starts the initial scouts exploring on its own. Consider the same, or a one-time tip on the fleet panel's Explore entry.
4. **Influence piles up unused.** **Fixed.**
   - Evidence: newcomer, warlord and explorer ended with 95–140 IP unspent. The power user's run 2 ended with 1,501 IP.
   - Nothing pointed a player who doesn't open Government at their free policy slots.
   - Fix: the readiness check names each policy category with a free slot while an available, affordable policy could be adopted into it. The link goes to Government.
5. **An idle colony ship gets a link but no guidance.**
   - Evidence: newcomer, all 4 games. The readiness link went to the ship's system, which had no planet it could settle, so no Colonize button was in view. The newcomer had no way to find a target.
   - Suggested: from the readiness item or the fleet panel, offer "nearest planet this ship can settle" with its target population. Show settle targets on the map while a colony ship is selected, as GG does.
6. **No way to find the enemy.**
   - Evidence: warlord, all 4 games. Empires lists every AI as "At war", but in 25–30 turns the warlord never located an enemy planet. Neither the Empires screen nor the map shows where an empire is.
   - Suggested: on the Empires screen, "show on map" for each empire's known capital or nearest known planet. List known enemy systems in Objects with an "owner" filter.
7. **Move orders refused without a reason.**
   - Evidence: explorer, 15 of 22 moves by right-click were refused across the 4 games. The notice says only "The selected fleet can't move to that system." A player can't tell whether the cause is no known route, too little fuel, or that the system isn't explored yet.
   - Suggested: give the reason in the notice. Before the click, draw the would-be route in a warning colour when it's out of range.
   - Caveat: some of these clicks needed a map pan first (see 14), so not all 15 are game refusals.
8. **The Ships list was empty at the default location once.**
   - Evidence: explorer runs 3 and 4, turns 15 and 22. The Ships tab showed "nothing buildable" for the selected location. The next turn it listed ships again.
   - Suggested: when the location can't build ships, say why ("no shipyard here") and offer the nearest location that can.
   - Not yet reproduced by hand.

### S3

9. **Policy cost labels said "per turn".** **Fixed.**
   - The Government header said "policies cost 0.0 IP/turn" while each policy said "N IP per turn".
   - Adoption cost is in fact charged once, on the adoption turn. The engine's influence queue counts only this turn's adoptions, and the AI code says "adoption cost is a one-time cost".
   - Fix: the header now says what adopting this turn costs, each policy says "N IP to adopt", and the Government first-time tip was corrected.
10. **"Stockpile Transfer" was first in the production "All" list.** **Fixed.**
    - Evidence: newcomer. The project is for experienced players, and a newcomer queuing the first item got nothing visible from it.
    - Fix: it now comes last.
11. **The readiness check nags about partly used PP.**
    - Evidence: newcomer, 15 times. Items were queued but couldn't take all PP because of minimum build times, and the dialog came up every turn.
    - Suggested: when the unspent share is small, or the only cause is minimum build times, say so once ("N PP can't be spent this turn: add another item to use it") and don't repeat it every turn.
12. **The message log grows to 40+ unread.**
    - Evidence: the message badge read 41 on turn 20 (explorer run 2, screenshot). Nothing marks messages read unless the log is opened, and the badge only grows.
    - Suggested: mark a turn's messages read when the next turn starts with the log closed, or add a "mark all read" button.
13. **New designs can leave slots empty without a word.**
    - Evidence: warlord. Designs were created with empty external slots.
    - Suggested: warn on Create when slots are left empty. The duplicate-design refusal is already clear: "This design is a duplicate of …".
14. **Map targets can be off screen.**
    - Evidence: explorer runs 1, 2 and 4. The nearest free system was off screen and the map had to be panned.
    - Suggested: let a readiness or "nearest target" link centre the map on the target. The minimap already allows a quick jump.

## Not confirmed as game gaps

These came from the bot and could be harness timing, not the game:

- **The first double-click on a freshly opened list didn't queue.** This happened once per game in research (warlord, economist, power user) and production (explorer, turn 1). Later double-clicks on the same lists always worked. The bot clicks in the same frame it scrolls the row into view, so the row may not have been laid out yet.
- **F2 didn't open Production on turn 1.** Power user, runs 1–3. Every other hotkey, and F2 itself from turn 2 on, worked.
- **The Defeat dialog stayed up.** The bot dismisses only OK, Keep playing and Close. Defeat offers Quit to title and Keep watching, as intended.

## What worked well

- Hotkeys (F2–F9 for screens, F10 options, F5 quick save) opened the right screens.
- From the Government screen: adopting policies into slots.
- From the system panel: setting capital focus to Industry.
- From the research tech menu: "move to top", 15 of 15 times.
- From the fleet menu: setting scouts to explore.
- Colonising from the system panel's Colonize and Place Outpost buttons: all 8 settle attempts worked.
- Designing warships and queueing them in production, with 9–12 ships by turn 30.
- Opening the Pedia from the "?" buttons, and its links.
- Quick save from the keyboard.
- No script errors and no crashes in about 1,000 played turns.
