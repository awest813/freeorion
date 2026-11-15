extends GutTest
## The last parity items: the research tech menu, design order, forcing
## unavailable items into production, ship parts in the catalogue, sensor
## ghosts at a system, splitting off a design and the fleet status, map
## details (obstructed supply, shared systems, unseen fields) and the chat
## (history, Tab, other empires' wars and treaties).

const FakeProduction := preload("res://test/unit/fake_production_source.gd")
const FakeDesigner := preload("res://test/unit/fake_designer_source.gd")
const SystemPanelTest := preload("res://test/unit/test_system_panel.gd")


func test_tech_menu_entries_follow_the_tech():
	assert_eq(ResearchScreen.tech_menu_ids({"in_queue": true}), [0, 1, 2, 5])
	assert_eq(ResearchScreen.tech_menu_ids({"status": "researchable"}), [3, 4, 5])
	assert_eq(ResearchScreen.tech_menu_ids({"status": "complete"}), [5], "Done: Pedia only")


func test_designs_move_to_the_top():
	var screen := DesignerScreen.new()
	var fake: RefCounted = FakeDesigner.new()
	fake.designs["empire"].push_back(
		{"id": 9, "name": "Scout", "hull": "SH_BASIC_SMALL", "parts": PackedStringArray()}
	)
	screen.source = fake
	add_child_autofree(screen)
	screen.show_design_kind("empire")
	await wait_process_frames(1)
	var ids: Array = screen._design_ids
	assert_eq(ids, [7, 9])
	var menu: MenuButton = screen._design_list.get_child(1).get_child(1)
	menu.get_popup().id_pressed.emit(DesignerScreen.DesignAction.TOP)
	assert_has(fake.calls, ["move_design", ids[1], ids[0]])


func test_unavailable_items_can_be_forced_and_ships_list_parts():
	var screen := ProductionScreen.new()
	var fake: RefCounted = FakeProduction.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	screen.add_item({"label": "Shipyard", "build_type": "building", "available": false})
	assert_has(fake.calls.map(func(c): return c[0]), "enqueue_forced")
	assert_eq(
		ProductionScreen.parts_summary(["SR_WEAPON_1_1", "", "SR_WEAPON_1_1", "AR_STD_PLATE"]),
		"2× %s, %s" % [tr("SR_WEAPON_1_1"), tr("AR_STD_PLATE")]
	)
	var tip := screen.catalog_tooltip(
		{
			"label": "Warship",
			"build_type": "ship",
			"hull": "SH_BASIC_MEDIUM",
			"parts": ["AR_STD_PLATE"]
		}
	)
	assert_string_contains(tip, tr("AR_STD_PLATE"))


func test_sensor_ghosts_at_a_system_go_together():
	var panel := SystemPanel.new()
	add_child_autofree(panel)
	var data: Dictionary = SystemPanelTest.SAMPLE.duplicate(true)
	data["fleets"][2]["ghost"] = true
	panel.show_data(data)
	await wait_process_frames(1)
	watch_signals(panel)
	var forget: Button = panel._fleet_list.get_child(panel._fleet_list.get_child_count() - 1)
	assert_eq(forget.text, tr("FW_ORDER_DISMISS_SENSOR_GHOST_ALL"))
	forget.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "forget_requested", [PackedInt32Array([9])])


func test_fleet_status_says_how_far_and_why_waiting():
	var moving := {"destination": "Vega", "etas": {"final": 4, "next": 1}}
	var text := FleetPanel.route_text(moving)
	assert_string_contains(text, "Vega")
	assert_string_contains(text, tr("FLEET_PANEL_NEXT_SYSTEM").replace("%1%", ""))
	moving["etas"] = {"final": -3, "next": -3}
	assert_string_contains(FleetPanel.route_text(moving), tr("FW_FLEET_ETA_OUT_OF_RANGE"))
	var refuelling := {"exploring": true, "ships": [{"stats": {"fuel": 1.0, "max_fuel": 3.0}}]}
	assert_eq(FleetPanel.route_text(refuelling), tr("FW_FLEET_EXPLORING_REFUEL"))


