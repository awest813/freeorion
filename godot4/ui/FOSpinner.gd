class_name FOSpinner
extends Control
## A busy indicator: three arcs in the accent turning (a still ring with
## reduced motion).

## Turns a second.
const SPEED := 0.8


func _init(size := 32) -> void:
	custom_minimum_size = Vector2(size, size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if is_visible_in_tree() and not FOUi.reduce_motion:
		queue_redraw()


func _draw() -> void:
	var tokens: FOTokens = FOUi.tokens
	var center := size / 2.0
	var radius := minf(size.x, size.y) * 0.4
	var turn := 0.0 if FOUi.reduce_motion else Time.get_ticks_msec() / 1000.0 * SPEED * TAU
	draw_arc(center, radius, 0, TAU, 48, Color(tokens.accent, 0.18), 3.0, true)
	for k in 3:
		var from := turn + k * TAU / 3.0
		draw_arc(center, radius, from, from + TAU / 7.0, 12, tokens.accent, 3.0, true)
