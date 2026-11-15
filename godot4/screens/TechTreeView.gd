class_name TechTreeView
extends Control
## The tech tree: techs as cards on TechTreeLayout's grid with arcs from
## prerequisites, coloured by status (researched, researchable, not yet).
## Drag to pan, wheel to zoom. Clicking a tech selects it and lights up
## what it needs and what it leads to; double-click queues it.

signal tech_selected(tech_name: String)
signal tech_activated(tech_name: String)

const NODE_SIZE := Vector2(212, 54)
const GAP := Vector2(64, 12)
const MIN_ZOOM := 0.35
const MAX_ZOOM := 1.6
const ICON := 38.0
## Below this zoom, cards show their icon only.
const TEXT_ZOOM := 0.55

## Techs as FOResearch.get_techs() lists them.
var techs: Array = []:
	set(value):
		techs = value
		_by_name.clear()
		for tech: Dictionary in techs:
			_by_name[tech["name"]] = tech
		_layout = TechTreeLayout.layout(techs)
		_at_cell.clear()
		for tech_name in _layout["cells"]:
			_at_cell[_layout["cells"][tech_name]] = tech_name
		_update_related()
		queue_redraw()
var selected := "":
	set(value):
		selected = value
		_update_related()
		queue_redraw()
## Queue position (0-based) by tech name, for the number on queued cards.
var queue_positions := {}:
	set(value):
		queue_positions = value
		queue_redraw()
var zoom := 0.8:
	set(value):
		zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
		queue_redraw()
## Screen offset of the grid's top-left corner.
var offset := Vector2(24, 24):
	set(value):
		offset = value
		queue_redraw()

var _by_name := {}
var _at_cell := {}
var _layout := {"cells": {}, "columns": 0, "rows": 0, "arcs": []}
## Techs linked to the selected one: all it needs, all it leads to, both.
var _ancestors := {}
var _descendants := {}
var _related := {}
var _hover := ""
var _dragging := false
var _icons := {}


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK


## Top-left of \a tech_name's card in grid space (zoom 1, no offset).
func cell_position(tech_name: String) -> Vector2:
	var cell: Vector2i = _layout["cells"].get(tech_name, Vector2i(-1, -1))
	return Vector2(cell.x * (NODE_SIZE.x + GAP.x), cell.y * (NODE_SIZE.y + GAP.y))


## The card under local point \a point, or "".
func tech_at(point: Vector2) -> String:
	var grid := (point - offset) / zoom
	var step := NODE_SIZE + GAP
	var column := floori(grid.x / step.x)
	var row := floori(grid.y / step.y)
	if grid.x - column * step.x > NODE_SIZE.x or grid.y - row * step.y > NODE_SIZE.y:
		return ""
	return _at_cell.get(Vector2i(column, row), "")


## Scroll so \a tech_name's card is in the middle.
func center_on(tech_name: String) -> void:
	if not _layout["cells"].has(tech_name):
		return
	offset = size / 2.0 - (cell_position(tech_name) + NODE_SIZE / 2.0) * zoom


## Size of the whole tree at the current zoom.
func content_size() -> Vector2:
	var step := NODE_SIZE + GAP
	return Vector2(_layout["columns"] * step.x, _layout["rows"] * step.y) * zoom


func _get_tooltip(at_position: Vector2) -> String:
	var tech_name := tech_at(at_position)
	if tech_name.is_empty():
		return ""
	var tech: Dictionary = _by_name[tech_name]
	return "%s\n%s" % [tr(tech_name), tr(tech.get("short_description", ""))]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					var factor := 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
					zoom_at(event.position, zoom * factor)
				accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				if event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
					var tech_name := tech_at(event.position)
					if not tech_name.is_empty():
						tech_activated.emit(tech_name)
				elif event.pressed:
					_dragging = false
				elif not _dragging and event.button_index == MOUSE_BUTTON_LEFT:
					var tech_name := tech_at(event.position)
					if not tech_name.is_empty():
						selected = tech_name
						tech_selected.emit(tech_name)
				accept_event()
	elif event is InputEventMouseMotion:
		if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
			if event.relative.length() > 0.0:
				_dragging = true
				offset += event.relative
			accept_event()
		var hover := tech_at(event.position)
		if hover != _hover:
			_hover = hover
			queue_redraw()


## Zoom to \a new_zoom keeping the point under \a anchor in place.
func zoom_at(anchor: Vector2, new_zoom: float) -> void:
	var grid := (anchor - offset) / zoom
	zoom = new_zoom
	offset = anchor - grid * zoom


func _update_related() -> void:
	_ancestors.clear()
	_descendants.clear()
	_related.clear()
	if selected.is_empty() or not _by_name.has(selected):
		return
	var down := [selected]
	while not down.is_empty():
		var name: String = down.pop_back()
		for prereq in _by_name.get(name, {}).get("prerequisites", []):
			if _by_name.has(prereq) and not _ancestors.has(prereq):
				_ancestors[prereq] = true
				down.push_back(prereq)
	var up := [selected]
	while not up.is_empty():
		var name: String = up.pop_back()
		for arc: Array in _layout["arcs"]:
			if arc[0] == name and not _descendants.has(arc[1]):
				_descendants[arc[1]] = true
				up.push_back(arc[1])
	_related = _ancestors.merged(_descendants)


# Whether arc \a from -> \a to is on a chain through the selected tech.
func _lit(from: String, to: String) -> bool:
	if selected.is_empty():
		return false
	if _ancestors.has(from) and (to == selected or _ancestors.has(to)):
		return true
	return _descendants.has(to) and (from == selected or _descendants.has(from))


