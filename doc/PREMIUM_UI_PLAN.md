# Premium 4X look: plan for the Godot 4 client

This plan aims to make the client look and feel like a commercial 4X game, in the vein of Stellaris, Endless Space 2 or Galactic Civilizations IV. It keeps everything that works today: the flows, accessibility, tests and readable information. The plan builds on the design tokens (`godot4/ui/tokens/FOTokens.gd`) and the theme builder (`godot4/ui/theme/FOThemeBuilder.gd`), not around them.

## Where the look is today

These observations come from screenshots of every screen at turn 15 of a real game. See `doc/PLAYTEST_GAPS.md` for how those games were played.

| Area | Today | What reads as "not premium" |
|------|-------|-----------------------------|
| Type | Roboto everywhere; at most 26 px for headings. | No display face and no hierarchy beyond size. Titles look like web-app headers. |
| Panels | Flat `#11151b`–`#242c37` fills with 1 px borders and 6 px radius, fully opaque. | No depth, material or frame. Every panel is the same box. |
| Full screens | Production, Research, Government and the rest are opaque pages of rows with "Add" buttons. | The galaxy disappears, and screens feel like spreadsheets. |
| Galaxy map | Flat star sprites, lines for lanes, translucent supply discs, no post effects. | No glow, no territory shapes, nothing moves. |
| Planets | Small static icons in the side panel, planet panel and Pedia. | 52 planet surface textures with bump maps sit unused, and planets never look like worlds. |
| Species | Shown as text, with a small 16 px icon in pickers. | 27 portraits at 500×500 are used only in the Pedia. |
| Motion | Panels fade in; nothing else animates. | No feedback when turns, numbers or selections change. |
| Front end | The title screen has GG's background and a boxed button list. Galaxy setup is a long form. | Galaxy setup looks like a settings page, and its shape previews are GG's dated art. The disc preview is a large white circle. |
| Sound | `FOAudio` has clicks, rollovers and one music track. | Sound isn't tied to the moments that matter: end of turn, combat, a discovery. |

**Constraints:**
- **Renderer:** Godot 4.4 on GL Compatibility (`project.godot`). Custom canvas shaders, the screen texture (for blur) and 2D glow are all available.
- **Shaders:** there are none in the project yet.
- **Licensing:** art and fonts must be free to redistribute, CC-BY-SA or SIL OFL like the rest of FreeOrion.
- **Accessibility:**
  - every new effect follows `FOUi.reduce_motion`;
  - the high-contrast tokens (`high_contrast.tres`) must keep working;
  - UI scale must keep working from 100% to 200%.
- **Code checks:** the checks stay on — no colour literals outside tokens (`tools/check_theme_literals.py`), gdlint, and the visual goldens.

## Direction

The proposed visual identity is "**observatory glass**": dark translucent panels over a living galaxy, lit by thin luminous edges in the empire's colour.

**Typography**
- A geometric display face for titles, numbers and the top bar. Candidates are **Exo 2** or **Rajdhani**, both SIL OFL.
- Roboto stays as the body face.
- Small caps with letter-spacing for section headers.

**Panel chrome**
- Glass: the map shows through, blurred and darkened.
- One chamfered corner.
- A 1 px top highlight.
- A hairline in the accent or empire colour.
- A faint noise texture so large fills aren't dead flat.

**Colour**
- Keep the neutral blue-grey surfaces.
- The accent follows the **player's empire colour**, as Stellaris does, clamped to readable lightness.
- Resources get one fixed hue each: industry amber, research cyan, influence violet, population green.

**Content first:** planets, species portraits, ship hulls and tech art become large and central. The interface frames them instead of listing them.

**Decision for you:** this direction, or one of two alternatives:
- **Military brass:** gold and steel, heavier frames, as in Sins of a Solar Empire.
- **Minimal holographic:** cyan line work with almost no fills, as in Endless Space 2.

The phases below hold for any of the three. Only Phase 0's values change.

## Phases

Each phase ships on its own, keeps the tests green, and updates the visual goldens on purpose. Effort is rough, in working days for one developer.

### Phase 0: foundation (tokens, type, chrome), about 4 days

The biggest change for the least code: every screen picks it up through the theme.

1. **Tokens v2** (`FOTokens.gd`, `default.tres`, `high_contrast.tres`). New tokens:
   - `glass_fill` (with alpha), `glass_blur`;
   - `edge_highlight`, `chamfer`;
   - the font roles `font_display` and `font_numeric` (tabular figures);
   - a fixed hue per resource (`res_industry`, `res_research`, …);
   - `accent_from_empire` (on or off).
