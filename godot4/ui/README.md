# ui/: the design system

The Godot client's look is **observatory glass**: dark translucent panels over a living galaxy, edged with thin light, lit in the player's empire colour. See `doc/PREMIUM_UI_PLAN.md` for where it came from.

Everything visual comes from here. Screens, panels and the map take colours, sizes, type and motion from the tokens through the theme, never from literals. `tools/check_theme_literals.py` enforces this.

## Tokens: `tokens/FOTokens.gd`

These token sets ship:
- `default.tres`;
- `high_contrast.tres`: opaque, no glass, thick white edges.

`FOUi.tokens` is the set in use. It is a copy, so the empire accent can change it at runtime.

| Group | Tokens | Use |
|-------|--------|-----|
| Surfaces | `surface`, `surface_raised`, `surface_overlay`, `border`, `border_strong` | Opaque fills; nested cards; inputs |
| Text | `text_primary`, `text_secondary`, `text_disabled`, `text_on_accent` | At least 4.5:1 on every surface and on glass (tested) |
| Accent and status | `accent` (plus hover and pressed), `positive`, `negative`, `warning`, `info`, `focus_ring` | One accent; status colours carry meaning, not decoration |
| Glass | `glass_enabled`, `glass_fill`, `glass_alpha`, `glass_alpha_screen`, `glass_blur_px`, `edge`, `shadow`, `shadow_size`, `chamfer`, `chamfer_small` | Floating panels, screens, cut corners |
| Display type | `font_size_display`, `display_weight`, `display_spacing`, `caps_spacing` | Titles and captions |
| Spacing, shape, type sizes, icons, motion | `space_1` to `space_8`, `radius*`, `font_size_*`, `icon*`, `motion_fast`, `motion` | Layout and timing |

**Empire accent.** In a game, `FOUi.set_empire_accent(color)` makes the empire colour the accent.
- `FOThemeBuilder.accent_from()` lightens it until `text_on_accent` reads at 4.5:1.
- Option `ui.accent.empire` turns this off.
- The title screen keeps the default blue.

## Type

| Role | Face | Where |
|------|------|-------|
| Body | Roboto | Everything by default |
| `TitleLabel`, `HeadingLabel`, `DisplayTitle` | Exo 2, semibold, slightly spaced | Panel titles, screen titles, the empire name, the turn banner |
| `SectionCaps` via `ScreenKit.section()` | Exo 2, capitals, widely spaced, secondary colour | Section captions ("PLANETS", "PLACES TO SETTLE") |
| `MenuItem` and `MenuItemPrimary` | Exo 2 at title size | The title screen's menu |

- **Glyph coverage:** Exo 2 has no Greek, so it falls back to Roboto for star names like "Kelvin β".
- **Size:** set sizes with variations, never a pixel override.

## Chrome

**Glass panels.** These variations get `theme/glass_panel.gdshader` (FOUi assigns it as they are created):
- `OverlayPanel`: floating panels, dialogs, toasts;
- `TopBarPanel`;
- `BackgroundPanel`: full screens.

The shader blurs what is behind the panel under the fill, with a faint grain.
- Only these top-level panels get glass. Nested cards stay plain, because the screen texture would show the map through them, not their parent.
- Glass goes away with high contrast or option `ui.glass`.

**Cut corners.** `FOThemeBuilder.cut()` cuts the top-left and bottom-right corners (`chamfer`, `chamfer_small`) of panels and buttons. Focus rings follow the cut on buttons.

**Cards.** `ScreenKit.card(row, band)` draws a list row as a card: a soft fill, a hairline edge, a cut corner and a colour band on the left. Use one band per kind of thing:

| List | Band colour |
|------|-------------|
| Research | The tech category's own colour from the game data |
| Production | `warning` for buildings, `info` for ships |
| Policies | `warning` for economic, `info` for social, `negative` for military |

**Buttons.** Use one of these variations:
- `PrimaryButton`: one per view, glowing when pointed at;
- `GhostButton`;
- `DangerButton`;
- `SegmentButton`;
- `NavButton`: top-bar screens;
- `MenuItem`.

## Icons

- **Interface icons** are one monochrome line set (`FOIcons`): close, info, add, remove, play, back, more, up, down, pause, menu, locate, dropdown, last.
  - Write a button's text as the glyph (`"✕"`, `"⌖"`, ...). FOUi swaps in the icon and keeps the glyph in the `"glyph"` meta for code and tests.
  - Icons are drawn at the UI scale and shown at their size in UI units.
- **Game content** keeps GG's art (meters, techs, buildings, parts) through `FOArt`.

## World art

- **`PlanetView`** draws a planet as a lit, turning sphere (`theme/planet_sphere.gdshader`):
  - surface art per type, kept per planet;
  - an atmosphere in the type's colour;
  - light in the star's colour;
  - size by planet size.
- **`EmpireArt.flag()`** gives each empire's flag, composed from GG's flag art and picked from the empire's name.
- **`EmpireArt.species_portrait()`** gives the painting where there is one, else the species icon.

## Motion and sound

| Event | Motion |
|-------|--------|
| Panel appears | `FOUi.fade_in()` |
| Full screen opens | `FOUi.slide_in()`: a short rise and fade |
| New turn | `TurnBanner`: in and out over about two seconds |
| Top bar numbers change | Count up or down to the new value |
| Turn being processed | `FOSpinner` |
| Map | Stars twinkle; the selected fleet's ring turns |

- **Reduced motion:** every animation checks `FOUi.reduce_motion` (option `ui.reduce-motion`) and shows the end state at once.
- **Sounds:** they go through `FOAudio` and its options. New turn, new battles and auto-turn stops have their own sounds.

## Checks

- `test/unit/test_ui_tokens.gd` checks:
  - contrast on surfaces, glass and empire accents;
  - that panels get the glass;
  - that glyphs become icons.
- Visual goldens (`test/visual/`) cover each screen at 100%, 150% and 200%, and in German and Russian. Regenerate them with `UPDATE_GOLDENS=1` when a change to the look is intended.
- `ui/ComponentGallery.tscn` shows every variation in both token sets.
