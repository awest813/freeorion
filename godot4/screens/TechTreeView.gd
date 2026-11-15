class_name TechTreeView
extends Control
## The tech tree: techs as cards on TechTreeLayout's grid with arcs from
## prerequisites, coloured by status (researched, researchable, not yet).
## Drag to pan, wheel to zoom. Clicking a tech selects it and lights up
## what it needs and what it leads to; double-click queues it.

signal tech_selected(tech_name: String)
signal tech_activated(tech_name: String)
## Shift+click on a tech: queue it (at the end).
signal tech_queued(tech_name: String)
## Right-click on \a tech_name's card, at the screen point \a at.
signal tech_context(tech_name: String, at: Vector2)

const NODE_SIZE := Vector2(212, 54)
const GAP := Vector2(64, 12)
const MIN_ZOOM := 0.35
const MAX_ZOOM := 1.6
const ICON := 38.0
## Below this zoom, cards show their icon only.
const TEXT_ZOOM := 0.55
## The overview in the corner when the tree is bigger than the view.
const OVERVIEW := Vector2(180, 112)

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
## Queue entries by tech name (for tooltips).
var queue_entries := {}
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
	return "" if tech_name.is_empty() else tooltip_text_for(tech_name)


## The rich tooltip of \a tech_name, as GG's tech tree.
func tooltip_text_for(tech_name: String) -> String:
	var tech: Dictionary = _by_name.get(tech_name, {})
	return "" if tech.is_empty() else describe(tech, queue_entries.get(tech_name, {}))


## A tech's tooltip, as GG's: status, cost and time, how it goes in the
## queue (\a queue_entry: progress, RP this turn of the most it can take,
## turns left), description, what it needs and unlocks, and the keys.
static func describe(tech: Dictionary, queue_entry := {}) -> String:
	var t := TranslationServer.translate
	var tech_name: String = tech.get("name", "")
	var lines: PackedStringArray = [t.call(tech_name)]
	var status: String = tech.get("status", "")
	if not status.is_empty():
		lines.push_back(t.call("RESEARCH_STATUS_" + status.to_upper()))
	lines.push_back(
		(
			String(t.call("RESEARCH_ITEM_COST"))
			. replace("%1%", "%.0f" % tech.get("cost", 0.0))
			. replace("%2%", ScreenKit.turns_text(tech.get("turns", 0)))
			. replace("%3%", t.call(tech.get("category", "")))
		)
	)
	if not queue_entry.is_empty():
		var most: float = tech.get("cost", 0.0) / maxf(float(tech.get("turns", 1)), 1.0)
		lines.push_back(
			(
				String(t.call("RESEARCH_TIP_QUEUED"))
				. replace("%1%", "%d" % roundi(queue_entry.get("progress", 0.0) * 100.0))
				. replace("%2%", "%.1f" % queue_entry.get("allocated_rp", 0.0))
				. replace("%3%", "%.1f" % most)
				. replace("%4%", ScreenKit.turns_text(queue_entry.get("turns_left", -1)))
			)
		)
	var description: String = t.call(tech.get("short_description", ""))
	if not description.begins_with("ERROR: "):
		lines.push_back(FORichText.plain_text(description))
	var needs: PackedStringArray = []
	for prereq in tech.get("prerequisites", PackedStringArray()):
		needs.push_back(t.call(prereq))
	if not needs.is_empty():
		lines.push_back(t.call("RESEARCH_TIP_NEEDS") + " " + ", ".join(needs))
	var unlocks: PackedStringArray = []
	for item: Dictionary in tech.get("unlocks", []):
		unlocks.push_back(t.call(item.get("name", "")))
	if not unlocks.is_empty():
		lines.push_back(t.call("RESEARCH_TIP_UNLOCKS") + " " + ", ".join(unlocks))
	lines.push_back(t.call("RESEARCH_TIP_KEYS"))
	return "\n".join(lines)


