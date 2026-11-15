extends GutTest
## ResearchScreen with an in-memory source.

const FakeSource := preload("res://test/unit/fake_research_source.gd")

var screen: ResearchScreen
var fake: RefCounted


func before_each():
	screen = ResearchScreen.new()
	fake = FakeSource.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)


func test_queue_and_points():
	assert_eq(screen._queue_list.get_child_count(), 2)
	assert_eq(
		screen._points.text, tr("RESEARCH_POINTS").replace("%1%", "4.5").replace("%2%", "7.5")
	)


func test_researchable_filter_sorted_by_cost():
	assert_eq(
		_catalog_names(),
		[
			tr("LRN_ALGO_ELEGANCE"),
			tr("GRO_PLANET_ECOL"),
			tr("PRO_ROBOTIC_PROD"),
			tr("SHP_ZORTRIUM_PLATE")
		]
	)


func test_open_and_complete_filters():
	screen._filter.current_tab = ResearchScreen.FILTERS.find("open")
	await wait_process_frames(1)
	assert_has(_catalog_names(), tr("SHP_WEAPON_1_2"), "Partly available techs are open")
	assert_does_not_have(_catalog_names(), tr("LRN_PHYS_BRAIN"))
	screen._filter.current_tab = ResearchScreen.FILTERS.find("complete")
	await wait_process_frames(1)
	assert_eq(_catalog_names(), [tr("LRN_PHYS_BRAIN")])


func test_category_and_search():
	var index := -1
	for i in screen._category.item_count:
		if screen._category.get_item_metadata(i) == "LEARNING_CATEGORY":
			index = i
	screen._category.select(index)
	screen._category.item_selected.emit(index)
	await wait_process_frames(1)
	assert_eq(_catalog_names(), [tr("LRN_ALGO_ELEGANCE")])
	screen._category.select(0)
	screen._category.item_selected.emit(0)
	screen._search.text = tr("SHP_ZORTRIUM_PLATE").substr(0, 5)
	screen._search.text_changed.emit(screen._search.text)
	await wait_process_frames(1)
	assert_has(_catalog_names(), tr("SHP_ZORTRIUM_PLATE"))


func test_queued_techs_cannot_be_added_again():
	var add := _button_in(screen._catalog.get_child(0), tr("RESEARCH_QUEUED"))
	assert_not_null(add)
	assert_true(add.disabled)
	assert_eq(add.text, tr("RESEARCH_QUEUED"))


func test_orders():
	var robotics := _row_for(tr("PRO_ROBOTIC_PROD"))
	_button_in(robotics, tr("PRODUCTION_ADD")).pressed.emit()
	_button_in(screen._queue_list.get_child(1), "▲").pressed.emit()
	_button_in(screen._queue_list.get_child(0), "✕").pressed.emit()
	assert_eq(
		fake.calls,
		[
			["enqueue", "PRO_ROBOTIC_PROD"],
			["move", "GRO_PLANET_ECOL", 0],
			["remove", "LRN_ALGO_ELEGANCE"],
		]
	)


func test_info_button_requests_pedia():
	watch_signals(screen)
	_button_in(_row_for(tr("PRO_ROBOTIC_PROD")), "?").pressed.emit()
	assert_signal_emitted_with_parameters(screen, "pedia_requested", ["tech", "PRO_ROBOTIC_PROD"])


func _catalog_names() -> Array:
	var names := []
	for row in screen._catalog.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 1:
			names.push_back(labels[0].text)
	return names


func _row_for(title: String) -> Node:
	for row in screen._catalog.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 0 and labels[0].text == title:
			return row
	return null


func _button_in(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null


func test_techs_missing_prerequisites_offer_them_too():
	screen._filter.current_tab = ResearchScreen.FILTERS.find("open")
	var labels: Array = (
		screen
		. find_children("*", "Button", true, false)
		. map(func(b): return b.text)
		. filter(func(t): return t == tr("RESEARCH_ADD_WITH_PREREQS"))
	)
	assert_eq(labels.size(), 1, "SHP_WEAPON_1_2 still needs its prerequisites")