2. **Fonts:** add the display font to `godot4/assets/fonts` with its licence. Add theme type variations `DisplayTitle`, `SectionCaps` and `Numeric` in `FOThemeBuilder`.
3. **Glass panel:** a `glass_panel.gdshader` (screen-texture blur, darken, noise) plus a `StyleBoxTexture` or `NinePatch` frame with chamfer and top highlight.
   - Use it for `PanelContainer` variations `GlassPanel` and `GlassCard`.
   - Fall back to an opaque fill in high contrast and in the "reduce transparency" option, which is new.
4. **Empire accent:** at game start, derive accent, hover and pressed colours from the empire colour, clamped for contrast (WCAG 4.5:1 on text over accent). The title screen keeps the default blue.
5. **Icon pass:**
   - Interface chrome (close, arrows, menu, add, remove, pin) moves to one monochrome line set, tinted by tokens.
   - Game content (meters, techs, buildings, parts) keeps GG's art.
   - Reuse `FOArt`; add a `ui_icons/` set, drawn or taken from an OFL or CC-BY icon font.
6. **Accept when:**
   - the component gallery (`ui/ComponentGallery.tscn`) shows the new chrome in default and high-contrast themes;
   - goldens are updated;
   - no literal-colour check fails;
   - text contrast is still at least 4.5:1.

### Phase 1: a living galaxy map, about 6 days

Layers in `godot4/map/GalaxyMap.gd` and `FleetLayer.gd`; shaders in `godot4/map/shaders/`.

1. **Stars:** a shader core with soft halo in the star's colour, slow twinkle, and size by star type. Black holes get an accretion ring and neutron stars a pulse. Glow comes from 2D HDR plus `WorldEnvironment` glow, with a fallback of a pre-blurred halo texture.
2. **Backdrop:** parallax layers (starfield, nebulae from `art/nebulae`, a faint galactic dust gradient by galaxy shape). The camera moves them at different rates.
3. **Territories:**
   - Replace the supply discs with smooth empire-coloured regions: a signed-distance field from owned or supplied systems, drawn by shader with a soft fill and a crisp border line.
   - Contested borders get hatching.
   - This is the single most "4X" visual.
4. **Starlanes:**
   - Thin, slightly glowing lines.
   - Lanes inside your supply are tinted with your colour.
   - Routes animate flow: dashes moving towards the destination.
   - The preview route keeps its warning red.
5. **Fleets:**
   - Owner-colour glow under the icon.
   - Selected fleets get a rotating ring.
   - Moving fleets get a short motion trail.
   - Combat systems get a pulsing red ring for the turn.
6. **Selection and hover:**
   - The system ring animates in.
   - The hovered system's name chip slides out.
   - The places-to-settle rings, edge pointers and route chips adopt the new chrome.
7. **Level of detail:**
   - Zoomed out: territories and empire names (large, letter-spaced, as in Stellaris) instead of system names.
   - Zoomed in: planets orbit as tiny dots around their star.
8. **Accept when:**
   - 60 fps at 1080p with 250 systems and 10 AIs on integrated graphics, which needs a scripted perf scene;
   - reduce-motion turns off twinkle, flow and trails;
   - the existing map tests and the synthetic map golden are updated.

### Phase 2: worlds and peoples, about 5 days

1. **Planet spheres:**
   - A `planet_sphere.gdshader` maps the equirectangular textures in `art/planets` onto a lit sphere, using the bump maps for relief.
   - It adds atmosphere rim light in the planet type's colour, a terminator lit from the side of the system's star in the star's colour, and slow rotation.
   - Gas giants get banded flow; asteroids keep their art.
   - One `PlanetView` control is used by the system panel (rows), planet panel (large header), Pedia, colonise prompts and places to settle.
   - Render to a `SubViewport` cache per planet type and size, so a system with 8 planets costs little.
2. **Species portraits** (`art/species`, 27 at 500×500):
   - a large portrait in the planet panel header next to the planet;
   - a portrait card in the galaxy-setup species picker, with environments and traits;
   - a portrait on each Empires card and in diplomacy proposals;
   - a small round avatar in pickers.
3. **Empire identity:**
   - the flag (`icons/flags`) and colour in the top bar, Empires cards and turn banner;
   - the empire name in the display face.
4. **Accept when:**
   - the planet panel golden shows a lit sphere and portrait;
   - shader fallback to the flat icon works with "reduce effects";
   - no frame drops when scrolling the Objects list with 100 planets.

