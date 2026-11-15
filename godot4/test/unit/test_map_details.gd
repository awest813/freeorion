extends GutTest
## Map details: the options menu, owner colours, blockaded and stale
## fleets, the zoom slider, gifts and sensor ghosts in the panels.

var shell: GameShell


func before_each():
	shell = GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(2)
	(
		shell
		. map_view
		. map
		. set_snapshot(
			{
				"system_ids": PackedInt32Array([1, 2]),
				"system_positions": PackedVector2Array([Vector2(0, 0), Vector2(600, 0)]),
				"system_star_types": PackedInt32Array([1, 2]),
				"lanes": PackedInt32Array([0, 1]),
				"system_owner_colors": PackedColorArray([Color.BLUE, Color(0, 0, 0, 0)]),
				"fleet_ids": PackedInt32Array([10, 11]),
				"fleet_positions": PackedVector2Array([Vector2(0, 0), Vector2(600, 0)]),
				"fleet_owner_ids": PackedInt32Array([1, 2]),
				"fleet_blockaded": PackedByteArray([1, 0]),
				"fleet_stale": PackedByteArray([0, 1]),
			},
			PackedStringArray(["A", "B"]),
			PackedColorArray([Color.BLUE, Color.RED])
		)
	)


func test_menu_toggles_what_the_map_draws():
	var menu := shell.map_menu
	var map := shell.map_view.map
	menu.open_at(Vector2(100, 100))
	assert_eq(menu.item_count, MapMenu.TOGGLES.size())
	menu.hide()
	for option in [
		"ui.map.system.circle.shown",
		"ui.map.starlane.empire.color.shown",
		"ui.map.fleet.supply.shown",
		"ui.map.background.gas.shown",
		"ui.map.background.starfields.shown",
		"ui.map.fleet.eta.shown",
	]:
		menu.set_shown(option, false)
	assert_false(map.show_system_circles)
	assert_false(map.show_supply_lanes)
	assert_false(map.show_supply)
	assert_false(map.show_fields)
	assert_false(map.show_starfield)
	assert_false(map.fleets.show_paths)
	menu.set_shown("ui.map.zoom.slider.shown", true)
	assert_true(shell.zoom_slider.visible)
	menu._on_id_pressed(MapMenu._index("ui.map.zoom.slider.shown"))
	assert_false(shell.zoom_slider.visible, "the menu item toggles")


func test_right_click_on_empty_map_opens_the_menu():
	var map := shell.map_view.map
	watch_signals(map)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = map.camera.world_to_screen(Vector2(300, 300))
	map.camera.drag_distance = 0.0
	map._unhandled_input(release)
	assert_signal_emitted(map, "map_context_requested")


func test_blockaded_and_ghost_fleets():
	var fleets := shell.map_view.map.fleets
	assert_true(fleets.is_blockaded(10))
	assert_false(fleets.is_blockaded(11))
	var text := FleetPanel.blockade_text({"blockaded": true, "exits": PackedStringArray(["Vega"])})
	assert_string_contains(text, "Vega")
	assert_eq(FleetPanel.blockade_text({"blockaded": true}), tr("FB_TOOLTIP_BLOCKADE_NO_EXIT"))


func test_zoom_slider_follows_and_drives_the_camera():
	var camera := shell.map_view.map.camera
	shell.zoom_slider.value = 1.0
	await wait_process_frames(90)
	assert_almost_eq(camera.zoom_level(), camera.max_zoom, camera.max_zoom * 0.1)
	assert_almost_eq(shell.zoom_slider.value, 1.0, 0.05, "the slider follows the zoom")


func test_ghost_fleet_menu_and_gifts():
	var panel := FleetPanel.new()
	add_child_autofree(panel)
	panel.give_targets_provider = func(_id) -> Dictionary:
		return {"targets": [{"id": 4, "name": "Empire Red"}], "giving_to": -1}
	panel.show_data({"id": 7, "name": "Ghost", "own": false, "ghost": true, "ships": []})
	assert_true(panel._menu.visible, "ghosts can be dismissed")
	assert_eq(panel.menu_actions(), [10])
	watch_signals(panel)
	panel.run_menu_action(10)
	assert_signal_emitted_with_parameters(panel, "forget_requested", [7])
	panel.show_data({"id": 8, "name": "Mine", "own": true, "in_system": true, "ships": []})
	panel._fill_menu()
	var popup := panel._menu.get_popup()
	assert_ne(popup.get_item_index(FleetPanel.GIVE_MENU_BASE + 4), -1)
	panel._on_menu_id(FleetPanel.GIVE_MENU_BASE + 4)
	assert_signal_emitted_with_parameters(panel, "give_requested", [8, 4])


func test_planet_gifts_and_rename():
	var panel := PlanetPanel.new()
	add_child_autofree(panel)
	panel.give_targets_provider = func(_id) -> Dictionary:
		return {"targets": [{"id": 4, "name": "Empire Red"}], "giving_to": 4}
	panel.show_data({"id": 5, "name": "Home", "own": true})
	assert_true(panel._give.visible)
	assert_eq(panel.give_entries().map(func(e): return e[1]), [4, -1], "give, or cancel the gift")
	watch_signals(panel)
	panel._title.text_submitted.emit("Capital")
	assert_signal_emitted_with_parameters(panel, "rename_requested", [5, "Capital"])
	panel.show_data({"id": 6, "name": "Theirs", "own": false})
	assert_false(panel._give.visible)
	assert_false(panel._title.editable)
