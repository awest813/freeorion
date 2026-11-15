class_name CombatSummary
extends VBoxContainer
## The GG combat report's graphical summary: a row per side, a bar per
## unit, filled to its health after the combat over its maximum (dead units
## in the dead colour). Four toggles, kept in GG's options: bar height and
## bar width proportional to each unit's maximum health, bars packed without
## gaps (GG's "smooth"), and row height proportional to the side's total.

## Toggles: option suffix, label key, default.
const TOGGLES := [
	["bar.proportional.height.enabled", "COMBAT_SUMMARY_BAR_HEIGHT", true],
	["bar.proportional.width.enabled", "COMBAT_SUMMARY_BAR_WIDTH", false],
	["bar.health.smooth.enabled", "COMBAT_SUMMARY_SMOOTH", false],
	["height.proportional.enabled", "COMBAT_SUMMARY_GRAPH_HEIGHT", true],
]
const OPTION_ROOT := "ui.combat.summary.graph."
const ROW_PX := 56.0
const GAP_PX := 2.0

## Toggle states: option suffix -> bool.
var toggles := {}
## Keep the toggles in the options (false in tests and previews).
var persist := false
## [{name, color, unit_list: [{health, max_health, destroyed}]}]
var sides: Array = []:
	set(value):
		sides = value
		_graph.queue_redraw()
		_fit()

var _graph: Control
var _checks := {}


func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var row := HFlowContainer.new()
	add_child(row)
	for entry in TOGGLES:
		toggles[entry[0]] = _load(entry[0], entry[2])
		var check := CheckBox.new()
		check.text = tr(entry[1])
		check.button_pressed = toggles[entry[0]]
		check.toggled.connect(set_toggle.bind(entry[0]))
		row.add_child(check)
		_checks[entry[0]] = check
	_graph = Control.new()
	_graph.draw.connect(_draw_graph)
	_graph.resized.connect(_graph.queue_redraw)
	add_child(_graph)


## Turn toggle \a option (a TOGGLES suffix) on or off, and remember it.
func set_toggle(on: bool, option: String) -> void:
	toggles[option] = on
	_checks[option].set_pressed_no_signal(on)
	var options := _options() if persist else null
	if options:
		options.add_option(OPTION_ROOT + option, "OPTIONS_DB_UI_COMBAT_SUMMARY", on)
		options.set_value(OPTION_ROOT + option, on)
		options.commit()
	_fit()
	_graph.queue_redraw()


## Each side's row height: equal, or by its total maximum health.
func row_heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	var largest := 0.0
	for side: Dictionary in sides:
		largest = maxf(largest, _total(side))
	for side: Dictionary in sides:
		if toggles["height.proportional.enabled"] and largest > 0.0:
			heights.push_back(maxf(ROW_PX * _total(side) / largest, ROW_PX * 0.25))
		else:
			heights.push_back(ROW_PX)
	return heights


## The bars of \a side in a row \a width by \a height wide: [rect, health
## fraction (-1 dead), unit] each, largest units first.
func bars(side: Dictionary, width: float, height: float) -> Array:
	var units: Array = side.get("unit_list", []).duplicate()
	units = units.filter(func(u): return u.get("max_health", 0.0) > 0.0)
	units.sort_custom(func(a, b): return a["max_health"] > b["max_health"])
	if units.is_empty():
		return []
	var largest: float = units[0]["max_health"]
	var total := 0.0
	for unit: Dictionary in units:
		total += unit["max_health"]
	var gap := 0.0 if toggles["bar.health.smooth.enabled"] else GAP_PX
	var room := maxf(width - gap * (units.size() - 1), 1.0)
	var result := []
	var x := 0.0
	for unit: Dictionary in units:
		var w: float = (
			room * unit["max_health"] / total
			if toggles["bar.proportional.width.enabled"]
			else room / units.size()
		)
		var h: float = (
			height * unit["max_health"] / largest
			if toggles["bar.proportional.height.enabled"]
			else height
		)
		var fraction: float = (
			-1.0
			if unit.get("destroyed", false)
			else clampf(unit.get("health", 0.0) / unit["max_health"], 0.0, 1.0)
		)
		result.push_back([Rect2(x, height - h, w, h), fraction, unit])
		x += w + gap
	return result


func _draw_graph() -> void:
	var tokens := FOUi.tokens
	var heights := row_heights()
	var y := 0.0
	var font := get_theme_font("font", "Label")
	var font_size := tokens.font_size_small
	for i in sides.size():
		var side: Dictionary = sides[i]
		var color: Color = side.get("color", Color.GRAY)
		_graph.draw_string(
			font,
			Vector2(0, y + font.get_ascent(font_size)),
			side.get("name", ""),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color
		)
		var top := y + font.get_height(font_size) + 2.0
		for bar: Array in bars(side, _graph.size.x, heights[i]):
			var rect: Rect2 = bar[0]
			rect.position.y += top
			var fraction: float = bar[1]
			if fraction < 0.0:
				_graph.draw_rect(rect, Color(tokens.negative, 0.55))
				continue
			# Damage taken over the health left, from the bottom up.
			_graph.draw_rect(rect, Color(tokens.warning, 0.55))
			var health := Rect2(
				rect.position + Vector2(0, rect.size.y * (1.0 - fraction)),
				Vector2(rect.size.x, rect.size.y * fraction)
			)
			_graph.draw_rect(health, Color(color.lerp(tokens.positive, 0.35), 0.9))
		y = top + heights[i] + tokens.space_3


func _fit() -> void:
	var font_height := get_theme_font("font", "Label").get_height(FOUi.tokens.font_size_small)
	var total := 0.0
	for height in row_heights():
		total += height + font_height + 2.0 + FOUi.tokens.space_3
	_graph.custom_minimum_size.y = total


func _total(side: Dictionary) -> float:
	var total := 0.0
	for unit: Dictionary in side.get("unit_list", []):
		total += unit.get("max_health", 0.0)
	return total


func _options() -> Object:
	return Engine.get_singleton("FOOptions") if Engine.has_singleton("FOOptions") else null


func _load(option: String, fallback: bool) -> bool:
	var options := _options()
	if options and options.exists(OPTION_ROOT + option):
		return bool(options.get_value(OPTION_ROOT + option))
	return fallback