### Phase 3: screens as overlays, not pages, about 8 days

Every full screen (`show_screen` in `GameShell.gd`) becomes a glass overlay over the dimmed, blurred live map. The galaxy is always there.

1. **Screen shell:**
   - one `ScreenFrame` with display-font title, section caps and close button;
   - optional left navigation and a context strip with points, cost and turns in the numeric face;
   - a 180 ms slide-and-fade in and out.
2. **Research:**
   - the catalogue becomes a grid of **tech cards**: large icon, category colour band, cost and turns, and "unlocks" chips for buildings, parts and hulls;
   - the queue becomes a vertical timeline with turn markers;
   - the tree view gets category lanes and glowing links for queued paths.
3. **Production:**
   - ship rows show hull art large;
   - buildings show their building art;
   - the queue items show progress rings and "done in N turns" in the numeric face;
   - an empty state when nothing is queued: art plus the suggested next item.
4. **Government:**
   - policies become **cards** in slot frames shaped by category (economic, social, military colour);
   - drag a card into a slot;
   - adoption cost on a ribbon;
   - an "affordable" glow.
5. **Empires:**
   - portrait cards with relationship status as a coloured ribbon;
   - relative power bars (ships, planets, output) compared with yours;
   - "Show on map" kept.
6. **Objects:**
   - table chrome restyled (sticky header, zebra rows from tokens, numeric face);
   - planet rows lead with `PlanetView` minis.
7. **Combat:** a hero header with system art, the sides' portraits or flags, and a large win or loss banner. The existing breakdown is restyled into the new cards.
8. **Pedia:**
   - article header art (planet sphere, portrait, tech icon) large;
   - a "related" chip row;
   - the category index tiles use the new card style.
9. **Accept when:**
   - each screen's golden is updated, including the de, ru, 150% and 200% variants;
   - persona harness runs still pass, using the same buttons by text.

### Phase 4: turn rhythm, motion and sound, about 4 days

1. **End turn:**
   - a hero button in the top-right with turn number, a readiness count badge and a progress ring while the server and AIs process;
   - a short "Turn N" banner with the empire flag on arrival;
   - all of it skippable.
2. **Numbers:**
   - top-bar resources tick to their new values;
   - change arrows fade in;
   - each resource's tooltip has a sparkline of the last 20 turns (data from Empires statistics).
3. **Notifications:**
   - turn events become a right-edge stack of cards (icon, title, one line, a link) that slide in;
   - the important ones (combat, planet lost, enemy sighted) are emphasised and stay until dismissed;
   - the log panel stays for history.
4. **Feedback:** hover lift, glow on buttons and cards, press depression, a check animation when an order is given (queued, adopted, sent).
5. **Sound:**
   - map `FOAudio` events to moments: turn end and start chime, combat sting, research complete, colony founded, warning tone for auto-turn stops;
   - ambient music crossfades between calm and war tracks, using GG's music;
   - volumes come from the existing options.
6. **Accept when:**
   - reduce-motion removes every animation listed;
   - sounds respect the options;
   - turn time isn't lengthened: the banner overlaps processing.

### Phase 5: front end, about 4 days

1. **Title:**
   - an animated backdrop: slow parallax of nebula and starfield, and one large `PlanetView` sphere rotating;
   - the logo with a subtle glow;
   - a borderless, left-aligned menu in the display face, with the hover line in the accent;
   - "Continue" as a hero card showing the last save's empire, turn and flag.
2. **Galaxy setup** becomes a three-step flow (*Empire* → *Galaxy* → *Rules*) instead of one long form:
   - Empire: species portrait cards, colour swatches and flag.
   - Galaxy: shape cards drawn **procedurally**, which replaces GG's dated previews and its blank disc image. A size slider shows the star count, and age and density are shown with small icons.
   - Rules: advanced options.
   - "Quick start" stays one click.
3. **Loading:**
   - a full-screen backdrop with the empire flag, a rotating tip from the Pedia and real progress steps;
   - the stages are known: server start, galaxy, AIs.
4. **Lobby and connect:** restyled with portraits and flags per player.
5. **Accept when:**
   - the menu flow playtest (title to game and back) and persona harness still pass;
   - setup and title goldens are updated.

### Phase 6: consistency and quality, about 3 days

