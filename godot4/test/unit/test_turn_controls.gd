extends GutTest
## End turn's menu, automatic turns, the ships tooltip, the wasted-PP
## shortcut, and double-clicks that open production.


func _bar() -> TopBar:
	var bar := TopBar.new()
	bar.follow_game = false
	add_child_autofree(bar)
	bar.set_state("Empire Blue", Color.BLUE, 12, false)
	return bar


func test_turn_menu_sends_or_revokes():
	var bar := _bar()
	bar.follow_game = true
	bar.order_count_provider = func() -> int: return 3
	bar.open_turn_menu()
	var menu: PopupMenu = bar._turn_menu
	assert_eq(menu.item_count, 2)
	assert_string_contains(menu.get_item_text(0), "3")
	assert_string_contains(menu.get_item_text(0), "12")
	assert_false(menu.is_item_disabled(1))
	watch_signals(bar)
	bar._on_turn_menu(1)
	assert_signal_emitted(bar, "revert_requested")
	menu.hide()
	bar.order_count_provider = func() -> int: return 0
	bar.open_turn_menu()
	assert_true(menu.is_item_disabled(1), "nothing to revoke")
	menu.hide()


func test_auto_end_turn_toggle():
	var bar := _bar()
	assert_false(bar.auto_end_turn)
	bar._auto_turn.button_pressed = true
	assert_true(bar.auto_end_turn)
	assert_eq(bar._auto_turn.tooltip_text, tr("MAP_BTN_AUTO_ADVANCE_ENABLED"))
	bar.set_auto_end_turn(false)
	assert_false(bar._auto_turn.button_pressed)


func test_ships_tooltip_counts_roles():
	var bar := _bar()
	bar.set_resources({"ships": 6, "ships_armed": 4, "ships_unarmed": 2, "ships_colony": 1})
	var tip: String = bar._resource_chips["ships"].tooltip_text
	assert_string_contains(tip, "%s: 4" % tr("MAP_FLEET_ARMED_COUNT"))
	assert_string_contains(tip, "%s: 1" % tr("MAP_FLEET_COLONY_COUNT"))


func test_wasted_industry_shows_where():
	var bar := _bar()
	watch_signals(bar)
	bar.set_resources({"industry": 10.0, "industry_spent": 4.0, "wasted_pp_system": 42})
	bar._resource_chips["industry"].pressed.emit()
	assert_signal_emitted_with_parameters(bar, "wasted_pp_requested", [42])
	assert_signal_not_emitted(bar, "screen_requested")
	bar.set_resources({"industry": 10.0, "industry_spent": 10.0, "wasted_pp_system": -1})
	bar._resource_chips["industry"].pressed.emit()
	assert_signal_emitted_with_parameters(bar, "screen_requested", ["production"])


func test_double_click_own_planet_builds_there():
	var panel := SystemPanel.new()
	add_child_autofree(panel)
	(
		panel
		. show_data(
			{
				"name": "Hegira",
				"planets":
				[{"id": 5, "name": "Hegira I", "own": true}, {"id": 6, "name": "Hegira II"}],
				"fleets": [],
			}
		)
	)
	watch_signals(panel)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	panel._planets.get_child(0).gui_input.emit(click)
	assert_signal_emitted_with_parameters(panel, "production_requested", [5])
	panel._planets.get_child(1).gui_input.emit(click)
	assert_signal_emit_count(panel, "production_requested", 1, "not for others' planets")
