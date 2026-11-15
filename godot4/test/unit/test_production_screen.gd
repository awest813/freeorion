extends GutTest
## ProductionScreen with an in-memory source.

const FakeSource := preload("res://test/unit/fake_production_source.gd")

var screen: ProductionScreen
var fake: RefCounted


func before_each():
	screen = ProductionScreen.new()
	fake = FakeSource.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)


func test_queue_rows_and_points():
	assert_eq(screen._queue_list.get_child_count(), 2)
	assert_eq(
		screen._points.text, tr("PRODUCTION_POINTS").replace("%1%", "9.5").replace("%2%", "15.0")
	)
	var labels := _texts(screen._queue_list.get_child(1))
	assert_has(labels, "Outpost Ship")
	assert_has(labels, tr("PRODUCTION_NEVER"), "Unfunded item shows Never")


func test_first_location_selected_and_catalog_filled():
	assert_eq(screen.selected_location_id(), 101)
	assert_eq(
		_catalog_names(),
		[tr("BLD_SHIPYARD_BASE"), "Outpost Ship", "Scout", tr("PROJECT_BT_STOCKPILE")]
	)


func test_filter_and_search():
	screen._filter.current_tab = ProductionScreen.FILTERS.find("ship")
	await wait_process_frames(1)
	assert_eq(_catalog_names(), ["Outpost Ship", "Scout"])
	screen._search.text = "sco"
	screen._search.text_changed.emit("sco")
	await wait_process_frames(1)
	assert_eq(_catalog_names(), ["Scout"])


func test_other_location_without_items():
	screen.select_location(102)
	await wait_process_frames(1)
	assert_eq(_texts(screen._catalog), [tr("PRODUCTION_NOTHING_BUILDABLE")])


func test_add_remove_and_reorder_issue_orders():
	_button_in(screen._catalog.get_child(2), tr("PRODUCTION_ADD")).pressed.emit()
	_button_in(screen._queue_list.get_child(0), "▼").pressed.emit()
	_button_in(screen._queue_list.get_child(1), "✕").pressed.emit()
	assert_eq(fake.calls, [["enqueue", "Scout", 101], ["move", 0, 1], ["remove", 1]])
	assert_true(_button_in(screen._queue_list.get_child(0), "▲").disabled, "First can't move up")
	assert_true(_button_in(screen._queue_list.get_child(1), "▼").disabled, "Last can't move down")


func test_escape_requests_close():
	watch_signals(screen)
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	screen._unhandled_key_input(escape)
	assert_signal_emitted(screen, "close_requested")


func _catalog_names() -> Array:
	var names := []
	for row in screen._catalog.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 0:
			names.push_back(labels[0].text)
	return names


func _button_in(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null


func _texts(node: Node) -> Array:
	var texts := []
	for label in node.find_children("*", "Label", true, false):
		texts.push_back(label.text)
	return texts


func test_pause_and_stockpile_toggles():
	var running := screen._queue_list.get_child(0)
	var paused := screen._queue_list.get_child(1)
	assert_string_contains(" ".join(_texts(paused)), tr("PRODUCTION_PAUSED"))
	assert_lt(paused.modulate.a, 1.0, "Paused items are dimmed")
	_button_in(running, "Ⅱ").pressed.emit()
	_button_in(paused, "▶").pressed.emit()
	var toggles := running.find_children("*", "Button", true, false).filter(
		func(b): return b.toggle_mode
	)
	var stockpile: Button = toggles[0]
	stockpile.button_pressed = true
	assert_eq(
		fake.calls,
		[["set_paused", 0, true], ["set_paused", 1, false], ["set_stockpile_allowed", 0, true]]
	)


func test_stockpile_project_and_line():
	assert_string_contains(screen._stockpile.text, "PP")
	var names := _texts(screen._catalog)
	assert_has(names, tr("PROJECT_BT_STOCKPILE"), "The stockpile project is buildable")


func test_where_can_it_be_built():
	var scout_row := screen._catalog.get_child(2)
	_button_in(scout_row, "⌖").pressed.emit()
	var dialog: FODialog = screen.get_children().filter(func(c): return c is FODialog)[0]
	var checks: Array = dialog.find_children("*", "CheckBox", true, false)
	assert_eq(checks.map(func(c): return c.text), ["Hegira β I", "Mu Arae II", "Vega III"])
	assert_eq(
		checks.map(func(c): return c.button_pressed), [true, false, false], "Chosen location ticked"
	)
	checks[2].button_pressed = true
	dialog.choose(0)
	assert_eq(fake.calls, [["enqueue", "Scout", 101], ["enqueue", "Scout", 103]])


func test_where_dialog_cancel_adds_nothing():
	_button_in(screen._catalog.get_child(0), "⌖").pressed.emit()
	var dialog: FODialog = screen.get_children().filter(func(c): return c is FODialog)[0]
	dialog.choose(1)
	assert_eq(fake.calls, [])