1. A visual audit of every screen, panel and dialog at 100%, 150% and 200%, and in de and ru, using the screen-tour harness. Fix overflow, clipping and alignment.
2. A performance pass on integrated graphics and software GL (xvfb), with fallbacks verified.
3. Update `godot4/ui/README.md` into a style guide: tokens, type roles, chrome variations, motion timings, iconography rules, do and don't screenshots.
4. Run a 20-game persona playtest again to make sure the new look didn't hide anything players relied on, such as buttons, links or numbers.

## Order and size

| Phase | Effort | Impact | Depends on |
|-------|--------|--------|------------|
| 0 Foundation | 4 d | Every screen at once | — |
| 1 Living map | 6 d | The screen players see most | 0 for chrome |
| 2 Worlds and peoples | 5 d | Content becomes the star | 0 |
| 3 Screen overlays | 8 d | Screens stop looking like spreadsheets | 0, 2 |
| 4 Rhythm, motion, sound | 4 d | Feel | 0 |
| 5 Front end | 4 d | First impression | 0, 2 |
| 6 Consistency and quality | 3 d | Finish | all |

That is about 34 working days in total. Phases 1, 2 and 4 can run in parallel after Phase 0. Suggested order for a visible step each week: 0 → 2 → 1 → 5 → 3 → 4 → 6, with planets and portraits early because they pay off everywhere.

## Risks

- **Performance on the compatibility renderer.**
  - Blur, glow and SDF territories cost fill rate.
  - Mitigation: a quality setting (Low, Medium, High) and cached render targets. Blur only once per frame behind all overlays, not per panel. Use pre-blurred fallbacks.
- **Readability.**
  - Glass and glow can reduce contrast.
  - Mitigation: every glass fill has a minimum darkening, text never sits directly on the blur, a contrast check runs in tests, and high contrast disables glass.
- **Art licensing.**
  - Mitigation: only OFL fonts, and only art already in `default/data/art` or newly made under CC-BY-SA.
- **Test churn.**
  - Goldens change in every phase.
  - Mitigation: regenerate per phase in one commit with screenshots in the message, and keep behaviour tests independent of look (text and signals, not pixels).
- **Scope creep.**
  - Mitigation: each phase has acceptance criteria above; anything else goes to a follow-up list.


## Status

The plan was carried out in the "observatory glass" direction, in the order 0 → 2 → 1 → 5 → 3 → 4 → 6. The style guide is `godot4/ui/README.md`.

| Phase | Done | Not done (follow-ups) |
|-------|------|-----------------------|
| 0 Foundation | Tokens for glass, edges, shadows, cut corners and display type. Glass shader on floating panels, the top bar and screens. Exo 2 display face, `SectionCaps` captions. Empire accent, readable at 4.5:1. Options `ui.glass` and `ui.accent.empire`. Monochrome interface icon set. | — |
| 2 Worlds and peoples | Planet spheres from GG's surface art (system and planet panels). Composed empire flags (top bar, Empires, setup, turn banner). Species portraits (planet panel, Empires, setup, Pedia). | Spheres in the Objects list: skipped, since list rows can't hold a live sphere and a ~20 px icon gains little from one. No sphere cache: the spheres render fast enough without one. |
| 1 Living map | Territory regions with borders. Twinkling stars with hot cores. Parallax nebulae. Lane glow. Fleet glow and turning selection ring. Empire names when zoomed out. Routes flow toward their destination. Zoomed in, planets orbit their stars in their type's colour. | — |
| 5 Front end | Title screen with a glass column, menu in the display face and drifting splash. Loading view with spinner and tips. Drawn galaxy-shape previews in setup and the lobby. Identity card in setup. Setup in three steps: empire, galaxy, rules. | — |
| 3 Screens | Screens settle in over the blurred galaxy. Card rows with category colours in Research, Production and Government. Species paintings in the Pedia. Empires cards weigh each empire's known strength against yours. Research catalogue as a grid of tech cards (art, category band, cost, unlock chips) and the queue as a timeline marking the turn each tech is done. Combat reports open with a header: both sides' flags and the outcome. | Tree view category lanes and glowing queued paths |
| 4 Rhythm | Turn banner, spinner while the turn is processed, counting resource numbers, sounds for battles and auto-turn stops. Cards for the turn's important events (battles, losses, captures) under the top bar. Music muffles in peace and opens up in war. | — |
| 6 Quality | Every screen checked at 100%, 150% and 200% and in German and Russian (icons were drawn twice too large at 200%; fixed). Style guide written. Persona games re-run: all five ran clean except the warlord, whose designs failed because the screen transition moved the designer as it first appeared and stretched it to 5,000 px. The transition now only scales and fades (regression test added). | — |