func _draw() -> void:
	var tokens := FOUi.tokens
	var view := Rect2(Vector2.ZERO, size)
	# Arcs below the cards.
	for arc: Array in _layout["arcs"]:
		var from := (
			offset + (cell_position(arc[0]) + Vector2(NODE_SIZE.x, NODE_SIZE.y / 2.0)) * zoom
		)
		var to := offset + (cell_position(arc[1]) + Vector2(0, NODE_SIZE.y / 2.0)) * zoom
		if not view.grow(200).has_point(from) and not view.grow(200).has_point(to):
			continue
		var lit := _lit(arc[0], arc[1])
		var done: bool = _by_name[arc[0]].get("status", "") == "complete"
		var color := (
			tokens.accent
			if lit
			else Color(tokens.positive if done else tokens.text_secondary, 0.35)
		)
		draw_polyline(_curve(from, to), color, (2.5 if lit else 1.5) * maxf(zoom, 0.6), true)
	for tech_name in _layout["cells"]:
		var rect := Rect2(offset + cell_position(tech_name) * zoom, NODE_SIZE * zoom)
		if view.intersects(rect):
			_draw_card(tech_name, rect)


func _curve(from: Vector2, to: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var bend := maxf((to.x - from.x) * 0.5, 24.0)
	for i in 17:
		var t := i / 16.0
		var a := from.lerp(from + Vector2(bend, 0), t)
		var b := (from + Vector2(bend, 0)).lerp(to - Vector2(bend, 0), t)
		var c := (to - Vector2(bend, 0)).lerp(to, t)
		points.push_back(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return points


func _draw_card(tech_name: String, rect: Rect2) -> void:
	var tokens := FOUi.tokens
	var tech: Dictionary = _by_name[tech_name]
	var status: String = tech.get("status", "")
	var background := tokens.surface_raised
	var border := Color(tokens.text_secondary, 0.25)
	var text_color := tokens.text_primary
	match status:
		"complete":
			background = tokens.surface_raised.lerp(tokens.positive, 0.18)
			border = Color(tokens.positive, 0.6)
		"researchable":
			background = tokens.surface_overlay
			border = Color(tokens.accent, 0.7)
		_:
			text_color = tokens.text_secondary
	var dimmed := not selected.is_empty() and tech_name != selected and not _related.has(tech_name)
	if dimmed:
		background = background.darkened(0.35)
		text_color = Color(text_color, 0.5)
	draw_rect(rect, background)
	var width := 1.0
	if tech_name == selected:
		border = tokens.accent
		width = 3.0
	elif tech_name == _hover:
		border = tokens.text_primary
		width = 2.0
	draw_rect(rect, border, false, width)
	var pad := 6.0 * zoom
	var icon := _icon(tech)
	var icon_size := ICON * zoom
	if icon:
		var icon_rect := Rect2(
			rect.position + Vector2(pad, (rect.size.y - icon_size) / 2.0), Vector2.ONE * icon_size
		)
		draw_texture_rect(icon, icon_rect, false, Color(1, 1, 1, 0.5 if dimmed else 1.0))
	if zoom < TEXT_ZOOM:
		return  # too small to read; icons, colours and arcs carry the shape
	var font := get_theme_font("font", "Label")
	var font_size := int(round(FOUi.tokens.font_size_small * clampf(zoom, 0.8, 1.2)))
	var text_x := rect.position.x + pad * 2.0 + icon_size
	var text_width := rect.end.x - text_x - pad
	var queued: int = queue_positions.get(tech_name, -1)
	if queued >= 0:
		var badge := "#%d" % (queued + 1)
		var badge_width := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			font,
			Vector2(
				rect.end.x - pad - badge_width, rect.position.y + pad + font.get_ascent(font_size)
			),
			badge,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			tokens.accent
		)
		text_width -= badge_width + pad
	var line_y := rect.position.y + pad + font.get_ascent(font_size)
	draw_string(
		font,
		Vector2(text_x, line_y),
		_fit(tr(tech_name), font, font_size, text_width),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		text_color
	)
	var detail := (
		tr("RESEARCH_ITEM_COST")
		. replace("%1%", "%.0f" % tech.get("cost", 0.0))
		. replace("%2%", str(tech.get("turns", 0)))
		. replace(" · %3%", "")
		. replace("%3%", "")
	)
	draw_string(
		font,
		Vector2(text_x, line_y + font.get_height(font_size)),
		_fit(detail, font, font_size, rect.end.x - text_x - pad),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(text_color, 0.7)
	)
	var progress: float = tech.get("progress", 0.0)
	if progress > 0.0 and status != "complete":
		var bar := Rect2(
			Vector2(rect.position.x, rect.end.y - 3.0 * zoom),
			Vector2(rect.size.x * clampf(progress, 0.0, 1.0), 3.0 * zoom)
		)
		draw_rect(bar, tokens.accent)


func _fit(text: String, font: Font, font_size: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	var cut := text.length()
	while cut > 1:
		cut -= 1
		var candidate := text.substr(0, cut).strip_edges() + "…"
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			return candidate
	return "…"


func _icon(tech: Dictionary) -> Texture2D:
	var key: String = tech.get("icon", "")
	if not _icons.has(key):
		var texture := FOArt.icon(key) if not key.is_empty() else null
		if texture == null:
			texture = FOArt.tech_category_icon(tech.get("category", ""))
		_icons[key] = texture
	return _icons[key]
