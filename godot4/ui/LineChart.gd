class_name LineChart
extends Control
## Line chart over turns: one line per series, axes with round ticks, and on
## hover a guide at the nearest turn with every series' value there. Used
## for empire statistics.

## Ticks wanted on the value axis (round numbers decide the exact count).
const VALUE_TICKS := 5
const LINE_WIDTH := 2.0
## The highlighted series (the player's empire) is drawn thicker.
const HIGHLIGHT_WIDTH := 3.5

## [{label, color, turns: PackedInt32Array, values: PackedFloat64Array}]
var series: Array = []:
	set(value):
		series = value
		_update_range()
		queue_redraw()
## Index into series drawn thicker and on top; -1 for none.
var highlight := -1:
	set(value):
		highlight = value
		queue_redraw()
## Series indices left out (toggled off in a legend).
## Heading of the hover box for x value (turn) \a turn.
var hover_title := func(turn: int) -> String: return tr("CHART_TURN").replace("%1%", str(turn))
var hidden_series := {}:
	set(value):
		hidden_series = value
		_update_range()
		queue_redraw()

var _turns := Vector2i(0, 1)
var _values := Vector2(0.0, 1.0)
var _hover_turn := -1
## Every value shown is whole (a count): no ticks between whole numbers.
var _whole := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 200)
	mouse_exited.connect(func(): _set_hover(-1))


## Round tick values from \a low to at least \a high, about \a count of them.
## With \a whole, ticks fall on whole numbers only (for counts).
static func nice_ticks(
	low: float, high: float, count := VALUE_TICKS, whole := false
) -> PackedFloat64Array:
	var ticks := PackedFloat64Array()
	if high <= low:
		high = low + 1.0
	var raw := (high - low) / maxf(count - 1, 1)
	var magnitude := pow(10.0, floor(log(raw) / log(10.0)))
	var step := magnitude
	for factor in [1.0, 2.0, 2.5, 5.0, 10.0]:
		step = factor * magnitude
		if step >= raw:
			break
	if whole:
		step = maxf(ceilf(step), 1.0)
	var value: float = floor(low / step) * step
	# Up to the first tick at or above high (with a little slack for rounding).
	while true:
		ticks.push_back(value)
		if value >= high - step * 1e-6:
			break
		value += step
	return ticks


## Short form of \a value for axes and hover: 950, 12.5, 1.2k, 154.8k, 3.1M.
static func short_number(value: float) -> String:
	var size := absf(value)
	if size >= 1e6:
		return "%.1fM" % (value / 1e6)
	if size >= 1e4:
		return "%.1fk" % (value / 1e3)
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value


## The value of \a line at \a turn, or NAN if it has none.
static func value_at(line: Dictionary, turn: int) -> float:
	var turns: PackedInt32Array = line.get("turns", PackedInt32Array())
	var index := turns.bsearch(turn)
	if index < turns.size() and turns[index] == turn:
		return line["values"][index]
	return NAN


