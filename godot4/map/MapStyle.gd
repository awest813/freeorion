class_name MapStyle
extends RefCounted
## Visual constants of the galaxy map that are content colours rather than UI
## tokens (star colours). UI-like colours (selection, labels) come from FOUi.

## StarType enum order: BLUE, WHITE, YELLOW, ORANGE, RED, NEUTRON, BLACK, NONE.
const STAR_COLORS: Array[Color] = [
	Color("#9bb0ff"),
	Color("#e6ecff"),
	Color("#fff2a8"),
	Color("#ffbe73"),
	Color("#ff7a5c"),
	Color("#c8f0ff"),
	Color("#8a55d0"),
	Color("#5c6470"),
]
const STAR_SIZES: Array[float] = [1.3, 1.15, 1.0, 0.9, 0.8, 0.6, 0.9, 0.35]
## Systems whose star type is not known yet (unexplored): grey glow plus a ring.
const UNKNOWN_STAR_COLOR := Color("#8d97a5")
const UNKNOWN_STAR_SIZE := 0.7
const UNEXPLORED_RING_PX := 6.0

## Sizes in screen pixels, kept constant across zoom levels.
const STAR_PX := 16.0
const LANE_PX := 1.5
const FLEET_PX := 7.0
const SELECTION_RING_PX := 13.0
const LABEL_FONT_SIZE := 13
const LABEL_OFFSET_PX := Vector2(0, 16)

## All labels are hidden when systems are on average closer than this on
## screen; otherwise labels are placed greedily without overlapping.
const LABEL_MIN_SPACING_PX := 12.0
const LABEL_PADDING_PX := 2.0

const SPACE_COLOR := Color(0.016, 0.02, 0.035)
const LANE_COLOR := Color(0.55, 0.65, 0.8, 0.45)
## Background star density: one star per this many screen pixels.
const BACKGROUND_PX_PER_STAR := 900.0


static func star_color(star_type: int) -> Color:
	if star_type >= 0 and star_type < STAR_COLORS.size():
		return STAR_COLORS[star_type]
	return UNKNOWN_STAR_COLOR


static func star_size(star_type: int) -> float:
	if star_type >= 0 and star_type < STAR_SIZES.size():
		return STAR_SIZES[star_type]
	return UNKNOWN_STAR_SIZE


## Soft round glow used for stars, generated so no art file is needed.
static func glow_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.42, 1.0])
	gradient.colors = PackedColorArray(
		[Color(1, 1, 1, 1), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0)]
	)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
