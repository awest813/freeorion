extends GutTest
## SystemPanel with fixed data.

const SAMPLE := {
	"name": "Hegira β",
	"star_type": "STAR_YELLOW",
	"planets":
	[
		{
			"id": 10,
			"name": "Hegira β I",
			"type": "PT_TERRAN",
			"size": "SZ_MEDIUM",
			"owner_name": "Empire Blue",
			"owner_color": Color("#3d9bff"),
			"own": true,
			"species": "SP_HUMAN",
			"focus": "FOCUS_INDUSTRY",
			"population": 15.0,
			"actions":
			{
				"focus":
				{
					"state": "available",
					"current": "FOCUS_INDUSTRY",
					"options": ["FOCUS_INDUSTRY", "FOCUS_RESEARCH"],
					"icons": ["icons/focus/industry.png", "icons/focus/research.png"],
				},
			},
		},
		{
			"id": 11,
			"name": "Hegira β II",
			"type": "PT_GASGIANT",
			"size": "SZ_GASGIANT",
			"actions":
			{"colonize": {"state": "available", "outpost": true, "ship_name": "Settler"}},
		},
	],
	"fleets_total": 3,
	"fleets_own": 2,
	"fleets":
	[
		{"id": 7, "name": "Battle Fleet", "ships": 2, "own": true, "destination": ""},
		{"id": 8, "name": "Scout", "ships": 1, "own": true, "destination": "Mu Arae"},
		{"id": 9, "name": "Monsters", "ships": 3, "own": false, "owner_color": Color.RED},
	],
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
	var buttons := panel.find_children("*", "Button", true, false)
	var close: Button = buttons.filter(func(b): return b.tooltip_text == tr("PANEL_CLOSE"))[0]
	close.pressed.emit()
	assert_signal_emitted(panel, "close_requested")


func test_own_fleets_are_selectable():
	panel.show_data(SAMPLE)
	await wait_process_frames(1)
	var buttons := panel._fleet_list.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 3, "Every fleet can be picked")
	assert_string_contains(buttons[1].text, "Mu Arae", "Destination shown")
	assert_eq(buttons[2].theme_type_variation, "GhostButton", "Others' fleets look apart")
	assert_not_null(buttons[2].icon, "with their owner's colour")
	watch_signals(panel)
	buttons[0].button_pressed = true
	assert_signal_emitted_with_parameters(panel, "fleet_selected", [7])
	assert_eq(panel.selected_fleet_id(), 7)
	assert_true(panel._notice.visible, "Move hint shown")
	buttons[1].button_pressed = true
	assert_eq(panel.selected_fleet_id(), 8, "Single selection")
	assert_false(buttons[0].button_pressed)
	panel.show_notice("")
	buttons[2].button_pressed = true
	assert_eq(panel.selected_fleet_id(), SAMPLE["fleets"][2]["id"], "Monsters can be inspected")
	assert_false(panel._notice.visible, "No move hint for fleets you can't order")


func test_selection_survives_refresh_until_fleet_leaves():
	panel.show_data(SAMPLE)
	panel.select_fleet(7)
	panel.show_data(SAMPLE)
	assert_eq(panel.selected_fleet_id(), 7, "Kept while listed")
	watch_signals(panel)
	var without := SAMPLE.duplicate(true)
	without["fleets"] = without["fleets"].slice(1)
	panel.show_data(without)
	assert_eq(panel.selected_fleet_id(), -1, "Cleared when the fleet is gone")
	assert_signal_emitted_with_parameters(panel, "fleet_selected", [-1])


func _texts(node: Node) -> Array:
	var texts := []
	for label in node.find_children("*", "Label", true, false):
		texts.push_back(label.text)
	return texts


func _buttons() -> Array:
	return panel._planets.find_children("*", "Button", true, false).filter(
		func(b): return not b is OptionButton
	)


func test_planet_actions_request_orders():
	panel.show_data(SAMPLE)
	watch_signals(panel)
	var outpost: Array = _buttons().filter(func(b): return b.text == tr("PL_OUTPOST"))
	assert_eq(outpost.size(), 1)
	outpost[0].pressed.emit()
	assert_signal_emitted_with_parameters(panel, "planet_action_requested", [11, "colonize"])


func test_focus_picker_for_own_planets():
	panel.show_data(SAMPLE)
	watch_signals(panel)
	var pickers: Array = panel._planets.find_children("*", "OptionButton", true, false)
	assert_eq(pickers.size(), 1, "Only the own planet has a focus picker")
	assert_eq(pickers[0].get_item_text(pickers[0].selected), tr("FOCUS_INDUSTRY"))
	pickers[0].item_selected.emit(1)
	assert_signal_emitted_with_parameters(panel, "focus_requested", [10, "FOCUS_RESEARCH"])


