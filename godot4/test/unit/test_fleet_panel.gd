extends GutTest
## FleetPanel with fixed data.

const SAMPLE := {
	"id": 7,
	"name": "Battle Fleet",
	"aggression": "obstructive",
	"destination": "Mu Arae",
	"eta": 3,
	"ships":
	[
		{
			"id": 70,
			"name": "Defender I",
			"design": "Frigate Ms",
			"icon": "icons/ship_hulls/basic-medium-hull_small.png",
			"structure": 18.0,
			"max_structure": 24.0,
			"armed": true,
		},
		{
			"id": 71,
			"name": "Settler",
			"design": "Outpost Ship",
			"icon": "icons/ship_hulls/basic-medium-hull_small.png",
			"structure": 8.0,
			"max_structure": 8.0,
			"colony": true,
		},
	],
	"merge_targets": [{"id": 8, "name": "Scout Fleet"}],
}

var panel: FleetPanel


func before_each():
	panel = FleetPanel.new()
	add_child_autofree(panel)
	panel.show_data(SAMPLE)
	await wait_process_frames(1)


func test_shows_fleet():
	assert_true(panel.visible)
	assert_eq(panel._name.text, "Battle Fleet")
	assert_string_contains(panel._route.text, "Mu Arae")
	assert_string_contains(panel._route.text, GameShell.eta_text(3))
	assert_eq(panel._ships.get_child_count(), 2)
	assert_true(panel._stance_buttons["obstructive"].button_pressed)
	assert_false(panel._stance_buttons["aggressive"].button_pressed)


func test_roles_are_labelled():
	var texts := panel._ships.get_child(0).find_children("*", "Label", true, false).map(
		func(l): return l.text
	)
	assert_true(texts.any(func(t): return t.contains(tr("FLEET_PANEL_ARMED"))))


func test_stance_request():
	watch_signals(panel)
	panel._stance_buttons["aggressive"].pressed.emit()
	assert_signal_emitted_with_parameters(panel, "aggression_requested", [7, "aggressive"])


func test_split_needs_some_but_not_all_ships():
	assert_true(panel._split.disabled, "Nothing selected")
	_check(0, true)
	assert_false(panel._split.disabled)
	watch_signals(panel)
	panel._split.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "split_requested", [PackedInt32Array([70])])
	_check(1, true)
	assert_true(panel._split.disabled, "Can't split off every ship")


func test_merge_moves_all_ships():
	watch_signals(panel)
	panel._merge.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "merge_requested", [8, PackedInt32Array([70, 71])])


func test_merge_hidden_without_targets():
	var alone := SAMPLE.duplicate(true)
	alone["merge_targets"] = []
	panel.show_data(alone)
	assert_false(panel._merge.visible)


func test_rename_on_enter():
	watch_signals(panel)
	panel._name.text = "Home Guard"
	panel._name.text_submitted.emit("Home Guard")
	assert_signal_emitted_with_parameters(panel, "rename_requested", [7, "Home Guard"])


func _check(row: int, pressed: bool) -> void:
	var box: CheckBox = panel._ships.get_child(row).find_children("*", "CheckBox", true, false)[0]
	box.button_pressed = pressed


func test_scrap_selected_ships_and_cancel():
	watch_signals(panel)
	assert_true(panel._scrap.disabled, "Nothing selected")
	panel._on_ship_toggled(true, 71)
	assert_false(panel._scrap.disabled)
	assert_eq(panel._scrap.text, tr("ORDER_SHIP_SCRAP"))
	panel._scrap.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "scrap_requested", [PackedInt32Array([71])])
	var scrapping := SAMPLE.duplicate(true)
	scrapping["ships"][1]["scrapping"] = true
	panel.show_data(scrapping)
	assert_eq(panel._scrap.text, tr("ORDER_CANCEL_SHIP_SCRAP"), "Pressing again cancels")
	var labels: Array = panel._ships.find_children("*", "Label", true, false)
	assert_true(labels.any(func(l): return l.text.contains(tr("FLEET_PANEL_SCRAPPING"))))


func test_big_fleets_scroll():
	var big := SAMPLE.duplicate(true)
	var ship: Dictionary = big["ships"][0]
	for i in 12:
		var copy := ship.duplicate()
		copy["id"] = 100 + i
		big["ships"].push_back(copy)
	panel.show_data(big)
	await wait_process_frames(2)
	assert_lt(
		panel._ships_scroll.size.y,
		panel._ships.size.y,
		"Fourteen ships don't all fit; the list scrolls"
	)


func test_drag_ships():
	var data: Dictionary = panel.ship_drag_data(Vector2.ZERO, 71)
	assert_eq(data["ship_ids"], PackedInt32Array([71]), "An unticked ship goes alone")
	assert_eq(data["fleet_id"], 7)
	panel._on_ship_toggled(true, 70)
	panel._on_ship_toggled(true, 71)
	data = panel.ship_drag_data(Vector2.ZERO, 70)
	assert_eq(data["ship_ids"], PackedInt32Array([70, 71]), "A ticked ship takes the others along")
	assert_true(FleetPanel.is_ship_drag(data, 8))
	assert_false(FleetPanel.is_ship_drag(data, 7), "Not onto its own fleet")
	assert_false(panel._can_drop_on_split(Vector2.ZERO, data), "Can't split off every ship")
	watch_signals(panel)
	var one: Dictionary = {"type": FleetPanel.SHIP_DRAG, "fleet_id": 7, "ship_ids": [71]}
	assert_true(panel._can_drop_on_split(Vector2.ZERO, one))
	panel._drop_on_split(Vector2.ZERO, one)
	assert_signal_emitted_with_parameters(panel, "split_requested", [[71]])