func test_split_off_one_design():
	var panel := FleetPanel.new()
	panel.give_targets_provider = func(_id) -> Dictionary: return {}
	add_child_autofree(panel)
	var ships := [
		{"id": 1, "design": "Scout", "stats": {"design_id": 10}},
		{"id": 2, "design": "Warship", "stats": {"design_id": 20}},
		{"id": 3, "design": "Warship", "stats": {"design_id": 20}},
	]
	panel.show_data({"id": 7, "name": "Mixed", "own": true, "in_system": true, "ships": ships})
	panel._fill_menu()
	watch_signals(panel)
	panel._on_menu_id(FleetPanel.DESIGN_MENU_BASE + 20)
	assert_signal_emitted_with_parameters(
		panel, "split_groups_requested", [[PackedInt32Array([2, 3])]]
	)


func test_map_details_colours_and_drawing():
	var snapshot := {
		"system_owner_ids": PackedInt32Array([1, -1]),
		"system_owner_sets": [PackedInt32Array([1, 2]), PackedInt32Array()],
		"supply_obstructed": PackedInt32Array([0, 1]),
		"supply_obstructed_owners": PackedInt32Array([2]),
		"field_stale": PackedByteArray([1]),
	}
	var palette := {1: Color.BLUE, 2: Color.RED}
	MapDetails.add_colors(snapshot, func(id: int) -> Color: return palette.get(id, Color.WHITE))
	assert_eq(snapshot["system_owner_colors"][1].a, 0.0, "Unowned: no ring")
	assert_eq(snapshot["system_owner_set_colors"][0], PackedColorArray([Color.BLUE, Color.RED]))
	assert_eq(snapshot["supply_obstructed_colors"], PackedColorArray([Color.RED]))
	var details := MapDetails.new()
	details.set_snapshot(snapshot)
	var canvas := Control.new()
	canvas.size = Vector2(200, 200)
	canvas.draw.connect(
		func():
			var positions := PackedVector2Array([Vector2(20, 20), Vector2(180, 20)])
			var view := Rect2(0, 0, 200, 200)
			details.draw_obstructed(canvas, positions, view, 2.0)
			details.draw_owner_rings(
				canvas, positions, snapshot["system_owner_colors"], view, 8.0, 1.0
			)
			details.draw_scanlines(
				canvas, PackedVector2Array([Vector2(100, 100)]), PackedFloat32Array([40]), view, 1.0
			)
	)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	assert_true(is_instance_valid(canvas), "Drawn without errors")


func test_chat_history_and_tab_completion():
	var chat := ChatPanel.new()
	add_child_autofree(chat)
	chat._on_submitted("hello")
	chat._on_submitted("/pedia Ion Storm")
	chat.recall(-1)
	assert_eq(chat.input.text, "/pedia Ion Storm")
	chat.recall(-1)
	assert_eq(chat.input.text, "hello")
	chat.recall(1)
	chat.recall(1)
	assert_eq(chat.input.text, "", "Past the newest: empty again")
	var words := PackedStringArray(["/pm", "/pedia", "Alice", "Albert"])
	assert_eq(ChatPanel.complete("/pm Ali", 7, words), "/pm Alice ")
	assert_eq(ChatPanel.complete("Al", 2, words), "Al", "Alice or Albert: no more in common")
	assert_eq(ChatPanel.complete("/pe", 3, words), "/pedia ")


func test_wars_between_other_empires_are_logged():
	var known := {}
	var empires := [
		{"id": 1, "name": "Us", "own": true, "statuses": {2: "peace", 3: "peace"}},
		{"id": 2, "name": "Red", "statuses": {1: "peace", 3: "peace"}},
		{"id": 3, "name": "Green", "statuses": {1: "peace", 2: "peace"}},
	]
	assert_eq(MessageLog.diplomacy_changes(known, empires).size(), 0)
	empires[1]["statuses"][3] = "war"
	empires[2]["statuses"][2] = "war"
	var messages := MessageLog.diplomacy_changes(known, empires)
	assert_eq(messages.size(), 1, "Once per pair")
	assert_string_contains(messages[0], "Red")
	assert_string_contains(messages[0], "Green")
