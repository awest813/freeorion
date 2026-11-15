extends GutTest
## SystemPanel with fixed data.

const SAMPLE := {
	"name": "Hegira β",
	"star_type": "STAR_YELLOW",
	"planets":
	[
		{
			"name": "Hegira β I",
			"type": "PT_TERRAN",
			"size": "SZ_MEDIUM",
			"owner_name": "Empire Blue",
			"owner_color": Color("#3d9bff"),
			"own": true,
			"species": "SP_HUMAN",
			"focus": "FOCUS_INDUSTRY",
			"population": 15.0,
		},
		{"name": "Hegira β II", "type": "PT_GASGIANT", "size": "SZ_GASGIANT"},
	],
	"fleets_total": 3,
	"fleets_own": 2,
}

var panel: SystemPanel


func before_each():
	panel = SystemPanel.new()
	add_child_autofree(panel)


func test_shows_system_and_planets():
	panel.show_data(SAMPLE)
	assert_true(panel.visible)
	assert_eq(panel._title.text, "Hegira β")
	assert_string_contains(panel._subtitle.text, tr("STAR_YELLOW"))
	await wait_process_frames(1)
	assert_eq(panel._planets.get_child_count(), 2, "One row per planet")
	assert_string_contains(panel._fleets.text, "3")
	assert_string_contains(panel._fleets.text, "2")


func test_planet_details_are_translated():
	panel.show_data(SAMPLE)
	var details := _texts(panel._planets.get_child(0))
	assert_true(details.any(func(t): return t.contains(tr("SP_HUMAN"))), "Species shown")
	assert_true(details.any(func(t): return t.contains("Empire Blue")), "Owner name shown")
	assert_true(details.any(func(t): return t == "15.0"), "Population shown")


func test_empty_data_hides():
	panel.show_data(SAMPLE)
	panel.show_data({})
	assert_false(panel.visible)
	panel.show_system(-1)
	assert_false(panel.visible)


func test_no_planets_message():
	panel.show_data({"name": "Deep Space", "planets": []})
	await wait_process_frames(1)
	assert_eq(_texts(panel._planets), [tr("SYSTEM_PANEL_NO_PLANETS")])


func test_close_button_requests_close():
	watch_signals(panel)
	var close: Button = panel.find_children("*", "Button", true, false)[0]
	close.pressed.emit()
	assert_signal_emitted(panel, "close_requested")


func _texts(node: Node) -> Array:
	var texts := []
	for label in node.find_children("*", "Label", true, false):
		texts.push_back(label.text)
	return texts
