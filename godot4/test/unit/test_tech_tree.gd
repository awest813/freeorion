extends GutTest
## TechTreeLayout and TechTreeView on small trees.


func _tech(tech_name: String, prerequisites: Array = [], status := "researchable") -> Dictionary:
	return {
		"name": tech_name,
		"category": "C",
		"status": status,
		"prerequisites": PackedStringArray(prerequisites),
		"cost": 10.0,
		"turns": 2,
	}


func test_columns_follow_the_longest_prerequisite_chain():
	var layout := (
		TechTreeLayout
		. layout(
			[
				_tech("A"),
				_tech("B", ["A"]),
				_tech("C", ["A", "B"]),
				_tech("D"),
				_tech("E", ["MISSING"]),
			]
		)
	)
	var cells: Dictionary = layout["cells"]
	assert_eq(cells["A"].x, 0)
	assert_eq(cells["B"].x, 1)
	assert_eq(cells["C"].x, 2, "Placed after its deepest prerequisite")
	assert_eq(cells["E"].x, 0, "Prerequisites outside the tree don't count")
	assert_eq(layout["columns"], 3)
	assert_eq(layout["arcs"].size(), 3)


func test_order_reduces_crossings():
	# X1 leads to Y2 and X2 to Y1: the second column should swap to match.
	var layout := TechTreeLayout.layout(
		[_tech("X1"), _tech("X2"), _tech("Y1", ["X2"]), _tech("Y2", ["X1"])]
	)
	var cells: Dictionary = layout["cells"]
	assert_eq(cells["X1"].y < cells["X2"].y, cells["Y2"].y < cells["Y1"].y, "No crossing")


func test_cycles_do_not_hang():
	var layout := TechTreeLayout.layout([_tech("P", ["Q"]), _tech("Q", ["P"])])
	assert_eq(layout["cells"].size(), 2)


func test_view_hit_testing_selection_and_chain():
	var view := TechTreeView.new()
	view.size = Vector2(800, 400)
	add_child_autofree(view)
	view.techs = [_tech("A", [], "complete"), _tech("B", ["A"]), _tech("C", ["B"]), _tech("D")]
	view.zoom = 1.0
	view.offset = Vector2.ZERO
	var b_center := view.cell_position("B") + TechTreeView.NODE_SIZE / 2.0
	assert_eq(view.tech_at(b_center), "B")
	assert_eq(view.tech_at(b_center + Vector2(TechTreeView.NODE_SIZE.x * 0.5 + 4, 0)), "", "Gap")
	watch_signals(view)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = b_center
	press.pressed = true
	view._gui_input(press)
	var release := press.duplicate()
	release.pressed = false
	view._gui_input(release)
	assert_eq(view.selected, "B")
	assert_signal_emitted_with_parameters(view, "tech_selected", ["B"])
	assert_true(view._lit("A", "B"), "Prerequisite arc lit")
	assert_true(view._lit("B", "C"), "Dependent arc lit")
	assert_true(view._related.has("A") and view._related.has("C"))
	assert_false(view._related.has("D"))
	press.double_click = true
	view._gui_input(press)
	assert_signal_emitted_with_parameters(view, "tech_activated", ["B"])


func test_view_pan_and_zoom_around_the_cursor():
	var view := TechTreeView.new()
	view.size = Vector2(800, 400)
	add_child_autofree(view)
	view.techs = [_tech("A"), _tech("B", ["A"])]
	view.zoom = 1.0
	view.offset = Vector2.ZERO
	var anchor := Vector2(300, 100)
	var before := (anchor - view.offset) / view.zoom
	view.zoom_at(anchor, 0.5)
	assert_almost_eq((anchor - view.offset) / view.zoom, before, Vector2.ONE * 0.01)
	view.zoom_at(anchor, 10.0)
	assert_eq(view.zoom, TechTreeView.MAX_ZOOM, "Zoom is bounded")
	view.center_on("B")
	var center := view.offset + (view.cell_position("B") + TechTreeView.NODE_SIZE / 2.0) * view.zoom
	assert_almost_eq(center, view.size / 2.0, Vector2.ONE * 0.01)