## The turn shown at \a x (local), clamped to the chart's turns.
func turn_at(x: float) -> int:
	var plot := _plot_rect()
	var t := clampf((x - plot.position.x) / maxf(plot.size.x, 1.0), 0.0, 1.0)
	return int(round(lerpf(_turns.x, _turns.y, t)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var inside := _plot_rect().grow(4).has_point(event.position)
		_set_hover(turn_at(event.position.x) if inside else -1)


func _set_hover(turn: int) -> void:
	if turn != _hover_turn:
		_hover_turn = turn
		queue_redraw()


func _update_range() -> void:
	var first := 1 << 30
	var last := -(1 << 30)
	var low := INF
	var high := -INF
	var whole := true
	for i in series.size():
		if hidden_series.has(i):
			continue
		var line: Dictionary = series[i]
		var turns: PackedInt32Array = line.get("turns", PackedInt32Array())
		if turns.is_empty():
			continue
		first = mini(first, turns[0])
		last = maxi(last, turns[-1])
		for value: float in line.get("values", PackedFloat64Array()):
			low = minf(low, value)
			high = maxf(high, value)
			whole = whole and is_equal_approx(value, roundf(value))
	if first > last:
		first = 0
		last = 1
	if last == first:
		last = first + 1
	if low == INF:
		low = 0.0
		high = 1.0
	# Counts and outputs read best from zero.
	low = minf(low, 0.0)
	_whole = whole
	var ticks := nice_ticks(low, high, VALUE_TICKS, whole)
	_turns = Vector2i(first, last)
	_values = Vector2(ticks[0], ticks[-1])


func _font() -> Font:
	return get_theme_font("font", "Label")


func _font_size() -> int:
	return FOUi.tokens.font_size_small if FOUi.tokens else 13


# Room on the left for value labels and below for turn labels.
func _plot_rect() -> Rect2:
	var font := _font()
	var label_width := 0.0
	for tick in nice_ticks(_values.x, _values.y, VALUE_TICKS, _whole):
		label_width = maxf(
			label_width,
			font.get_string_size(short_number(tick), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x
		)
	var left := label_width + 12.0
	var bottom := font.get_height(_font_size()) + 8.0
	return Rect2(left, 8.0, maxf(size.x - left - 12.0, 1.0), maxf(size.y - bottom - 8.0, 1.0))


func _point(plot: Rect2, turn: float, value: float) -> Vector2:
	var x := inverse_lerp(_turns.x, _turns.y, turn)
	var y := inverse_lerp(_values.x, _values.y, value) if _values.y > _values.x else 0.0
	return Vector2(plot.position.x + x * plot.size.x, plot.end.y - y * plot.size.y)


func _draw() -> void:
	var plot := _plot_rect()
	var font := _font()
	var font_size := _font_size()
	var tokens := FOUi.tokens
	var grid_color := Color(tokens.text_secondary, 0.15) if tokens else Color(1, 1, 1, 0.15)
	var text_color := tokens.text_secondary if tokens else Color(0.7, 0.7, 0.7)
	# Value grid and labels.
	for tick in nice_ticks(_values.x, _values.y, VALUE_TICKS, _whole):
		var y := _point(plot, _turns.x, tick).y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid_color, 1.0)
		var text := short_number(tick)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			font,
			Vector2(plot.position.x - width - 6.0, y + font.get_ascent(font_size) * 0.4),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			text_color
		)
	# Turn labels.
	for tick in nice_ticks(_turns.x, _turns.y, 6, true):
		if tick < _turns.x or tick > _turns.y:
			continue
		var x := _point(plot, tick, _values.x).x
		var text := str(int(tick))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			font,
			Vector2(x - width / 2.0, plot.end.y + font.get_ascent(font_size) + 4.0),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			text_color
		)
	# Lines, the highlighted one last so it sits on top.
	var order := range(series.size())
	if highlight >= 0 and highlight < series.size():
		order.erase(highlight)
		order.push_back(highlight)
	for i in order:
		if hidden_series.has(i):
			continue
		var line: Dictionary = series[i]
		var points := PackedVector2Array()
		var turns: PackedInt32Array = line.get("turns", PackedInt32Array())
		var values: PackedFloat64Array = line.get("values", PackedFloat64Array())
		for j in turns.size():
			points.push_back(_point(plot, turns[j], values[j]))
		var width := HIGHLIGHT_WIDTH if i == highlight else LINE_WIDTH
		if points.size() > 1:
			draw_polyline(points, line.get("color", Color.WHITE), width, true)
		elif points.size() == 1:
			draw_circle(points[0], width, line.get("color", Color.WHITE))
	if _hover_turn >= 0:
		_draw_hover(plot, font, font_size)


# A guide at the hovered turn and a box listing each line's value there,
# highest first.
func _draw_hover(plot: Rect2, font: Font, font_size: int) -> void:
	var x := _point(plot, _hover_turn, _values.x).x
	var tokens := FOUi.tokens
	var text_color := tokens.text_primary if tokens else Color.WHITE
	draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(text_color, 0.4), 1.0)
	var rows := []
	for i in series.size():
		if hidden_series.has(i):
			continue
		var value := value_at(series[i], _hover_turn)
		if is_nan(value):
			continue
		draw_circle(_point(plot, _hover_turn, value), 3.5, series[i].get("color", Color.WHITE))
		rows.push_back([value, series[i]])
	if rows.is_empty():
		return
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var line_height := font.get_height(font_size) + 2.0
	var title: String = hover_title.call(_hover_turn)
	var box_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	for row in rows:
		var text := "%s  %s" % [row[1].get("label", ""), short_number(row[0])]
		box_width = maxf(
			box_width, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 16.0
		)
	var box_size := Vector2(box_width + 16.0, line_height * (rows.size() + 1) + 10.0)
	var box_x := x + 12.0 if x + 12.0 + box_size.x <= plot.end.x else x - 12.0 - box_size.x
	var box := Rect2(Vector2(box_x, plot.position.y + 4.0), box_size)
	var background := tokens.surface_overlay if tokens else Color(0.1, 0.12, 0.15)
	draw_rect(box, Color(background, 0.95))
	var y := box.position.y + 5.0 + font.get_ascent(font_size)
	draw_string(
		font,
		Vector2(box.position.x + 8.0, y),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(text_color, 0.7)
	)
	for row in rows:
		y += line_height
		draw_rect(
			Rect2(box.position.x + 8.0, y - font.get_ascent(font_size) * 0.7, 8.0, 8.0),
			row[1].get("color", Color.WHITE)
		)
		draw_string(
			font,
			Vector2(box.position.x + 24.0, y),
			"%s  %s" % [row[1].get("label", ""), short_number(row[0])],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			text_color
		)