## Zoom in (1), out (-1), or fit the whole tree (0), from buttons.
func zoom_step(direction: int) -> void:
	var center := size / 2.0
	if direction == 0:
		var content := content_size() / zoom
		var fit := minf(size.x / maxf(content.x, 1.0), size.y / maxf(content.y, 1.0))
		# Never so small the names can't be read: the overview shows the rest.
		zoom = clampf(fit, TEXT_ZOOM, MAX_ZOOM)
		# Centred when it fits; from the top left when even the smallest
		# zoom can't show it all.
		var spare := (size - content * zoom) / 2.0
		offset = Vector2(maxf(spare.x, 24.0), maxf(spare.y, 24.0))
		queue_redraw()
		return
	zoom_at(center, clampf(zoom * (1.25 if direction > 0 else 0.8), MIN_ZOOM, MAX_ZOOM))


## The overview's place (empty when the whole tree is in view).
func overview_rect() -> Rect2:
	var content := content_size()
	if content.x <= size.x and content.y <= size.y:
		return Rect2()
	var gap: float = FOUi.tokens.space_2 if FOUi.tokens else 8.0
	# Bottom left: the zoom buttons are top right, a screen's tip bottom right.
	return Rect2(Vector2(gap, size.y - OVERVIEW.y - gap), OVERVIEW)


## Centre the view on the tree point under \a at in the overview.
func jump_to_overview_point(at: Vector2) -> void:
	var box := overview_rect()
	if box.size == Vector2.ZERO:
		return
	var tree := content_size() / zoom
	var world := (at - box.position) / box.size * tree
	offset = size / 2.0 - world * zoom
	queue_redraw()


func _draw_overview() -> void:
	var box := overview_rect()
	if box.size == Vector2.ZERO:
		return
	var tokens := FOUi.tokens
	draw_rect(box, Color(tokens.surface, 0.92))
	draw_rect(box, tokens.border, false, 1.0)
	var tree := content_size() / zoom
	var ratio := box.size / tree
	for tech_name in _layout["cells"]:
		var status: String = _by_name[tech_name].get("status", "")
		var color := tokens.positive if status == "complete" else tokens.text_secondary
		if tech_name == selected:
			color = tokens.accent
		var at := box.position + cell_position(tech_name) * ratio
		draw_rect(Rect2(at, Vector2(maxf(NODE_SIZE.x * ratio.x, 2.0), 2.0)), Color(color, 0.8))
	# What the view shows now.
	var view := Rect2(-offset / zoom * ratio + box.position, size / zoom * ratio).intersection(box)
	draw_rect(view, tokens.accent, false, 1.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					var factor := 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
					zoom_at(event.position, zoom * factor)
				accept_event()
			MOUSE_BUTTON_RIGHT:
				var tech_name := tech_at(event.position)
				if event.pressed and not tech_name.is_empty():
					selected = tech_name
					tech_selected.emit(tech_name)
					tech_context.emit(tech_name, event.global_position)
				accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				if event.pressed and overview_rect().has_point(event.position):
					jump_to_overview_point(event.position)
					_dragging = true
				elif (
					event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT
				):
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
						if event.shift_pressed:
							tech_queued.emit(tech_name)
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
	_draw_overview()


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
		. replace("%2%", ScreenKit.turns_text(tech.get("turns", 0)))
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
	# What it unlocks: small icons along the bottom right.
	var unlocks: Array = tech.get("unlocks", [])
	var unlock_size := 16.0 * zoom
	var unlock_x := rect.end.x - pad
	for i in mini(unlocks.size(), 5):
		var texture := FOArt.icon(unlocks[i].get("icon", ""))
		if texture == null:
			continue
		unlock_x -= unlock_size + 2.0
		draw_texture_rect(
			texture,
			Rect2(Vector2(unlock_x, rect.end.y - pad - unlock_size), Vector2.ONE * unlock_size),
			false,
			Color(1, 1, 1, 0.5 if dimmed else 0.9)
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
