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
const ROUTE_DASH_PX := 8.0
const FLEET_PX := 7.0
## The bar on a blockaded fleet's marker.
const BLOCKADE_COLOR := Color("#f07171")
const SELECTION_RING_PX := 13.0
const LABEL_FONT_SIZE := 13
const LABEL_OFFSET_PX := Vector2(0, 16)

## All labels are hidden when systems are on average closer than this on
## screen; otherwise labels are placed greedily without overlapping.
const LABEL_MIN_SPACING_PX := 12.0
const LABEL_PADDING_PX := 2.0

const SPACE_COLOR := Color(0.016, 0.02, 0.035)
const LANE_COLOR := Color(0.55, 0.65, 0.8, 0.45)
## Supply, drawn under the lanes in the supplying empire's colour: lanes as
## wider bands, supplied systems as soft disks (a fraction of the typical
## system spacing).
const SUPPLY_LANE_PX := 6.0
const SUPPLY_LANE_ALPHA := 0.35
const SUPPLY_SYSTEM_ALPHA := 0.13
const SUPPLY_SYSTEM_RADIUS := 0.45
## Detection ranges, when shown: one faint tint, in a colour no empire's
## supply uses.
const DETECTION_ALPHA := 0.12
const DETECTION_COLOR := Color("#b8f2e6")
## Map modes: supply's tint in the supply mode and faded in the political
## one; owned systems' disks; resource half-disks and threat disks, sized by
## the square root of their value, in screen pixels.
const SUPPLY_MODE_ALPHA := 0.3
const SUPPLY_FADED_ALPHA := 0.04
const POLITICAL_ALPHA := 0.4
const RESOURCE_PX_PER_ROOT := 5.0
const THREAT_PX_PER_ROOT := 1.2
const MODE_MIN_PX := 5.0
const MODE_MAX_PX := 48.0
const INDUSTRY_COLOR := Color("#f0a030")
const RESEARCH_COLOR := Color("#40b0f0")
const THREAT_COLOR := Color("#ff4040")
## Fields (ion storms, nebulae, ...): their art, faded so lanes stay legible.
const FIELD_ALPHA := 0.6
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


## Opaque screen-space backdrop (space colour plus static stars) baked into one
## texture per viewport size, so the whole background is a single quad.
## Deterministic so screenshots are stable.
static func bake_starfield(size: Vector2i) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	image.fill(MapStyle.SPACE_COLOR)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919
	var count := int(size.x * size.y / MapStyle.BACKGROUND_PX_PER_STAR)
	for i in count:
		var shade := rng.randf_range(0.25, 0.7)
		var star := Color(shade, shade, shade * 1.1)
		var color := MapStyle.SPACE_COLOR.lerp(star, rng.randf_range(0.4, 0.9))
		var x := rng.randi_range(0, size.x - 2)
		var y := rng.randi_range(0, size.y - 2)
		image.set_pixel(x, y, color)
		if rng.randf() < 0.25:
			# A few brighter, two-pixel stars.
			var halo := MapStyle.SPACE_COLOR.lerp(color, 0.5)
			image.set_pixel(x + 1, y, halo)
			image.set_pixel(x, y + 1, halo)
	return ImageTexture.create_from_image(image)