func test_action_texts():
	assert_eq(
		SystemPanel.action_text(
			"colonize", {"state": "available", "capacity": 1.0, "target_population": 13.0}
		),
		tr("PL_COLONIZE").replace("%1%", "1.0").replace("%2%", "13.0")
	)
	assert_eq(SystemPanel.action_text("colonize", {"state": "pending"}), tr("PL_CANCEL_COLONIZE"))
	assert_eq(
		SystemPanel.action_text("invade", {"state": "available", "troops": 6.0, "defenders": 5.0}),
		tr("PL_INVADE").replace("%1%", "6.0").replace("%2%", "5.0")
	)
	assert_eq(
		SystemPanel.action_text("annex", {"state": "available", "cost": 0.0}), tr("PL_ANNEX_FREE")
	)
	assert_eq(
		SystemPanel.action_text("annex", {"state": "unaffordable", "cost": 12.5}),
		tr("PL_ANNEXABLE").replace("%1%", "12.5")
	)
	assert_eq(SystemPanel.action_text("invade", {"state": ""}), "", "Not offered")
	assert_eq(SystemPanel.action_text("bombard", {"state": "available"}), tr("PL_BOMBARD"))
	assert_eq(SystemPanel.action_text("bombard", {"state": "pending"}), tr("PL_CANCEL_BOMBARD"))


func test_unaffordable_annex_is_disabled():
	var data := SAMPLE.duplicate(true)
	data["planets"][1]["actions"] = {"annex": {"state": "unaffordable", "cost": 30.0}}
	panel.show_data(data)
	var annex: Array = _buttons().filter(
		func(b): return b.text.begins_with(tr("PL_ANNEXABLE").get_slice("%", 0))
	)
	assert_eq(annex.size(), 1)
	assert_true(annex[0].disabled)


func test_ships_dropped_on_a_fleet():
	panel.show_data(SAMPLE)
	watch_signals(panel)
	var target_id := 8
	var data := {"type": FleetPanel.SHIP_DRAG, "fleet_id": 999, "ship_ids": PackedInt32Array([5])}
	assert_true(panel.can_drop_ships(Vector2.ZERO, data, target_id))
	assert_false(panel.can_drop_ships(Vector2.ZERO, {"type": "other"}, target_id))
	panel.drop_ships(Vector2.ZERO, data, target_id)
	assert_signal_emitted_with_parameters(
		panel, "ships_dropped", [target_id, PackedInt32Array([5])]
	)


func test_system_picker_steps_and_wraps():
	panel.systems_provider = func() -> Array: return [[3, "Alpha"], [5, "Beta"], [9, "Gamma"]]
	var data := SAMPLE.duplicate(true)
	data["id"] = 9
	panel.show_data(data)
	watch_signals(panel)
	panel.step_system(1)
	assert_signal_emitted_with_parameters(panel, "system_requested", [3])
	panel.step_system(-1)
	assert_signal_emitted_with_parameters(panel, "system_requested", [5])
	panel._fill_picker()
	assert_eq(panel._picker.get_popup().item_count, 3)


func test_own_systems_are_renamed_in_place():
	var data := SAMPLE.duplicate(true)
	data["id"] = 9
	data["own"] = true
	panel.show_data(data)
	assert_true(panel._title.editable)
	watch_signals(panel)
	panel._title.text_submitted.emit(" New Home ")
	assert_signal_emitted_with_parameters(panel, "rename_requested", [9, "New Home"])
	panel.show_data(SAMPLE)
	assert_false(panel._title.editable, "not someone else's")


func test_system_list_opens_wide_enough_to_read():
	panel.systems_provider = func(): return [[1, "Alpha Centauri"], [2, "Beta"], [3, "Gamma"]]
	panel._picker.show_popup()
	await wait_process_frames(2)
	var popup: PopupMenu = panel._picker.get_popup()
	assert_eq(popup.item_count, 3)
	assert_gt(popup.max_size.x, 100, "not capped to nothing")
	if DisplayServer.get_name() != "headless":
		assert_gt(popup.size.x, 60, "shown wide enough to read")
	popup.hide()


func test_refreshing_leaves_no_stray_nodes():
	# A planet with nothing to do, and an own one that makes nothing: their
	# rows have no actions and no chips.
	var data := SAMPLE.duplicate(true)
	data["planets"].push_back({"id": 12, "name": "Hegira β III", "type": "PT_BARREN"})
	data["planets"].push_back(
		{"id": 13, "name": "Hegira β IV", "own": true, "meters": {"industry": 0.0}}
	)
	panel.show_data(data)
	await wait_process_frames(1)
	var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for i in 3:
		panel.show_data(data)
		await wait_process_frames(1)
	assert_eq(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		before,
		"Planet rows' empty chip and action rows are freed"
	)
