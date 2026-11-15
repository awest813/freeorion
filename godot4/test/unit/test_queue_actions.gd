extends GutTest
## Production and research queues: the item menu, batch size, restoring
## removed items, Delete on a focused item, and pausing research.

const FakeProduction := preload("res://test/unit/fake_production_source.gd")
const FakeResearch := preload("res://test/unit/fake_research_source.gd")


func _production() -> ProductionScreen:
	var screen := ProductionScreen.new()
	screen.source = FakeProduction.new()
	add_child_autofree(screen)
	screen.refresh()
	return screen


func _research() -> ResearchScreen:
	var screen := ResearchScreen.new()
	screen.source = FakeResearch.new()
	add_child_autofree(screen)
	screen.refresh()
	return screen


func _delete() -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_DELETE
	key.pressed = true
	return key


func test_item_menu_offers_what_applies():
	var screen := _production()
	var queue: Array = screen.source.queue
	assert_eq(screen.item_actions(queue[0], 2), [1, 2, 7], "a building: down, copy, Pedia")
	var ship: Dictionary = queue[1].duplicate()
	ship["progress"] = 0.4
	ship["location_id"] = 101
	ship["rally_point_id"] = 12
	assert_eq(screen.item_actions(ship, 2), [0, 2, 3, 5, 6], "no rally target selected")
	screen.rally_target = func() -> Array: return [11, "Hegira β"]
	assert_has(screen.item_actions(ship, 2), 4)


func test_item_menu_orders():
	var screen := _production()
	var ship: Dictionary = screen.source.queue[1]
	screen.rally_target = func() -> Array: return [11, "Hegira β"]
	for id in [0, 1, 2, 3, 4, 5]:
		screen.run_item_action(id, ship, 2)
	assert_eq(
		screen.source.calls,
		[
			["move", 1, 0],
			["move", 1, 1],
			["duplicate", 1],
			["split_incomplete", 1],
			["set_rally_point", 1, 11],
			["set_rally_point", 1, -1],
		]
	)
	watch_signals(screen)
	screen.run_item_action(6, {"index": 0, "location_id": 101}, 2)
	assert_signal_emitted_with_parameters(screen, "location_requested", [101])


func test_batch_size_for_ships():
	var screen := _production()
	var row: Control = screen._queue_list.get_child(1)
	var spins := row.find_children("*", "SpinBox", true, false)
	assert_eq(spins.size(), 2, "quantity and batch size")
	spins[1].value = 3
	assert_has(screen.source.calls, ["set_blocksize", 1, 3])


func test_removed_items_can_be_restored():
	var screen := ProductionScreen.new()
	var fake := FakeProduction.new()
	fake.removed = [{"index": 4, "build_type": "building", "label": "BLD_GAS_GIANT_GEN"}]
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	var buttons := screen._removed_list.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 1)
	buttons[0].pressed.emit()
	assert_has(fake.calls, ["restore", 4])


func test_delete_removes_the_focused_item():
	var screen := _production()
	var card: Control = screen._queue_list.get_child(0)
	card.gui_input.emit(_delete())
	assert_has(screen.source.calls, ["remove", 0])
	var research := _research()
	var tech_card: Control = research._queue_list.get_child(0)
	tech_card.gui_input.emit(_delete())
	assert_eq(research.source.calls[-1][0], "remove")


func test_research_can_be_paused():
	var research := _research()
	var row: Control = research._queue_list.get_child(0)
	var pause: Button = null
	for button: Button in row.find_children("*", "Button", true, false):
		if button.text == "Ⅱ":
			pause = button
	assert_not_null(pause)
	pause.pressed.emit()
	var tech: String = research.source.queue[0]["name"]
	assert_eq(research.source.calls[-1], ["set_paused", tech, true])
