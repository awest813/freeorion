extends GutTest
## The fleet panel's menu (merge all, splits, scrap the fleet, new fleets'
## stance), its totals and per-ship stats, renaming ships, and dragging a
## whole fleet in the system panel.


func _ship(id: int, design: int, stats: Dictionary, scrapping := false) -> Dictionary:
	var full := {
		"damage": 0.0,
		"destroy": 0.0,
		"fighters": 0.0,
		"fighters_max": 0.0,
		"troops": 0.0,
		"colony": 0.0,
		"structure": 10.0,
		"max_structure": 10.0,
		"shield": 0.0,
		"fuel": 5.0,
		"max_fuel": 5.0,
		"speed": 75.0,
		"design_id": design,
	}
	full.merge(stats, true)
	return {"id": id, "name": "Ship %d" % id, "stats": full, "scrapping": scrapping}


func _fleet() -> Dictionary:
	return {
		"id": 7,
		"name": "Battle Fleet",
		"own": true,
		"in_system": true,
		"aggression": "obstructive",
		"ships":
		[
			_ship(70, 1, {"damage": 18.0, "structure": 4.0, "shield": 3.0}),
			_ship(71, 1, {"damage": 18.0, "fuel": 0.0, "speed": 60.0, "shield": 1.0}),
			_ship(72, 2, {"fighters": 2.0, "fighters_max": 6.0, "troops": 4.0}),
		],
		"merge_targets": [{"id": 8, "name": "Scout Fleet"}],
	}


func _panel(data: Dictionary) -> FleetPanel:
	var panel := FleetPanel.new()
	add_child_autofree(panel)
	panel.show_data(data)
	return panel


func test_totals_sum_average_and_take_the_lowest():
	var totals := FleetPanel.fleet_totals(_fleet()["ships"])
	assert_eq(totals["count"], 3)
	assert_eq(totals["damage"], 36.0)
	assert_eq(totals["fighters"], 2.0)
	assert_eq(totals["troops"], 4.0)
	assert_eq(totals["structure"], 24.0)
	assert_almost_eq(totals["shield"], 4.0 / 3.0, 0.001)
	assert_eq(totals["fuel"], 0.0, "lowest fuel")
	assert_eq(totals["speed"], 60.0, "slowest ship")


func test_totals_shown_with_icons():
	var panel := _panel(_fleet())
	var texts := panel._totals.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_has(texts, "36", "damage")
	assert_has(texts, "2/6", "fighters of most")
	assert_has(texts, "24/30", "structure of max")
	assert_false(texts.has("0"), "nothing shown for zero colonists")


func test_menu_offers_what_applies():
	var panel := _panel(_fleet())
	assert_eq(panel.menu_actions(), [0, 1, 2, 3, 4, 5, 6])
	var alone := _fleet()
	alone["merge_targets"] = []
	alone["in_system"] = false
	alone["ships"][0]["scrapping"] = true
	panel.show_data(alone)
	assert_eq(panel.menu_actions(), [7], "between systems only cancelling scrapping")
	var foreign := _fleet()
	foreign["own"] = false
	panel.show_data(foreign)
	assert_eq(panel.menu_actions(), [])


func test_splits_make_the_right_groups():
	var panel := _panel(_fleet())
	watch_signals(panel)
	panel.run_menu_action(1)
	assert_eq(get_signal_parameters(panel, "split_groups_requested")[0], [PackedInt32Array([70])])
	panel.run_menu_action(2)
	assert_eq(get_signal_parameters(panel, "split_groups_requested")[0], [PackedInt32Array([71])])
	panel.run_menu_action(3)
	assert_eq(get_signal_parameters(panel, "split_groups_requested")[0], [PackedInt32Array([72])])
	panel.run_menu_action(4)
	assert_eq(
		get_signal_parameters(panel, "split_groups_requested")[0],
		[PackedInt32Array([71]), PackedInt32Array([72])],
		"each ship but the first leaves"
	)
	panel.run_menu_action(5)
	assert_eq(
		get_signal_parameters(panel, "split_groups_requested")[0],
		[PackedInt32Array([72])],
		"each design but the first leaves"
	)


func test_merge_all_and_scrap_fleet():
	var panel := _panel(_fleet())
	watch_signals(panel)
	panel.run_menu_action(0)
	assert_signal_emitted_with_parameters(panel, "merge_all_requested", [7])
	var data := _fleet()
	data["ships"][1]["scrapping"] = true
	panel.show_data(data)
	panel.run_menu_action(6)
	assert_eq(get_signal_parameters(panel, "scrap_requested")[0], PackedInt32Array([70, 72]))
	panel.run_menu_action(7)
	assert_eq(get_signal_parameters(panel, "scrap_requested")[0], PackedInt32Array([71]))


func test_new_fleet_stance_from_the_menu():
	var panel := _panel(_fleet())
	watch_signals(panel)
	panel._fill_menu()
	var popup := panel._menu.get_popup()
	assert_eq(popup.item_count, 9, "seven actions, a separator and the stance submenu")
	panel._on_menu_id(FleetPanel.STANCE_MENU_BASE + 1)
	assert_eq(panel.new_fleet_stance, "passive")
	assert_signal_emitted_with_parameters(panel, "new_fleet_stance_changed", ["passive"])


func test_ship_rows_show_stats():
	var panel := _panel(_fleet())
	var row: Control = panel._ships.get_child(0)
	var texts := row.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_has(texts, "18", "damage")
	assert_has(texts, "3.0", "shield")
	assert_has(texts, "75", "speed")


func test_own_ships_are_renamed_in_place():
	var panel := ShipPanel.new()
	add_child_autofree(panel)
	panel.show_data({"id": 71, "name": "Pronghorn", "own": true})
	assert_true(panel._title.editable)
	watch_signals(panel)
	panel._title.text_submitted.emit("  Swift  ")
	assert_signal_emitted_with_parameters(panel, "rename_requested", [71, "Swift"])
	panel.show_data({"id": 72, "name": "Other", "own": false})
	assert_false(panel._title.editable)


func test_whole_fleet_drags_onto_another():
	var panel := SystemPanel.new()
	add_child_autofree(panel)
	var data: Variant = panel.fleet_drag_data(
		Vector2.ZERO, {"id": 7, "name": "A", "ship_ids": PackedInt32Array([70, 71])}
	)
	assert_eq(data["ship_ids"], PackedInt32Array([70, 71]))
	assert_true(panel.can_drop_ships(Vector2.ZERO, data, 8))
	assert_false(panel.can_drop_ships(Vector2.ZERO, data, 7), "not onto itself")
