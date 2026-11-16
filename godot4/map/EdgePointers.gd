class_name EdgePointers
extends RefCounted
## For GalaxyMap: targets off screen (the places a selected colony fleet
## could settle, the end of the route previewed under the pointer) get a
## pointer at the edge of the screen area panels leave free, towards each,
## with its text. Clicking a pointer goes there.

## Pointer size, and its distance from the edge of the free area, in pixels.
const ARROW_PX := 12.0
const MARGIN_PX := 28.0

## Screen area panels leave free: () -> Rect2 (all of the map if unset).
var free_area := Callable()
## Pointers drawn last: [{rect (screen), world}].
var _hits: Array = []


## Where on the edge of \a area a pointer to \a at (screen) goes: \a at
## itself when it is inside.
static func edge_point(area: Rect2, at: Vector2) -> Vector2:
	if area.has_point(at):
		return at
	var center := area.get_center()
	var dir := at - center
	var scale := INF
	if absf(dir.x) > 0.001:
		scale = minf(scale, area.size.x * 0.5 / absf(dir.x))
	if absf(dir.y) > 0.001:
		scale = minf(scale, area.size.y * 0.5 / absf(dir.y))
	return center + dir * minf(scale, 1.0)


## The targets to point at in \a map: [[world position, text, colour]].
static func targets(map: GalaxyMap) -> Array:
	var tokens: FOTokens = FOUi.tokens
	var list := []
	for mark: Dictionary in map.fleets.settle_marks():
		var text: String = mark.get("text", "")
		if not str(mark.get("name", "")).is_empty():
			text = "%s · %s" % [mark["name"], text]
		list.push_back([mark.get("position", Vector2.ZERO), text, tokens.positive])
	var preview := map.fleets.preview_points()
	# The route to a place to settle already has that place's pointer.
	var marked := list.any(func(t): return preview.size() >= 2 and t[0] == preview[-1])
	if preview.size() >= 2 and not marked:
		var color: Color = tokens.negative if map.fleets.is_preview_warning() else tokens.accent
		list.push_back([preview[preview.size() - 1], map.fleets.preview_label(), color])
	return list


## Draw on \a layer (screen space) the pointers for \a map's targets off
## screen, with \a font.
func draw(layer: CanvasItem, map: GalaxyMap, font: Font) -> void:
	_hits.clear()
	if FOUi.tokens == null or font == null:
		return
	var viewport := Rect2(Vector2.ZERO, map.get_viewport_rect().size)
	var area: Rect2 = free_area.call() if free_area.is_valid() else viewport
	area = area.grow(-MARGIN_PX)
	var placed: Array[Rect2] = []
	for target: Array in targets(map):
		var at := map.camera.world_to_screen(target[0])
		var tip := edge_point(area, at)
		if tip == at:
			continue
		var dir := (at - area.get_center()).normalized()
		var side := Vector2(-dir.y, dir.x) * ARROW_PX * 0.6
		var back := tip - dir * ARROW_PX
		layer.draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), target[2])
		var hit := Rect2(tip, Vector2.ZERO).grow(ARROW_PX)
		if not str(target[1]).is_empty():
			var chip := _draw_text(layer, font, target[1], back, dir, area, target[2], placed)
			placed.push_back(chip)
			hit = hit.merge(chip)
		_hits.push_back({"rect": hit, "world": target[0]})


## The world position of the pointer at \a screen_pos, or null.
func hit(screen_pos: Vector2) -> Variant:
	for entry: Dictionary in _hits:
		if (entry["rect"] as Rect2).has_point(screen_pos):
			return entry["world"]
	return null


## Centre \a map on the target of the pointer at \a screen_pos, if any.
func follow(map: GalaxyMap, screen_pos: Vector2) -> bool:
	var target: Variant = hit(screen_pos)
	if target != null:
		map.camera.center_on(target)
	return target != null


## \a chip moved off the \a placed ones: inward from a top or bottom edge,
## down along a side one (\a dir points at the edge), within \a area.
static func clear_of(chip: Rect2, placed: Array[Rect2], dir: Vector2, area: Rect2) -> Rect2:
	var step := Vector2(0, chip.size.y + 2.0)
	if absf(dir.y) > absf(dir.x) and dir.y > 0:
		step = -step  # bottom edge: stack upwards
	for i in placed.size() + 1:
		if not placed.any(func(other: Rect2): return other.intersects(chip)):
			break
		chip.position += step
	chip.position.y = clampf(chip.position.y, area.position.y, area.end.y - chip.size.y)
	return chip


# \a text in a chip beside the arrow whose base is \a at, on its inner
# side (away from \a dir), kept inside \a area, edged in \a color; returns
# the chip.
func _draw_text(
	layer: CanvasItem,
	font: Font,
	text: String,
	at: Vector2,
	dir: Vector2,
	area: Rect2,
	color: Color,
	placed: Array[Rect2] = []
) -> Rect2:
	var tokens: FOTokens = FOUi.tokens
	var size := MapStyle.LABEL_FONT_SIZE
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pad := Vector2(tokens.space_2, tokens.space_1)
	var box := Vector2(width, size * 1.25) + pad * 2.0
	# Far enough in along the arrow that the chip doesn't cover it.
	var reach := absf(dir.x) * box.x / 2.0 + absf(dir.y) * box.y / 2.0 + tokens.space_1
	var top_left := at - dir * reach - box / 2.0
	top_left.x = clampf(top_left.x, area.position.x, area.end.x - box.x)
	top_left.y = clampf(top_left.y, area.position.y, area.end.y - box.y)
	var chip := Rect2(top_left.round(), box)
	chip = clear_of(chip, placed, dir, area)
	layer.draw_rect(chip, Color(tokens.surface_overlay, 0.92))
	layer.draw_rect(chip, color, false, 2.0)
	layer.draw_string(
		font,
		chip.position + pad + Vector2(0, size),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		tokens.text_primary
	)
	return chip
