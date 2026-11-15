class_name MapScale
extends Control
## The map's scale legend: a bar as long as a round distance (1, 2 or 5
## times a power of ten, in uu) at the current zoom.

## The bar is at most this many pixels wide.
const MAX_BAR_PX := 160.0

## World units the bar stands for.
var length_units := 0.0
var _bar_px := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(MAX_BAR_PX + 8.0, 28.0)


## The longest round distance not above \a max_units: 1, 2, 5, 10, 20, ...
static func nice_length(max_units: float) -> float:
	if max_units <= 0.0:
		return 0.0
	var magnitude := pow(10.0, floor(log(max_units) / log(10.0)))
	for factor in [5.0, 2.0, 1.0]:
		if factor * magnitude <= max_units:
			return factor * magnitude
	return magnitude


## Follow \a zoom (screen pixels per world unit).
func set_zoom(zoom: float) -> void:
	length_units = nice_length(MAX_BAR_PX / maxf(zoom, 0.0001))
	_bar_px = length_units * zoom
	queue_redraw()


func _draw() -> void:
	var tokens := FOUi.tokens
	var color: Color = tokens.text_secondary if tokens else Color(0.7, 0.7, 0.7)
	var font := get_theme_font("font", "Label")
	var font_size: int = tokens.font_size_small if tokens else 13
	var y := size.y - 4.0
	var left := 4.0
	draw_line(Vector2(left, y), Vector2(left + _bar_px, y), color, 2.0)
	for x in [left, left + _bar_px]:
		draw_line(Vector2(x, y - 6.0), Vector2(x, y), color, 2.0)
	var text := tr("MAP_SCALE_UU").replace("%1%", LineChart.short_number(length_units))
	draw_string(font, Vector2(left, y - 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
